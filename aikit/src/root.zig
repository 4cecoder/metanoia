//! aikit — a standalone, backend-agnostic native-AI-inference library for
//! Zig 0.17+. Not metanoia-specific: no imports of GTK, sqlite, or anything
//! app-shaped anywhere under src/. See README.md for the design rationale
//! and how to add a new capability or backend.

const builtin = @import("builtin");

pub const tts = @import("capabilities/tts.zig");

pub const models = struct {
    pub const qwen3_tts = @import("models/qwen3_tts.zig");
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
};

test {
    _ = tts;
    _ = models.qwen3_tts;
    _ = backend.ggml;
    if (builtin.os.tag == .macos) _ = backend.mlx;
}
