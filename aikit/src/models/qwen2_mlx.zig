//! Native Zig forward pass for Qwen2(.5)-family causal LMs, on top of
//! `backend/mlx.zig`'s primitives — the "actual per-layer transformer",
//! as opposed to `examples/llm_spike.zig`'s single-tensor dequantize+matmul
//! proof of feasibility.
//!
//! Architecture (verified against the real checkpoint's `config.json` and
//! the real `model.safetensors` key/shape listing — not assumed from
//! memory; see `examples/llm_forward_pass.zig`'s doc comment for how):
//!   token embedding (quantized, tied to lm_head)
//!     -> N x { RMSNorm -> self-attn (GQA, RoPE, causal) -> residual
//!              -> RMSNorm -> SwiGLU MLP -> residual }
//!     -> final RMSNorm -> tied lm_head (quantized matmul) -> logits
//!
//! Every `nn.Linear` in the checkpoint (q/k/v/o proj, mlp gate/up/down,
//! the tied embedding) is 4-bit affine-quantized (`mlx_lm`/`mlx-community`
//! format: packed `uint32` weight + per-64-column `scales`/`biases`) —
//! run directly via `mlx_quantized_matmul` (`Array.linearQuantized`)
//! rather than dequantized to a full float matrix first, except for the
//! embedding *lookup* (gather then dequantize just the looked-up rows,
//! mirroring `mlx.nn.QuantizedEmbedding.__call__`).
//!
//! Qwen2 specifics that differ from a "generic" transformer and were
//! confirmed against the checkpoint/config rather than assumed:
//!   - q_proj/k_proj/v_proj each have a real (unquantized, fp16) additive
//!     bias vector (`*.bias`, singular — not to be confused with each
//!     quantized layer's `*.biases`, plural, which is the affine
//!     quantization zero-point, present on every quantized weight);
//!     o_proj and every MLP projection have no bias (`bias=False` in
//!     `mlx_lm`'s reference `qwen2.py`).
//!   - RoPE is applied to the *full* head dimension (dims=head_dim=64),
//!     non-traditional ("NeoX"-style) rotation (`rope_traditional`
//!     defaults to `false` and isn't overridden in this checkpoint's
//!     `config.json`), base = `rope_theta` = 1e6, scale = 1.0 (no
//!     `rope_scaling` block present).
//!   - GQA: 14 query heads, 2 KV heads, head_dim 64 (896/14) — MLX's fused
//!     `mlx_fast_scaled_dot_product_attention` tiles K/V internally, no
//!     manual repeat needed (see `backend/mlx.zig`'s `Array.attention`
//!     doc comment).
//!   - `tie_word_embeddings: true` (config.json, and no separate
//!     `lm_head.weight` key exists in the checkpoint) — logits come from
//!     running the *input* embedding table as a linear layer
//!     (`mlx.nn.QuantizedEmbedding.as_linear`), not a distinct weight.

const std = @import("std");
const mlx = @import("../backend/mlx.zig");

/// Architecture constants for `mlx-community/Qwen2.5-0.5B-Instruct-4bit`,
/// read from that checkpoint's real `config.json` (not assumed/guessed —
/// see this file's doc comment). A different Qwen2-family checkpoint would
/// need its own `Config` value; nothing here hardcodes these numbers
/// outside this struct's defaults.
pub const Config = struct {
    hidden_size: i32 = 896,
    num_hidden_layers: i32 = 24,
    intermediate_size: i32 = 4864,
    num_attention_heads: i32 = 14,
    num_key_value_heads: i32 = 2,
    vocab_size: i32 = 151936,
    rms_norm_eps: f32 = 1e-6,
    rope_theta: f32 = 1_000_000.0,
    /// From the checkpoint's `config.json` `"quantization"` block.
    quant_group_size: i32 = 64,
    quant_bits: i32 = 4,

    pub fn headDim(self: Config) i32 {
        return @divExact(self.hidden_size, self.num_attention_heads);
    }
};

pub const Model = struct {
    ckpt: mlx.Checkpoint,
    cfg: Config,

    pub fn init(ckpt: mlx.Checkpoint, cfg: Config) Model {
        return .{ .ckpt = ckpt, .cfg = cfg };
    }

    /// Formats a checkpoint key into `buf` (must outlive only the
    /// immediately-following `Checkpoint.get` call) and looks it up.
    fn getFmt(self: Model, buf: []u8, comptime fmt: []const u8, args: anytype) !mlx.Array {
        const key = try std.fmt.bufPrintSentinel(buf, fmt, args, 0);
        return self.ckpt.get(key);
    }

    /// One affine-quantized `nn.Linear`: `x @ w^T` via
    /// `mlx_quantized_matmul`, given `fmt` as the key prefix up to (not
    /// including) `.weight`/`.scales`/`.biases` — e.g.
    /// `"model.layers.{d}.self_attn.q_proj"`.
    fn quantLinear(self: Model, x: mlx.Array, comptime fmt: []const u8, args: anytype) !mlx.Array {
        var buf: [160]u8 = undefined;
        const w = try self.getFmt(&buf, fmt ++ ".weight", args);
        defer w.free();
        const scales = try self.getFmt(&buf, fmt ++ ".scales", args);
        defer scales.free();
        const biases = try self.getFmt(&buf, fmt ++ ".biases", args);
        defer biases.free();
        return mlx.Array.linearQuantized(x, w, scales, biases, self.cfg.quant_group_size, self.cfg.quant_bits);
    }

    /// Adds a real (unquantized) per-output-feature bias vector — only
    /// q_proj/k_proj/v_proj have one (see this file's doc comment).
    fn addBias(self: Model, x: mlx.Array, comptime fmt: []const u8, args: anytype) !mlx.Array {
        var buf: [160]u8 = undefined;
        const b = try self.getFmt(&buf, fmt, args);
        defer b.free();
        return x.add(b);
    }

    /// Splits a flat `[T, n_heads*head_dim]` projection output into
    /// `[1, n_heads, T, head_dim]` — the shape MLX's fused RoPE/attention
    /// ops expect (`(B, *, T, D)`).
    fn splitHeads(x: mlx.Array, seq_len: i32, n_heads: i32, head_dim: i32) mlx.Array {
        const r = x.reshape(&[_]i32{ 1, seq_len, n_heads, head_dim });
        defer r.free();
        return r.transposeAxes(&[_]i32{ 0, 2, 1, 3 });
    }

    /// Runs the full forward pass for `token_ids` (a single sequence, no
    /// batching, no KV cache — that's the next phase) and returns logits
    /// for *only the last position*, shape `[1, vocab_size]`. Caller owns
    /// the returned `Array` (`.free()`).
    pub fn forward(self: Model, token_ids: []const i32) !mlx.Array {
        const cfg = self.cfg;
        const seq_len: i32 = @intCast(token_ids.len);
        const head_dim = cfg.headDim();
        const scale: f32 = 1.0 / std.math.sqrt(@as(f32, @floatFromInt(head_dim)));

        const idx = mlx.Array.fromInt32(token_ids, &[_]i32{seq_len});
        defer idx.free();

        // --- Token embedding: gather the small [T, *] row slices out of
        // the quantized embedding table, then dequantize just those (not
        // the full 151936-row table) — mirrors
        // `mlx.nn.QuantizedEmbedding.__call__`.
        var kbuf: [160]u8 = undefined;
        const embed_w = try self.getFmt(&kbuf, "model.embed_tokens.weight", .{});
        defer embed_w.free();
        const embed_s = try self.getFmt(&kbuf, "model.embed_tokens.scales", .{});
        defer embed_s.free();
        const embed_b = try self.getFmt(&kbuf, "model.embed_tokens.biases", .{});
        defer embed_b.free();

        const w_rows = mlx.Array.embedding(embed_w, idx);
        defer w_rows.free();
        const s_rows = mlx.Array.embedding(embed_s, idx);
        defer s_rows.free();
        const b_rows = mlx.Array.embedding(embed_b, idx);
        defer b_rows.free();

        var h = mlx.Array.dequantizeAffine(w_rows, s_rows, b_rows, cfg.quant_group_size, cfg.quant_bits); // [T, hidden]

        var layer: i32 = 0;
        while (layer < cfg.num_hidden_layers) : (layer += 1) {
            const ln1_w = try self.getFmt(&kbuf, "model.layers.{d}.input_layernorm.weight", .{layer});
            const normed = mlx.Array.rmsNorm(h, ln1_w, cfg.rms_norm_eps);
            ln1_w.free();

            // --- Self-attention (GQA + RoPE) ---
            const q_flat = try self.quantLinear(normed, "model.layers.{d}.self_attn.q_proj", .{layer});
            const q_biased = try self.addBias(q_flat, "model.layers.{d}.self_attn.q_proj.bias", .{layer});
            q_flat.free();
            const k_flat = try self.quantLinear(normed, "model.layers.{d}.self_attn.k_proj", .{layer});
            const k_biased = try self.addBias(k_flat, "model.layers.{d}.self_attn.k_proj.bias", .{layer});
            k_flat.free();
            const v_flat = try self.quantLinear(normed, "model.layers.{d}.self_attn.v_proj", .{layer});
            const v_biased = try self.addBias(v_flat, "model.layers.{d}.self_attn.v_proj.bias", .{layer});
            v_flat.free();
            normed.free();

            const q_h = splitHeads(q_biased, seq_len, cfg.num_attention_heads, head_dim);
            q_biased.free();
            const k_h = splitHeads(k_biased, seq_len, cfg.num_key_value_heads, head_dim);
            k_biased.free();
            const v_h = splitHeads(v_biased, seq_len, cfg.num_key_value_heads, head_dim);
            v_biased.free();

            const q_rope = mlx.Array.rope(q_h, head_dim, false, cfg.rope_theta, 1.0, 0);
            q_h.free();
            const k_rope = mlx.Array.rope(k_h, head_dim, false, cfg.rope_theta, 1.0, 0);
            k_h.free();

            const attn = mlx.Array.attention(q_rope, k_rope, v_h, scale, true); // [1, n_heads, T, head_dim]
            q_rope.free();
            k_rope.free();
            v_h.free();

            const attn_t = attn.transposeAxes(&[_]i32{ 0, 2, 1, 3 }); // [1, T, n_heads, head_dim]
            attn.free();
            const attn_flat = attn_t.reshape(&[_]i32{ seq_len, cfg.hidden_size });
            attn_t.free();

            const attn_out = try self.quantLinear(attn_flat, "model.layers.{d}.self_attn.o_proj", .{layer}); // no bias
            attn_flat.free();

            const h_attn = h.add(attn_out);
            attn_out.free();
            h.free();
            h = h_attn;

            // --- SwiGLU MLP ---
            const ln2_w = try self.getFmt(&kbuf, "model.layers.{d}.post_attention_layernorm.weight", .{layer});
            const normed2 = mlx.Array.rmsNorm(h, ln2_w, cfg.rms_norm_eps);
            ln2_w.free();

            const gate = try self.quantLinear(normed2, "model.layers.{d}.mlp.gate_proj", .{layer});
            const up = try self.quantLinear(normed2, "model.layers.{d}.mlp.up_proj", .{layer});
            normed2.free();

            const gate_act = gate.silu();
            gate.free();
            const swiglu = gate_act.mul(up);
            gate_act.free();
            up.free();

            const down = try self.quantLinear(swiglu, "model.layers.{d}.mlp.down_proj", .{layer});
            swiglu.free();

            const h_mlp = h.add(down);
            down.free();
            h.free();
            h = h_mlp;
        }

        const norm_w = try self.getFmt(&kbuf, "model.norm.weight", .{});
        const h_normed = mlx.Array.rmsNorm(h, norm_w, cfg.rms_norm_eps);
        norm_w.free();
        h.free();

        // Only the last position's hidden state determines the
        // next-token distribution — slice before the (otherwise
        // full-vocab-width) lm_head matmul.
        const last = h_normed.slice(
            &[_]i32{ seq_len - 1, 0 },
            &[_]i32{ seq_len, cfg.hidden_size },
            null,
        );
        h_normed.free();

        // Tied lm_head: run the embedding table as a quantized linear
        // layer (`mlx.nn.QuantizedEmbedding.as_linear`).
        const logits = mlx.Array.linearQuantized(last, embed_w, embed_s, embed_b, cfg.quant_group_size, cfg.quant_bits);
        last.free();
        return logits; // [1, vocab_size]
    }
};
