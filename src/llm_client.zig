//! In-process/native vs. remote LLM backend selection, mirroring
//! `tts_client.zig`'s `tts_backend: "native"|"remote"` switch (see
//! `aikit/README.md`'s "LLM inference" section and CLAUDE.md's pattern
//! note on the TTS precedent). `"remote"` (the default) keeps today's
//! `ollama_client.zig` (curl to a locally-running Ollama server) path
//! completely untouched; `"native"` calls into `aikit.models.qwen2_mlx`'s
//! in-process MLX generation instead — same public signature
//! (`generate_response(allocator, io, prompt) ![]const u8`) so
//! `services/llm_engine.zig`'s two `analyzeVerse` call sites don't need to
//! change beyond swapping which module they call.

const std = @import("std");
const builtin = @import("builtin");
const ollama = @import("ollama_client.zig");
// Only importable when built with `-Dnative-ai=true` (see root build.zig)
// — that flag exists so a default `zig build`/`zig build test` (CI
// included) doesn't require mlx-c to be installed just to compile.
// `shouldUseNativeLLMBackend` still defaults to "remote" either way.
const build_options = @import("build_options");
const aikit = if (build_options.native_ai) @import("aikit") else struct {};

/// Pure decision: does `cfg_llm_backend` (the raw `llm_backend` string from
/// `data/config.json`, see `src/models/config.zig`) select the native
/// (in-process aikit/MLX) path over the default remote (curl to Ollama)
/// path? Only the exact string "native" opts in — any other value,
/// including the default "remote", an empty string (config key absent from
/// an older config file), or an unrecognized value, safely falls back to
/// the remote path so behavior for existing users/configs is unchanged
/// unless they explicitly ask for "native". Mirrors
/// `tts_client.shouldUseNativeBackend` exactly (same reasoning, same
/// signature shape).
pub fn shouldUseNativeLLMBackend(cfg_llm_backend: []const u8) bool {
    return std.mem.eql(u8, cfg_llm_backend, "native");
}

/// Generates a response to `prompt`, routing through either the native or
/// remote backend per `data/config.json`'s `llm_backend` key (same
/// read-config-by-path convention as `tts_client.generate_speech`, rather
/// than threading a `Config` value through every caller). Falls back to
/// "remote" on any read/parse failure, same as `tts_client.zig`.
pub fn generate_response(allocator: std.mem.Allocator, io: std.Io, prompt: []const u8) ![]const u8 {
    var llm_backend: []const u8 = "remote";
    var llm_backend_owned = false;
    if (std.Io.Dir.cwd().readFileAlloc(io, "data/config.json", allocator, std.Io.Limit.limited(4096))) |config_data| {
        defer allocator.free(config_data);
        if (std.json.parseFromSlice(std.json.Value, allocator, config_data, .{})) |parsed| {
            defer parsed.deinit();
            if (parsed.value.object.get("llm_backend")) |backend| {
                llm_backend = try allocator.dupe(u8, backend.string);
                llm_backend_owned = true;
            }
        } else |_| {}
    } else |_| {}
    defer if (llm_backend_owned) allocator.free(llm_backend);

    if (shouldUseNativeLLMBackend(llm_backend)) {
        return generateResponseNative(io, allocator, prompt);
    }

    // Remote path: byte-identical call into the existing, unchanged
    // ollama_client.zig — this is the default and must stay exactly what
    // every existing caller already gets today.
    return ollama.generate_response(allocator, io, prompt);
}

// --- Native backend (aikit / MLX Qwen2.5-0.5B-Instruct-4bit) -----------
//
// Model weights: expected at vendor/llm/qwen2.5-0.5b-instruct-4bit/,
// relative to the metanoia repo root, containing `tokenizer.json` +
// `model.safetensors` (an `mlx-community`-format checkpoint directory,
// e.g. a copy of `mlx-community/Qwen2.5-0.5B-Instruct-4bit`'s HuggingFace
// snapshot). Mirrors `tts_client.zig`'s `vendor/qwentts.cpp/models/*.gguf`
// convention — a fixed relative path under `vendor/`, gitignored (the
// checkpoint's ~265MB, well past what's worth tracking in git), not a
// metanoia-owned `data/`/`models/` dir since it's third-party model
// weights, not app data. Distinct subdirectory from `vendor/qwentts.cpp/`
// (a different upstream project entirely) — `vendor/llm/` is this backend's
// own home.
const native_model_dir = "vendor/llm/qwen2.5-0.5b-instruct-4bit";

/// True only when built with `-Dnative-ai=true` AND on macOS (aikit's MLX
/// backend is macOS-only — see `aikit/src/backend/mlx.zig`'s comptime
/// guard and `aikit/src/root.zig`'s `void` fallback on other platforms).
const native_llm_available = build_options.native_ai and builtin.os.tag == .macos;
const NativeLLM = if (native_llm_available) aikit.models.qwen2_mlx.Qwen2LLM else void;

// Loaded lazily on first native-backend call and kept for the life of the
// process (loading the checkpoint is the expensive part) — same pattern
// and same reasoning as tts_client.zig's `native_synth`/`native_synth_mutex`.
var native_llm_mutex: std.Io.Mutex = .init;
var native_llm: ?NativeLLM = null;

/// Releases the lazily-loaded native model, if one was loaded. See
/// `tts_client.shutdownNativeBackendForTesting`'s doc comment — same
/// reasoning: short-lived test processes should release MLX/Metal
/// resources explicitly before exit rather than relying on the (never
/// reached, for a long-running app) process-exit cleanup.
pub fn shutdownNativeLLMBackendForTesting() void {
    if (comptime !native_llm_available) return;
    if (native_llm) |*model| {
        model.deinit();
        native_llm = null;
    }
}

fn generateResponseNative(io: std.Io, allocator: std.mem.Allocator, prompt: []const u8) ![]const u8 {
    if (comptime !native_llm_available) {
        // Not built with -Dnative-ai=true (or not macOS): shouldUseNativeLLMBackend
        // still defaults to "remote", so this is only reached if someone
        // explicitly set `llm_backend: "native"` without also rebuilding
        // with the flag on a supported platform — a clear error beats a
        // missing-symbol build failure they'd otherwise never see coming.
        return error.NativeLLMUnsupportedPlatform;
    }

    native_llm_mutex.lockUncancelable(io);
    defer native_llm_mutex.unlock(io);

    if (native_llm == null) {
        native_llm = try NativeLLM.init(allocator, io, native_model_dir, .{});
    }
    const generator = native_llm.?.generator();

    return generator.generate(allocator, prompt, .{}) catch |err| {
        std.debug.print("Native LLM generation failed: {any}\n", .{err});
        return error.LlmServerError;
    };
}

test "shouldUseNativeLLMBackend picks native only for the exact string \"native\"" {
    try std.testing.expect(shouldUseNativeLLMBackend("native"));
    try std.testing.expect(!shouldUseNativeLLMBackend("remote"));
    try std.testing.expect(!shouldUseNativeLLMBackend(""));
    try std.testing.expect(!shouldUseNativeLLMBackend("Native")); // case-sensitive, no fuzzy matching
    try std.testing.expect(!shouldUseNativeLLMBackend("bogus"));
}
