//! Phase 1 of native LLM inference (the actual per-layer forward pass,
//! following on from `examples/llm_spike.zig`'s single-tensor
//! dequantize+matmul proof of feasibility and the tokenizer built in the
//! phase before this one). Loads a REAL `mlx-community/Qwen2.5-0.5B-
//! Instruct-4bit` checkpoint end to end — real `tokenizer.json` BPE
//! encoding, real weights for all 24 transformer layers (not just layer
//! 0), a real `models/qwen2_mlx.zig` forward pass — and prints the top-5
//! next-token predictions for the prompt "The capital of France is", the
//! same thing the Python (`mlx_lm`) reference oracle reported:
//!
//!   | id    | text      | logit     | prob     |
//!   |-------|-----------|-----------|----------|
//!   | 12095 | ' Paris'  | 17.937500 | 0.488592 |
//!   | 32671 | ' ______' | 16.171875 | 0.083588 |
//!   | 7407  | ' located'| 16.046875 | 0.073766 |
//!   | 264   | ' a'      | 15.781250 | 0.056559 |
//!   | 279   | ' the'    | 15.750000 | 0.054819 |
//!
//! No KV cache / multi-token generation here — single forward pass,
//! single set of logits over the full prompt. That's the next phase.
//!
//! Run: zig build run-llm-forward-pass \
//!        -Dllm-model-dir=/path/to/mlx-community--Qwen2.5-0.5B-Instruct-4bit/snapshot
//! (must contain both `tokenizer.json` and `model.safetensors`; defaults
//! to the real checkpoint this repo's other LLM-phase tests were built
//! against, if present at that fixed path.)

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const aikit = @import("aikit");
const mlx = aikit.backend.mlx;
const qwen2 = aikit.models.qwen2_mlx;

comptime {
    if (builtin.os.tag != .macos) @compileError("macOS-only (MLX)");
}

const Prediction = struct { id: u32, logit: f32 };

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const model_dir = build_options.model_dir;
    if (model_dir.len == 0) {
        std.debug.print("usage: zig build run-llm-forward-pass -Dllm-model-dir=<dir containing tokenizer.json + model.safetensors>\n", .{});
        return error.MissingArg;
    }

    var tokenizer_path_buf: [4096]u8 = undefined;
    const tokenizer_path = try std.fmt.bufPrint(&tokenizer_path_buf, "{s}/tokenizer.json", .{model_dir});

    var weights_path_buf: [4096]u8 = undefined;
    const weights_path = try std.fmt.bufPrintSentinel(&weights_path_buf, "{s}/model.safetensors", .{model_dir}, 0);

    // --- Tokenize the prompt with the real BPE tokenizer ---
    var threaded_io = std.Io.Threaded.init(gpa, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    var tok = try aikit.tokenizer.Tokenizer.initFromFile(gpa, io, tokenizer_path);
    defer tok.deinit();

    const prompt = "The capital of France is";
    const ids32 = try tok.encode(gpa, prompt);
    defer gpa.free(ids32);

    std.debug.print("prompt: \"{s}\"\n", .{prompt});
    std.debug.print("token ids ({d}): {any}\n", .{ ids32.len, ids32 });

    const ids_i32 = try gpa.alloc(i32, ids32.len);
    defer gpa.free(ids_i32);
    for (ids32, ids_i32) |id, *out| out.* = @intCast(id);

    // --- Load the real checkpoint and run the real forward pass ---
    const ckpt = mlx.Checkpoint.load(weights_path) catch {
        std.debug.print("mlx_load_safetensors FAILED for {s}\n", .{weights_path});
        return error.LoadFailed;
    };
    std.debug.print("checkpoint loaded: {s}\n", .{weights_path});

    const model = qwen2.Model.init(ckpt, .{});
    const logits = try model.forward(ids_i32);
    defer logits.free();
    logits.eval();

    const shape = logits.shape();
    std.debug.print("logits shape: [{d},{d}]\n", .{ shape[0], shape[1] });
    const vocab_size: usize = @intCast(shape[1]);

    const logits_host = try gpa.alloc(f32, vocab_size);
    defer gpa.free(logits_host);
    logits.asFloat32(logits_host);

    // --- Top-5 by logit, plus softmax probability over the full vocab ---
    var max_logit: f32 = -std.math.inf(f32);
    for (logits_host) |v| max_logit = @max(max_logit, v);
    var sum_exp: f64 = 0;
    for (logits_host) |v| sum_exp += @exp(@as(f64, v - max_logit));

    var top: [5]Prediction = @splat(.{ .id = 0, .logit = -std.math.inf(f32) });
    for (logits_host, 0..) |v, i| {
        if (v <= top[4].logit) continue;
        var pos: usize = 4;
        while (pos > 0 and top[pos - 1].logit < v) : (pos -= 1) {
            top[pos] = top[pos - 1];
        }
        top[pos] = .{ .id = @intCast(i), .logit = v };
    }

    std.debug.print("\ntop-5 next-token predictions:\n", .{});
    std.debug.print("{s: <8} {s: <12} {s: <10}\n", .{ "id", "logit", "prob" });
    for (top) |p| {
        const prob = @exp(@as(f64, p.logit - max_logit)) / sum_exp;
        std.debug.print("{d: <8} {d: <12.6} {d: <10.6}\n", .{ p.id, p.logit, prob });
    }
}
