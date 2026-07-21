//! Real end-to-end verification of the whisper.cpp-backed STT capability
//! (`aikit.models.whisper_stt.WhisperSTT`, implementing
//! `capabilities/stt.zig`'s `Transcriber` interface) — loads a real
//! `ggml-*.bin` Whisper checkpoint and transcribes a real WAV file,
//! printing whatever text actually comes back (no hardcoded expected
//! output to compare against, unlike the LLM examples — Whisper's exact
//! output isn't something this repo has an independent Python-reference
//! oracle for yet, so this is "does it produce plausible real speech
//! text," not a byte-exact comparison).
//!
//! Run: zig build run-stt-transcribe \
//!        -Dstt-model=/path/to/ggml-tiny.en.bin \
//!        -Dstt-audio=/path/to/some.wav
//! (both default to this repo's own vendor/whisper.cpp/models/ggml-tiny.en.bin
//! and data/tommy.wav, resolved relative to aikit/ — i.e. "../vendor/..."
//! and "../data/..." — see build.zig's `stt-model`/`stt-audio` options.)

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const aikit = @import("aikit");

comptime {
    if (builtin.os.tag != .macos) @compileError("macOS-only (whisper.cpp via Homebrew, for now)");
}

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var threaded_io = std.Io.Threaded.init(gpa, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const model_path = build_options.model_path;
    const audio_path = build_options.audio_path;
    std.debug.print("model: {s}\naudio: {s}\n", .{ model_path, audio_path });

    var model = aikit.models.whisper_stt.WhisperSTT.init(model_path) catch |err| {
        std.debug.print("whisper_init_from_file_with_params FAILED: {any}\n", .{err});
        return error.LoadFailed;
    };
    const transcriber = model.transcriber();
    defer transcriber.deinit();

    const text = try transcriber.transcribe(io, gpa, audio_path, .{});
    defer gpa.free(text);

    std.debug.print("\ntranscribed text: \"{s}\"\n", .{text});

    if (text.len == 0) {
        std.debug.print("\nEMPTY transcription — likely a real problem (silent audio, wrong model, or a bug), not success.\n", .{});
        return error.EmptyTranscription;
    }
}
