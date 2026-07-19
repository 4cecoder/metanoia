const std = @import("std");

pub const Audio = struct {
    samples: []const i16,
    sample_rate: u32,
    channels: u8,

    pub fn deinit(self: Audio, allocator: std.mem.Allocator) void {
        allocator.free(self.samples);
    }
};

pub const SynthesizeOptions = struct {
    /// Named/preset voice identifier. Backend-specific meaning (e.g. a
    /// speaker name baked into the model checkpoint); empty means "use
    /// the backend's default voice". Mutually exclusive in practice with
    /// `reference_audio_path` — a backend that receives both should
    /// prefer the reference-audio path and may reject/ignore `voice`.
    voice: []const u8 = "",
    speed: f32 = 1.0,
    seed: ?u64 = null,

    /// Path to a reference audio clip for zero-shot voice cloning
    /// (in-context-learning style: the backend conditions generation on
    /// this clip so the output resembles that speaker). Left as a
    /// generic "reference audio" concept rather than named after any
    /// backend's specific API (e.g. qwentts.cpp calls this
    /// `ref_audio_24k`) so the interface stays backend-agnostic — a
    /// backend without cloning support should treat this as unsupported
    /// (return an error) rather than silently ignoring it. Format
    /// expectations (sample rate, channels, bit depth) are a backend
    /// concern, not specified here.
    reference_audio_path: ?[]const u8 = null,

    /// Exact transcript of `reference_audio_path`, required by backends
    /// whose cloning mode needs the matching text (ICL cloning) as
    /// opposed to audio-only conditioning (x-vector-only style cloning).
    /// Ignored when `reference_audio_path` is null.
    reference_text: ?[]const u8 = null,
};

pub const SynthesizeError = error{
    ModelNotLoaded,
    BackendFailure,
    OutOfMemory,
    /// `reference_audio_path` was set but couldn't be opened/read.
    ReferenceAudioUnreadable,
    /// `reference_audio_path` was readable but not in a format/sample
    /// rate the backend can consume for cloning (e.g. not mono 16-bit
    /// PCM at the backend's expected rate). Backends are not required to
    /// resample/transcode; callers that need this should pre-convert the
    /// reference clip before calling `synthesize`.
    UnsupportedReferenceAudioFormat,
};

/// Backend-agnostic TTS interface. `src/models/qwen3_tts.zig` implements
/// this today (GGML/qwentts.cpp backend), but any future backend — ONNX
/// Runtime, a different model family, a networked fallback — implements the
/// same vtable without callers caring which. This is the seam that keeps
/// aikit usable outside metanoia: a consumer only ever touches `Synthesizer`,
/// never a backend-specific type.
pub const Synthesizer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// `io` follows the same threaded-Io convention as the rest of
        /// metanoia (see `src/tts_client.zig`'s `engine: std.Io` param) —
        /// backends that need to read a reference-audio file
        /// (`SynthesizeOptions.reference_audio_path`) use it for that;
        /// backends without file I/O needs are free to ignore it.
        synthesize: *const fn (ptr: *anyopaque, io: std.Io, allocator: std.mem.Allocator, text: []const u8, options: SynthesizeOptions) SynthesizeError!Audio,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn synthesize(self: Synthesizer, io: std.Io, allocator: std.mem.Allocator, text: []const u8, options: SynthesizeOptions) SynthesizeError!Audio {
        return self.vtable.synthesize(self.ptr, io, allocator, text, options);
    }

    pub fn deinit(self: Synthesizer) void {
        self.vtable.deinit(self.ptr);
    }
};

test "SynthesizeOptions defaults" {
    const opts = SynthesizeOptions{};
    try std.testing.expectEqualStrings("", opts.voice);
    try std.testing.expectEqual(@as(f32, 1.0), opts.speed);
    try std.testing.expectEqual(@as(?u64, null), opts.seed);
    try std.testing.expectEqual(@as(?[]const u8, null), opts.reference_audio_path);
    try std.testing.expectEqual(@as(?[]const u8, null), opts.reference_text);
}
