//! Phase 2 of native LLM inference: real multi-token autoregressive
//! generation via `models/qwen2_mlx.zig`'s KV-cache-based `Model.generate`
//! (following on from `examples/llm_forward_pass.zig`'s single-forward-pass
//! demo, which only computed logits for one next token). Loads the real
//! `mlx-community/Qwen2.5-0.5B-Instruct-4bit` checkpoint, greedily
//! generates 10 tokens for the prompt "The capital of France is" (no chat
//! template — a raw completion, deliberately mirroring the Python
//! `mlx_lm` reference oracle exactly so the two are directly comparable),
//! and checks the result against that oracle's real output:
//!
//!   ids:  [12095, 13, 1084, 374, 279, 7772, 3283, 304, 279, 1879]
//!   text: " Paris. It is the largest city in the world"
//!
//! (Re-derived from a real `uv run python3` + `mlx_lm.generate.stream_generate`
//! call against this same checkpoint, not just pasted from a prior phase's
//! notes — see the aikit-native-llm task's report for the exact command.)
//!
//! Run: zig build run-llm-generate \
//!        -Dllm-model-dir=/path/to/mlx-community--Qwen2.5-0.5B-Instruct-4bit/snapshot
//! (must contain both `tokenizer.json` and `model.safetensors`.)

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const aikit = @import("aikit");
const mlx = aikit.backend.mlx;
const qwen2 = aikit.models.qwen2_mlx;

comptime {
    if (builtin.os.tag != .macos) @compileError("macOS-only (MLX)");
}

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const model_dir = build_options.model_dir;
    if (model_dir.len == 0) {
        std.debug.print("usage: zig build run-llm-generate -Dllm-model-dir=<dir containing tokenizer.json + model.safetensors>\n", .{});
        return error.MissingArg;
    }

    var tokenizer_path_buf: [4096]u8 = undefined;
    const tokenizer_path = try std.fmt.bufPrint(&tokenizer_path_buf, "{s}/tokenizer.json", .{model_dir});

    var weights_path_buf: [4096]u8 = undefined;
    const weights_path = try std.fmt.bufPrintSentinel(&weights_path_buf, "{s}/model.safetensors", .{model_dir}, 0);

    var threaded_io = std.Io.Threaded.init(gpa, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    var tok = try aikit.tokenizer.Tokenizer.initFromFile(gpa, io, tokenizer_path);
    defer tok.deinit();

    const prompt = "The capital of France is";
    const prompt_ids32 = try tok.encode(gpa, prompt);
    defer gpa.free(prompt_ids32);

    std.debug.print("prompt: \"{s}\"\n", .{prompt});
    std.debug.print("prompt token ids ({d}): {any}\n", .{ prompt_ids32.len, prompt_ids32 });

    const prompt_ids = try gpa.alloc(i32, prompt_ids32.len);
    defer gpa.free(prompt_ids);
    for (prompt_ids32, prompt_ids) |id, *out| out.* = @intCast(id);

    const ckpt = mlx.Checkpoint.load(weights_path) catch {
        std.debug.print("mlx_load_safetensors FAILED for {s}\n", .{weights_path});
        return error.LoadFailed;
    };
    std.debug.print("checkpoint loaded: {s}\n", .{weights_path});

    const model = qwen2.Model.init(ckpt, .{});

    const gen_ids = try model.generate(gpa, prompt_ids, .{ .max_new_tokens = 10, .eos_token_id = 151645 });
    defer gpa.free(gen_ids);

    std.debug.print("\ngenerated {d} tokens: {any}\n", .{ gen_ids.len, gen_ids });

    const text = try tok.decode(gpa, gen_ids);
    defer gpa.free(text);
    std.debug.print("generated text: \"{s}\"\n", .{text});

    const expected_ids = [_]u32{ 12095, 13, 1084, 374, 279, 7772, 3283, 304, 279, 1879 };
    const expected_text = " Paris. It is the largest city in the world";
    const ids_match = std.mem.eql(u32, gen_ids, &expected_ids);
    const text_match = std.mem.eql(u8, text, expected_text);

    std.debug.print("\nexpected ids:  {any}\n", .{expected_ids});
    std.debug.print("expected text: \"{s}\"\n", .{expected_text});
    std.debug.print("\nMATCH: ids={} text={}\n", .{ ids_match, text_match });

    if (!ids_match or !text_match) {
        std.debug.print("\nDIVERGENCE from Python reference — see this file's doc comment for context.\n", .{});
        return error.GenerationMismatch;
    }
}
