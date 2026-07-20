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
const llm = @import("../capabilities/llm.zig");
const tokenizer_mod = @import("../tokenizer.zig");

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
    /// `config.json`'s `eos_token_id` (`<|im_end|>` for this checkpoint) —
    /// `Model.generate`'s default stop token. Additive field for KV-cache
    /// generation support; doesn't change `forward`'s verified behavior
    /// (nothing in `forward` reads it).
    eos_token_id: u32 = 151645,

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

    /// Cache-aware forward pass: like `forward` above, but only computes
    /// attention K/V for `token_ids` (the *new* tokens — the full prompt
    /// on the first call/prefill, exactly one token per call thereafter)
    /// and attends them against `cache`'s already-computed prefix,
    /// appending this step's K/V into `cache` before returning — an
    /// autoregressive decode step only pays for the new token(s), not the
    /// whole sequence again.
    ///
    /// RoPE for the new tokens is applied starting at `cache.len()` (the
    /// absolute sequence position they begin at), per `mlx_fast_rope`'s
    /// `offset` param (see `backend/mlx.zig`'s doc comment) — this is a
    /// correctness requirement, not just performance: the rotation angle
    /// depends on absolute position, and a decode step's "position 0"
    /// isn't the sequence's actual position 0.
    ///
    /// Causal masking is only applied when `token_ids.len() > 1`
    /// (prefill, where later prompt tokens must not attend to earlier
    /// ones' *future* selves within the same call). A single new decode
    /// token needs no mask at all — it trivially attends to everything
    /// already cached (all of which precedes it) plus itself, matching
    /// `mlx_lm`'s own `create_attention_mask` (which skips masking
    /// entirely for length-1 decode steps). This only supports the
    /// prefill-then-one-token-at-a-time call pattern `generate` below
    /// uses — not chunked/multi-token decode steps after the first call.
    ///
    /// Returns logits for the *last* position only, `[1, vocab_size]` —
    /// same contract as `forward`. Caller owns the returned `Array`
    /// (`.free()`).
    pub fn forwardStep(self: Model, token_ids: []const i32, cache: *KVCache) !mlx.Array {
        const cfg = self.cfg;
        const seq_len: i32 = @intCast(token_ids.len);
        const head_dim = cfg.headDim();
        const scale: f32 = 1.0 / std.math.sqrt(@as(f32, @floatFromInt(head_dim)));
        const offset = cache.len();
        const causal = token_ids.len > 1;

        const idx = mlx.Array.fromInt32(token_ids, &[_]i32{seq_len});
        defer idx.free();

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

            // --- Self-attention (GQA + RoPE), cache-aware ---
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

            const q_rope = mlx.Array.rope(q_h, head_dim, false, cfg.rope_theta, 1.0, offset);
            q_h.free();
            const k_rope = mlx.Array.rope(k_h, head_dim, false, cfg.rope_theta, 1.0, offset);
            k_h.free();

            // Append this step's (already-rotated) K/V into the cache and
            // attend against the full (old+new) result. `cache.append`
            // takes ownership of `k_rope`/`v_h` — they must not be freed
            // here.
            const kv = cache.append(@intCast(layer), k_rope, v_h);

            const attn = mlx.Array.attention(q_rope, kv.k, kv.v, scale, causal); // [1, n_heads, T, head_dim]
            q_rope.free();
            // kv.k / kv.v are owned by `cache` (kept for future steps) —
            // not freed here, unlike `forward`'s single-pass k_rope/v_h.

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

        const last = h_normed.slice(
            &[_]i32{ seq_len - 1, 0 },
            &[_]i32{ seq_len, cfg.hidden_size },
            null,
        );
        h_normed.free();

        const logits = mlx.Array.linearQuantized(last, embed_w, embed_s, embed_b, cfg.quant_group_size, cfg.quant_bits);
        last.free();
        return logits; // [1, vocab_size]
    }

    pub const GenerateOptions = struct {
        max_new_tokens: usize = 64,
        /// Stop (without including the stop token in the returned ids)
        /// once this token id is generated. `null` disables early
        /// stopping — generation always runs the full `max_new_tokens`.
        eos_token_id: ?u32 = null,
    };

    /// Greedy (argmax, deterministic) autoregressive generation on top of
    /// `forwardStep`'s KV cache. Runs prefill on `prompt_ids`, then
    /// repeatedly: sample (argmax) the next token, stop if it's
    /// `options.eos_token_id`, otherwise append it and feed it back in as
    /// the next decode step — until `options.max_new_tokens` tokens have
    /// been produced or the eos check fires. Deterministic and directly
    /// comparable to a Python greedy-decode reference (see
    /// `examples/llm_generate.zig`); temperature/top-p sampling is a
    /// documented follow-up, not implemented here. Caller owns the
    /// returned slice.
    pub fn generate(self: Model, allocator: std.mem.Allocator, prompt_ids: []const i32, options: GenerateOptions) ![]u32 {
        var cache = try KVCache.init(allocator, @intCast(self.cfg.num_hidden_layers));
        defer cache.deinit();

        var out: std.ArrayList(u32) = .empty;
        errdefer out.deinit(allocator);

        var logits = try self.forwardStep(prompt_ids, &cache);
        var next_id = try argmax(allocator, logits);
        logits.free();

        var step: usize = 0;
        while (step < options.max_new_tokens) : (step += 1) {
            if (options.eos_token_id) |eos| {
                if (next_id == eos) break;
            }
            try out.append(allocator, next_id);

            const next_i32: i32 = @intCast(next_id);
            logits = try self.forwardStep(&[_]i32{next_i32}, &cache);
            next_id = try argmax(allocator, logits);
            logits.free();
        }

        return out.toOwnedSlice(allocator);
    }
};

/// KV cache for autoregressive generation — one entry per transformer
/// layer, storing the keys/values accumulated across `Model.forwardStep`
/// calls so a decode step only computes attention for the *new* token(s)
/// against the already-computed prefix, instead of recomputing the whole
/// sequence every step (both a correctness requirement — see
/// `forwardStep`'s doc comment on RoPE offsets — and a performance one).
pub const KVCache = struct {
    allocator: std.mem.Allocator,
    layers: []LayerCache,

    const LayerCache = struct {
        k: ?mlx.Array = null,
        v: ?mlx.Array = null,
    };

    pub fn init(allocator: std.mem.Allocator, num_layers: usize) !KVCache {
        const layers = try allocator.alloc(LayerCache, num_layers);
        for (layers) |*l| l.* = .{};
        return .{ .allocator = allocator, .layers = layers };
    }

    pub fn deinit(self: *KVCache) void {
        for (self.layers) |*l| {
            if (l.k) |k| k.free();
            if (l.v) |v| v.free();
        }
        self.allocator.free(self.layers);
    }

    /// Number of positions already cached (same across every layer, since
    /// every `forwardStep` call appends to all layers together). 0 before
    /// the first call (prefill).
    pub fn len(self: KVCache) i32 {
        const first = self.layers[0].k orelse return 0;
        return first.shape()[2]; // [1, n_kv_heads, T, head_dim]
    }

    /// Appends this layer's newly-computed keys/values (shape `[1,
    /// n_kv_heads, T_new, head_dim]`) onto whatever's already cached for
    /// `layer_idx` (concatenated along the sequence axis, axis 2),
    /// returning the full (old+new) keys/values to attend over. Takes
    /// ownership of `new_k`/`new_v` — frees the old cached arrays and the
    /// just-passed-in new ones once concatenated into the replacement
    /// (mirrors `backend/mlx.zig`'s `Array.concat` doc comment, which
    /// names exactly this use case); callers must not free `new_k`/
    /// `new_v` themselves.
    pub fn append(self: *KVCache, layer_idx: usize, new_k: mlx.Array, new_v: mlx.Array) struct { k: mlx.Array, v: mlx.Array } {
        const l = &self.layers[layer_idx];
        if (l.k) |old_k| {
            const old_v = l.v.?;
            const full_k = mlx.Array.concat(&.{ old_k, new_k }, 2);
            const full_v = mlx.Array.concat(&.{ old_v, new_v }, 2);
            old_k.free();
            old_v.free();
            new_k.free();
            new_v.free();
            l.k = full_k;
            l.v = full_v;
        } else {
            l.k = new_k;
            l.v = new_v;
        }
        return .{ .k = l.k.?, .v = l.v.? };
    }
};

/// Reads `logits` (`[1, vocab_size]`) back to the host and returns the
/// argmax index — greedy/deterministic next-token selection. `logits`
/// isn't freed here (matches `Array`'s general ownership convention —
/// callers free what they created); `generate` above frees it right after
/// this call.
fn argmax(allocator: std.mem.Allocator, logits: mlx.Array) !u32 {
    logits.eval();
    const shape = logits.shape();
    const vocab: usize = @intCast(shape[shape.len - 1]);
    const host = try allocator.alloc(f32, vocab);
    defer allocator.free(host);
    logits.asFloat32(host);

    var best_idx: usize = 0;
    var best_val: f32 = -std.math.inf(f32);
    for (host, 0..) |v, i| {
        if (v > best_val) {
            best_val = v;
            best_idx = i;
        }
    }
    return @intCast(best_idx);
}

/// A loaded checkpoint + tokenizer, ready for full text-in/text-out
/// generation via `capabilities/llm.zig`'s `Generator` interface — the
/// LLM-capability counterpart to `models/qwen3_tts.zig`'s `Qwen3TTS` for
/// TTS. `Model`/`KVCache` above are template-agnostic (raw token ids in,
/// raw token ids out); this wrapper is *Instruct*-checkpoint-specific — it
/// applies the ChatML turn template
/// (`<|im_start|>role\n...<|im_end|>\n`) this checkpoint's own
/// `tokenizer_config.json` documents (`mlx-community/Qwen2.5-0.5B-
/// Instruct-4bit`'s chat_template), because running an instruct-tuned
/// checkpoint on a raw, unformatted prompt produces a text *continuation*
/// (what `examples/llm_forward_pass.zig`/`examples/llm_generate.zig`
/// deliberately exercise, to compare against the Python reference) rather
/// than an assistant *response* — the behavior metanoia's app integration
/// actually wants in place of Ollama.
pub const Qwen2LLM = struct {
    allocator: std.mem.Allocator,
    ckpt: mlx.Checkpoint,
    tok: tokenizer_mod.Tokenizer,
    cfg: Config,

    /// `model_dir` must contain `tokenizer.json` + `model.safetensors`
    /// (same expectation as `examples/llm_forward_pass.zig`). `io` follows
    /// this codebase's threaded-`std.Io` convention — only the tokenizer
    /// load needs it (checkpoint loading goes through MLX's own,
    /// synchronous `mlx_load_safetensors`).
    pub fn init(allocator: std.mem.Allocator, io: std.Io, model_dir: []const u8, cfg: Config) !Qwen2LLM {
        var tok_path_buf: [4096]u8 = undefined;
        const tokenizer_path = try std.fmt.bufPrint(&tok_path_buf, "{s}/tokenizer.json", .{model_dir});
        var tok = try tokenizer_mod.Tokenizer.initFromFile(allocator, io, tokenizer_path);
        errdefer tok.deinit();

        var weights_buf: [4096]u8 = undefined;
        const weights_path = try std.fmt.bufPrintSentinel(&weights_buf, "{s}/model.safetensors", .{model_dir}, 0);
        const ckpt = try mlx.Checkpoint.load(weights_path);

        return .{ .allocator = allocator, .ckpt = ckpt, .tok = tok, .cfg = cfg };
    }

    pub fn deinit(self: *Qwen2LLM) void {
        self.tok.deinit();
    }

    pub fn generator(self: *Qwen2LLM) llm.Generator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable = llm.Generator.VTable{
        .generate = generateImpl,
        .deinit = deinitImpl,
    };

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Qwen2LLM = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn generateImpl(ptr: *anyopaque, allocator: std.mem.Allocator, prompt: []const u8, options: llm.GenerateOptions) llm.GenerateError![]const u8 {
        const self: *Qwen2LLM = @ptrCast(@alignCast(ptr));
        return self.generateText(allocator, prompt, options) catch |err| switch (err) {
            error.OutOfMemory => llm.GenerateError.OutOfMemory,
            else => llm.GenerateError.BackendFailure,
        };
    }

    /// Formats `prompt` as a single-turn ChatML user message (see this
    /// struct's doc comment), runs greedy generation via `Model.generate`,
    /// and decodes the result back to text. The eos token (`<|im_end|>`)
    /// is excluded from generation's returned ids (see
    /// `Model.GenerateOptions.eos_token_id`), so nothing needs stripping
    /// afterward.
    pub fn generateText(self: *Qwen2LLM, allocator: std.mem.Allocator, prompt: []const u8, options: llm.GenerateOptions) ![]const u8 {
        const chat_prompt = try std.fmt.allocPrint(
            allocator,
            "<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n<|im_start|>user\n{s}<|im_end|>\n<|im_start|>assistant\n",
            .{prompt},
        );
        defer allocator.free(chat_prompt);

        const prompt_ids32 = try self.tok.encode(allocator, chat_prompt);
        defer allocator.free(prompt_ids32);

        const prompt_ids = try allocator.alloc(i32, prompt_ids32.len);
        defer allocator.free(prompt_ids);
        for (prompt_ids32, prompt_ids) |id, *out| out.* = @intCast(id);

        const model = Model.init(self.ckpt, self.cfg);
        const gen_ids = try model.generate(allocator, prompt_ids, .{
            .max_new_tokens = options.max_new_tokens,
            .eos_token_id = self.cfg.eos_token_id,
        });
        defer allocator.free(gen_ids);

        return self.tok.decode(allocator, gen_ids);
    }
};

// --- Tests ---------------------------------------------------------------

test "KVCache.append concatenates along the sequence axis and updates len()" {
    var cache = try KVCache.init(std.testing.allocator, 1);
    defer cache.deinit();

    try std.testing.expectEqual(@as(i32, 0), cache.len());

    // Shape (B=1, n_kv_heads=1, T=2, D=1): two "positions" worth of K/V.
    const k1_data = [_]f32{ 1.0, 2.0 };
    const v1_data = [_]f32{ 10.0, 20.0 };
    const k1 = mlx.Array.fromFloat32(&k1_data, &[_]i32{ 1, 1, 2, 1 });
    const v1 = mlx.Array.fromFloat32(&v1_data, &[_]i32{ 1, 1, 2, 1 });

    const first = cache.append(0, k1, v1);
    try std.testing.expectEqual(@as(i32, 2), cache.len());
    var out1: [2]f32 = undefined;
    first.k.asFloat32(&out1);
    try std.testing.expectEqualSlices(f32, &k1_data, &out1);

    // Appending one more position should concatenate onto the existing 2,
    // giving 3 total.
    const k2_data = [_]f32{3.0};
    const v2_data = [_]f32{30.0};
    const k2 = mlx.Array.fromFloat32(&k2_data, &[_]i32{ 1, 1, 1, 1 });
    const v2 = mlx.Array.fromFloat32(&v2_data, &[_]i32{ 1, 1, 1, 1 });

    const second = cache.append(0, k2, v2);
    try std.testing.expectEqual(@as(i32, 3), cache.len());
    var out2: [3]f32 = undefined;
    second.k.asFloat32(&out2);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 1.0, 2.0, 3.0 }, &out2);
    var out2v: [3]f32 = undefined;
    second.v.asFloat32(&out2v);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 10.0, 20.0, 30.0 }, &out2v);
}

const qwen25_model_dir = "/Users/fource/.cache/huggingface/hub/models--mlx-community--Qwen2.5-0.5B-Instruct-4bit/snapshots/a5339a4131f135d0fdc6a5c8b5bbed2753bbe0f3";

// Real end-to-end verification of `Model.generate`'s KV-cache-based
// greedy decoding against a real checkpoint, compared token-by-token to
// a Python `mlx_lm` reference oracle (`mlx_lm.generate.stream_generate`,
// greedy/no sampler) for the prompt "The capital of France is":
//   [12095, 13, 1084, 374, 279, 7772, 3283, 304, 279, 1879]
//   -> " Paris. It is the largest city in the world"
// Loads the real checkpoint (~265MB) — skips (not fails) if it isn't
// present at the fixed path this repo's other LLM-phase tests use.
test "Model.generate matches the Python mlx_lm greedy-decode reference for \"The capital of France is\"" {
    const gpa = std.testing.allocator;
    var threaded_io = std.Io.Threaded.init(gpa, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    var tok = tokenizer_mod.Tokenizer.initFromFile(gpa, io, qwen25_model_dir ++ "/tokenizer.json") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer tok.deinit();

    const prompt_ids32 = try tok.encode(gpa, "The capital of France is");
    defer gpa.free(prompt_ids32);
    const prompt_ids = try gpa.alloc(i32, prompt_ids32.len);
    defer gpa.free(prompt_ids);
    for (prompt_ids32, prompt_ids) |id, *out| out.* = @intCast(id);

    const ckpt = mlx.Checkpoint.load(qwen25_model_dir ++ "/model.safetensors") catch return error.SkipZigTest;
    const model = Model.init(ckpt, .{});

    const gen_ids = try model.generate(gpa, prompt_ids, .{ .max_new_tokens = 10, .eos_token_id = 151645 });
    defer gpa.free(gen_ids);

    const expected = [_]u32{ 12095, 13, 1084, 374, 279, 7772, 3283, 304, 279, 1879 };
    try std.testing.expectEqualSlices(u32, &expected, gen_ids);

    const text = try tok.decode(gpa, gen_ids);
    defer gpa.free(text);
    try std.testing.expectEqualStrings(" Paris. It is the largest city in the world", text);
}
