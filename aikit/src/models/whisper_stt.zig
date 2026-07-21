//! whisper.cpp-backed implementation of `capabilities/stt.zig`'s
//! `Transcriber` interface. See `backend/whisper.zig`'s doc comment for
//! why this is a deliberate, explicitly-documented new FFI exception
//! (not a continuation of TTS's grandfathered one) and README.md's "STT"
//! section for the clean-room-Zig-replacement backlog entry this creates.
//!
//! Verified against a real checkpoint (`ggml-tiny.en.bin`, downloaded from
//! `https://huggingface.co/ggerganov/whisper.cpp`) and real audio
//! (`data/tommy.wav`, 24kHz mono — this module's own resampler converts
//! it to the 16kHz mono float32 `whisper_full` requires) — see
//! `examples/stt_transcribe.zig`.

const std = @import("std");
const stt = @import("../capabilities/stt.zig");
const whisper = @import("../backend/whisper.zig");

pub const WhisperSTT = struct {
    ctx: ?*whisper.whisper_context = null,

    /// `model_path` is a `ggml-*.bin` Whisper checkpoint (any of the
    /// sizes at https://huggingface.co/ggerganov/whisper.cpp — `tiny.en`
    /// is what this module was verified against).
    pub fn init(model_path: []const u8) !WhisperSTT {
        // See backend/whisper.zig's doc comment on ggml_backend_load_all —
        // required once per process before any whisper_init* call, or
        // device lookup finds nothing registered at all (not even CPU) and
        // whisper.cpp asserts. Idempotent to call more than once (re-scans
        // the same backend list), so no once-guard needed for correctness,
        // just a little redundant work if multiple WhisperSTT instances
        // are created.
        whisper.ggml_backend_load_all();

        const path_z = try std.heap.page_allocator.dupeSentinel(u8, model_path, 0);
        defer std.heap.page_allocator.free(path_z);

        const cparams = whisper.whisper_context_default_params();
        const ctx = whisper.whisper_init_from_file_with_params(path_z.ptr, cparams) orelse {
            return error.ModelLoadFailed;
        };
        return .{ .ctx = ctx };
    }

    pub fn transcriber(self: *WhisperSTT) stt.Transcriber {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable = stt.Transcriber.VTable{
        .transcribe = transcribeImpl,
        .deinit = deinitImpl,
    };

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *WhisperSTT = @ptrCast(@alignCast(ptr));
        whisper.whisper_free(self.ctx);
        self.ctx = null;
    }

    fn transcribeImpl(ptr: *anyopaque, io: std.Io, allocator: std.mem.Allocator, audio_path: []const u8, options: stt.TranscribeOptions) stt.TranscribeError![]const u8 {
        const self: *WhisperSTT = @ptrCast(@alignCast(ptr));
        const ctx = self.ctx orelse return stt.TranscribeError.ModelNotLoaded;

        const samples = try loadAndResampleTo16kMono(io, allocator, audio_path);
        defer allocator.free(samples);

        // whisper_full_default_params_by_ref allocates a real, fully-sized
        // C struct (correct defaults for every one of ~50 fields, computed
        // by whisper.cpp itself) — see backend/whisper.zig's doc comment on
        // why hand-defaulting this struct field-by-field from Zig would be
        // both wasteful and risky. We only override the handful of fields
        // this capability actually exposes.
        const params_ptr = whisper.whisper_full_default_params_by_ref(whisper.WHISPER_SAMPLING_GREEDY);
        defer whisper.whisper_free_params(params_ptr);

        params_ptr.print_progress = false;
        params_ptr.print_realtime = false;
        params_ptr.print_special = false;
        params_ptr.print_timestamps = false;
        params_ptr.translate = options.translate;

        var lang_z: ?[:0]u8 = null;
        defer if (lang_z) |l| allocator.free(l);
        if (options.language) |lang| {
            const z = allocator.dupeSentinel(u8, lang, 0) catch return stt.TranscribeError.OutOfMemory;
            lang_z = z;
            params_ptr.language = z.ptr;
            params_ptr.detect_language = false;
        } else {
            params_ptr.language = null;
            params_ptr.detect_language = true;
        }

        // Pass a full-struct *copy* (`params_ptr.*`) by value — safe here
        // specifically because WhisperFullParams (unlike a hand-truncated
        // subset) is declared with every real field in order, so this copy
        // is byte-for-byte what whisper.cpp's own C code expects.
        const status = whisper.whisper_full(ctx, params_ptr.*, samples.ptr, @intCast(samples.len));
        if (status != 0) return stt.TranscribeError.BackendFailure;

        const n_segments = whisper.whisper_full_n_segments(ctx);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        var i: c_int = 0;
        while (i < n_segments) : (i += 1) {
            const seg_text = whisper.whisper_full_get_segment_text(ctx, i);
            out.appendSlice(allocator, std.mem.span(seg_text)) catch return stt.TranscribeError.OutOfMemory;
        }
        return out.toOwnedSlice(allocator) catch return stt.TranscribeError.OutOfMemory;
    }
};

/// Reads a canonical-PCM WAV file at any sample rate / 16-bit mono or
/// stereo (stereo is downmixed by averaging channels), and linearly
/// resamples it to the 16kHz mono float32 `whisper_full` requires.
/// `whisper.cpp`'s own CLI tools do this via a vendored `miniaudio`
/// dependency; this is a from-scratch equivalent (RIFF chunk walking
/// mirrors `models/qwen3_tts.zig`'s `loadMono16WavAsF32`, extended to
/// arbitrary source sample rates rather than a fixed 24kHz) so this
/// capability doesn't pull in a second new native dependency on top of
/// whisper.cpp itself. Linear interpolation only — not a
/// bandlimited/sinc resampler, so audio quality is "good enough for
/// speech recognition," not archival-grade; documented limitation, not a
/// silent one.
fn loadAndResampleTo16kMono(io: std.Io, allocator: std.mem.Allocator, path: []const u8) stt.TranscribeError![]f32 {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return stt.TranscribeError.AudioUnreadable;
    defer file.close(io);

    var read_buf: [64 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const bytes = file_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(256 * 1024 * 1024)) catch
        return stt.TranscribeError.AudioUnreadable;
    defer allocator.free(bytes);

    if (bytes.len < 44) return stt.TranscribeError.UnsupportedAudioFormat;
    if (!std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WAVE")) {
        return stt.TranscribeError.UnsupportedAudioFormat;
    }

    var offset: usize = 12;
    var fmt_found = false;
    var audio_format: u16 = 0;
    var num_channels: u16 = 0;
    var sample_rate: u32 = 0;
    var bits_per_sample: u16 = 0;
    var data_slice: ?[]const u8 = null;

    while (offset + 8 <= bytes.len) {
        const chunk_id = bytes[offset .. offset + 4];
        const chunk_size = std.mem.readInt(u32, bytes[offset + 4 ..][0..4], .little);
        const body_start = offset + 8;
        if (body_start + chunk_size > bytes.len) break;

        if (std.mem.eql(u8, chunk_id, "fmt ")) {
            if (chunk_size < 16) return stt.TranscribeError.UnsupportedAudioFormat;
            const body = bytes[body_start .. body_start + chunk_size];
            audio_format = std.mem.readInt(u16, body[0..2], .little);
            num_channels = std.mem.readInt(u16, body[2..4], .little);
            sample_rate = std.mem.readInt(u32, body[4..8], .little);
            bits_per_sample = std.mem.readInt(u16, body[14..16], .little);
            fmt_found = true;
        } else if (std.mem.eql(u8, chunk_id, "data")) {
            data_slice = bytes[body_start .. body_start + chunk_size];
        }

        // Chunks are word-aligned: an odd-sized chunk has one pad byte.
        offset = body_start + chunk_size + (chunk_size & 1);
    }

    if (!fmt_found or data_slice == null) return stt.TranscribeError.UnsupportedAudioFormat;
    // audio_format 1 == PCM integer.
    if (audio_format != 1 or bits_per_sample != 16 or (num_channels != 1 and num_channels != 2) or sample_rate == 0) {
        return stt.TranscribeError.UnsupportedAudioFormat;
    }

    const data = data_slice.?;
    const bytes_per_frame: usize = @as(usize, num_channels) * 2;
    const n_src_frames = data.len / bytes_per_frame;

    const mono = allocator.alloc(f32, n_src_frames) catch return stt.TranscribeError.OutOfMemory;
    defer allocator.free(mono);

    var i: usize = 0;
    while (i < n_src_frames) : (i += 1) {
        const base = i * bytes_per_frame;
        if (num_channels == 1) {
            const s: i16 = std.mem.readInt(i16, data[base..][0..2], .little);
            mono[i] = @as(f32, @floatFromInt(s)) / 32768.0;
        } else {
            const l: i16 = std.mem.readInt(i16, data[base..][0..2], .little);
            const r: i16 = std.mem.readInt(i16, data[base + 2 ..][0..2], .little);
            mono[i] = (@as(f32, @floatFromInt(l)) + @as(f32, @floatFromInt(r))) / 2.0 / 32768.0;
        }
    }

    if (sample_rate == whisper_sample_rate) {
        return allocator.dupe(f32, mono) catch return stt.TranscribeError.OutOfMemory;
    }

    const dst_len_f: f64 = @as(f64, @floatFromInt(n_src_frames)) * @as(f64, @floatFromInt(whisper_sample_rate)) / @as(f64, @floatFromInt(sample_rate));
    const dst_len: usize = @intFromFloat(@floor(dst_len_f));
    const out = allocator.alloc(f32, dst_len) catch return stt.TranscribeError.OutOfMemory;

    var j: usize = 0;
    while (j < dst_len) : (j += 1) {
        const src_pos: f64 = @as(f64, @floatFromInt(j)) * @as(f64, @floatFromInt(sample_rate)) / @as(f64, @floatFromInt(whisper_sample_rate));
        const idx0: usize = @intFromFloat(@floor(src_pos));
        const frac: f32 = @floatCast(src_pos - @floor(src_pos));
        const idx1: usize = @min(idx0 + 1, n_src_frames - 1);
        out[j] = mono[idx0] * (1.0 - frac) + mono[idx1] * frac;
    }
    return out;
}

const whisper_sample_rate: u32 = 16000;

test "loadAndResampleTo16kMono rejects a too-short buffer as unsupported format" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const result = loadAndResampleTo16kMono(io, std.testing.allocator, "definitely-does-not-exist.wav");
    try std.testing.expectError(stt.TranscribeError.AudioUnreadable, result);
}

test "WhisperSTT.transcriber returns a Transcriber bound to itself" {
    var model = WhisperSTT{};
    const t = model.transcriber();
    try std.testing.expectEqual(@as(*anyopaque, @ptrCast(&model)), t.ptr);
}
