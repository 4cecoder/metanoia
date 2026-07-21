const std = @import("std");

pub const TranscribeOptions = struct {
    /// ISO 639-1 language code (e.g. "en"), or `null` for auto-detect.
    /// Backend-specific meaning (Whisper's `language` param); a backend
    /// without language selection should ignore this rather than error.
    language: ?[]const u8 = "en",
    /// Translate the result to English (Whisper's `translate` flag).
    /// Ignored by backends without translation support.
    translate: bool = false,
};

pub const TranscribeError = error{
    ModelNotLoaded,
    BackendFailure,
    OutOfMemory,
    /// The input audio file couldn't be opened/read.
    AudioUnreadable,
    /// The audio was readable but not a format the backend can decode
    /// (e.g. not a canonical-PCM WAV). Backends are not required to
    /// support every codec — callers needing something else should
    /// pre-convert before calling `transcribe`.
    UnsupportedAudioFormat,
};

/// Backend-agnostic speech-to-text interface. `models/whisper_stt.zig`
/// implements this today (whisper.cpp FFI backend — see that file's doc
/// comment for why this is a deliberate, explicitly-documented exception
/// to aikit's "no new external native deps going forward" principle, not
/// a quiet reach for the easy option). A future clean-room Zig Whisper
/// port (backlog — see README.md's "STT" section) would implement the
/// same interface without callers caring which. Mirrors
/// `capabilities/tts.zig`'s `Synthesizer` shape but is its own interface,
/// not a reuse of it — same reasoning as `capabilities/llm.zig`'s
/// `Generator`.
pub const Transcriber = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// `io` follows the same threaded-Io convention as the rest of
        /// this codebase (see `capabilities/tts.zig`'s `synthesize` doc
        /// comment) — used to read `audio_path`.
        transcribe: *const fn (ptr: *anyopaque, io: std.Io, allocator: std.mem.Allocator, audio_path: []const u8, options: TranscribeOptions) TranscribeError![]const u8,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn transcribe(self: Transcriber, io: std.Io, allocator: std.mem.Allocator, audio_path: []const u8, options: TranscribeOptions) TranscribeError![]const u8 {
        return self.vtable.transcribe(self.ptr, io, allocator, audio_path, options);
    }

    pub fn deinit(self: Transcriber) void {
        self.vtable.deinit(self.ptr);
    }
};

test "TranscribeOptions defaults" {
    const opts = TranscribeOptions{};
    try std.testing.expectEqualStrings("en", opts.language.?);
    try std.testing.expectEqual(false, opts.translate);
}
