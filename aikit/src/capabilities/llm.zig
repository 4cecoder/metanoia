const std = @import("std");

/// Generation knobs a caller controls, independent of any specific
/// backend/model. Deliberately minimal to match what's actually
/// implemented today (see `models/qwen2_mlx.zig`'s `Model.generate`):
/// greedy/argmax decoding only. Temperature/top-p sampling is a
/// documented follow-up — a backend without it should just ignore any
/// such field added here later rather than erroring, same spirit as
/// `capabilities/tts.zig`'s `SynthesizeOptions.speed` note.
pub const GenerateOptions = struct {
    max_new_tokens: usize = 512,
};

pub const GenerateError = error{
    ModelNotLoaded,
    BackendFailure,
    OutOfMemory,
};

/// Backend-agnostic text-in/text-out LLM interface. `models/qwen2_mlx.zig`'s
/// `Qwen2LLM` implements this today (native MLX backend, macOS only), but
/// any future backend — a different model family, a GGML/llama.cpp-style
/// port for cross-platform support — implements the same vtable without
/// callers caring which. Mirrors `capabilities/tts.zig`'s `Synthesizer`
/// shape but is its own interface, not a reuse of that one — see
/// `README.md`'s "Adding a new capability" note on why.
pub const Generator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        generate: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, prompt: []const u8, options: GenerateOptions) GenerateError![]const u8,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn generate(self: Generator, allocator: std.mem.Allocator, prompt: []const u8, options: GenerateOptions) GenerateError![]const u8 {
        return self.vtable.generate(self.ptr, allocator, prompt, options);
    }

    pub fn deinit(self: Generator) void {
        self.vtable.deinit(self.ptr);
    }
};

test "GenerateOptions defaults" {
    const opts = GenerateOptions{};
    try std.testing.expectEqual(@as(usize, 512), opts.max_new_tokens);
}
