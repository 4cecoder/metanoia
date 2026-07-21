//! aikit — a standalone, backend-agnostic native-AI-inference library for
//! Zig 0.17+. Not metanoia-specific: no imports of GTK, sqlite, or anything
//! app-shaped anywhere under src/. See README.md for the design rationale
//! and how to add a new capability or backend.

const builtin = @import("builtin");

pub const tts = @import("capabilities/tts.zig");

/// Backend-agnostic text-in/text-out LLM interface (`Generator`). See
/// `models.qwen2_mlx.Qwen2LLM` for the (macOS/MLX-only, for now)
/// implementation.
pub const llm = @import("capabilities/llm.zig");

/// Backend-agnostic speech-to-text interface (`Transcriber`). See
/// `models.whisper_stt.WhisperSTT` for the (macOS-only, for now)
/// whisper.cpp-backed implementation — and that file's / `backend/whisper.zig`'s
/// doc comments for why this is a deliberate, explicitly-documented new
/// FFI exception rather than a quiet reach for the easy option.
pub const stt = @import("capabilities/stt.zig");

/// Backend-agnostic byte-level BPE tokenizer (HuggingFace `tokenizer.json`
/// format — GPT-2 family, Qwen2/Qwen2.5 included). See src/tokenizer.zig's
/// doc comment for why this lives at the top level instead of under
/// backend/ or models/.
pub const tokenizer = @import("tokenizer.zig");

pub const models = struct {
    pub const qwen3_tts = @import("models/qwen3_tts.zig");
    /// Native Zig forward pass for Qwen2(.5)-family causal LMs on top of
    /// `backend.mlx` — macOS only (see backend/mlx.zig's comptime guard);
    /// `void` fallback elsewhere keeps this struct's shape stable.
    pub const qwen2_mlx = if (builtin.os.tag == .macos) @import("models/qwen2_mlx.zig") else void;
    /// whisper.cpp-backed Whisper STT — macOS only for now (Homebrew
    /// whisper-cpp path assumed, see backend/whisper.zig's comptime
    /// guard); `void` fallback elsewhere keeps this struct's shape stable.
    pub const whisper_stt = if (builtin.os.tag == .macos) @import("models/whisper_stt.zig") else void;
};

/// Raw backend FFI layers. Most callers should go through `models.*`
/// (a capability implementation), not these directly — exposed here mainly
/// so backend-level tests run as part of `zig build test` and so a future
/// model implementation on top of `backend.mlx` has somewhere to import it
/// from. `mlx` is macOS-only (see backend/mlx.zig's comptime guard); the
/// `void` fallback keeps this struct's shape stable across platforms
/// without ever analyzing mlx.zig's Metal/mlx-c-dependent code elsewhere.
pub const backend = struct {
    pub const ggml = @import("backend/ggml.zig");
    pub const mlx = if (builtin.os.tag == .macos) @import("backend/mlx.zig") else void;
    pub const whisper = if (builtin.os.tag == .macos) @import("backend/whisper.zig") else void;
};

test {
    _ = tts;
    _ = llm;
    _ = stt;
    _ = tokenizer;
    _ = models.qwen3_tts;
    _ = backend.ggml;
    if (builtin.os.tag == .macos) {
        _ = backend.mlx;
        _ = models.qwen2_mlx;
        _ = backend.whisper;
        _ = models.whisper_stt;
    }
}
