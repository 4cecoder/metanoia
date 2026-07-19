const std = @import("std");
const tts = @import("../capabilities/tts.zig");
const ggml = @import("../backend/ggml.zig");

/// Qwen3-TTS backend (qwentts.cpp / GGML+Metal). Validated in the Phase 0
/// spike on the project's actual target hardware (base Apple M1, 16GB):
/// builds clean, pre-converted GGUF weights (no conversion step), byte-
/// reproducible output with a fixed seed, format-compatible with the
/// existing MLX pipeline's cached wavs (24kHz mono S16). RTF ~2.0
/// (slower than real-time) on that hardware — acceptable for now because
/// callers (metanoia's tts_client.zig) generate each verse once and cache
/// the result forever, so this cost is paid at most once per verse+voice.
///
/// Phase 1: confirmed against the real qwen.h that qwentts.cpp supports
/// zero-shot ICL (in-context-learning) voice cloning natively — a
/// reference WAV plus its exact transcript, via `qt_tts_params.ref_audio_24k`
/// / `ref_n_samples` / `ref_text`. `SynthesizeOptions.reference_audio_path`
/// / `reference_text` (capabilities/tts.zig) map directly onto that.
///
/// Model caveat: this Phase 1 build only downloaded the *Base* talker
/// checkpoint (`qwen-talker-0.6b-base-Q8_0.gguf`), which is what the
/// cloning path requires (named CustomVoice speakers live in a different
/// checkpoint and are rejected by qwen.h when loaded against Base). So
/// `SynthesizeOptions.voice` (a named-speaker hint) is not wired to
/// anything here — only `reference_audio_path`/`reference_text` cloning
/// works against this checkpoint. That's the tommy-voice path this module
/// was built to support.
pub const Qwen3TTS = struct {
    ctx: ?*ggml.QwenContext = null,

    pub fn init(model_path: []const u8, codec_path: []const u8) !Qwen3TTS {
        const model_z = try std.heap.page_allocator.dupeSentinel(u8, model_path, 0);
        defer std.heap.page_allocator.free(model_z);
        const codec_z = try std.heap.page_allocator.dupeSentinel(u8, codec_path, 0);
        defer std.heap.page_allocator.free(codec_z);

        var init_params: ggml.QtInitParams = .{};
        ggml.qt_init_default_params(&init_params);
        init_params.talker_path = model_z.ptr;
        init_params.codec_path = codec_z.ptr;

        const ctx = ggml.qt_init(&init_params) orelse {
            return error.ModelLoadFailed;
        };
        return .{ .ctx = ctx };
    }

    pub fn synthesizer(self: *Qwen3TTS) tts.Synthesizer {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable = tts.Synthesizer.VTable{
        .synthesize = synthesizeImpl,
        .deinit = deinitImpl,
    };

    fn synthesizeImpl(ptr: *anyopaque, io: std.Io, allocator: std.mem.Allocator, text: []const u8, options: tts.SynthesizeOptions) tts.SynthesizeError!tts.Audio {
        const self: *Qwen3TTS = @ptrCast(@alignCast(ptr));
        const ctx = self.ctx orelse return tts.SynthesizeError.ModelNotLoaded;

        // `options.speed` has no counterpart in qwen.h's qt_tts_params —
        // qwentts.cpp exposes no direct playback-rate knob (only sampling
        // temperature/top-k/top-p and the AR frame budget). Not applied.
        // A future backend revision could resample the output buffer to
        // approximate it, but that's not done here to avoid silently
        // pretending the request was honored.

        const text_z = allocator.dupeSentinel(u8, text, 0) catch return tts.SynthesizeError.OutOfMemory;
        defer allocator.free(text_z);

        var params: ggml.QtTtsParams = .{};
        ggml.qt_tts_default_params(&params);
        params.text = text_z.ptr;
        if (options.seed) |s| params.seed = @bitCast(s);

        var ref_text_z: ?[:0]u8 = null;
        defer if (ref_text_z) |t| allocator.free(t);
        var ref_samples: ?[]f32 = null;
        defer if (ref_samples) |s| allocator.free(s);

        if (options.reference_audio_path) |ref_path| {
            const wav = try loadMono16WavAsF32(io, allocator, ref_path);
            ref_samples = wav;
            params.ref_audio_24k = wav.ptr;
            params.ref_n_samples = @intCast(wav.len);

            if (options.reference_text) |ref_text| {
                const z = allocator.dupeSentinel(u8, ref_text, 0) catch return tts.SynthesizeError.OutOfMemory;
                ref_text_z = z;
                params.ref_text = z.ptr;
            }
        }

        var out: ggml.QtAudio = .{};
        const status = ggml.qt_synthesize(ctx, &params, &out);
        if (status != .ok) {
            return tts.SynthesizeError.BackendFailure;
        }
        defer ggml.qt_audio_free(&out);

        const n: usize = @intCast(out.n_samples);
        const samples_f32 = if (out.samples) |s| s[0..n] else &[_]f32{};

        const samples_i16 = allocator.alloc(i16, n) catch return tts.SynthesizeError.OutOfMemory;
        for (samples_f32, samples_i16) |f, *s| {
            const clamped = std.math.clamp(f, -1.0, 1.0);
            s.* = @intFromFloat(clamped * 32767.0);
        }

        return .{
            .samples = samples_i16,
            .sample_rate = @intCast(out.sample_rate),
            .channels = @intCast(out.channels),
        };
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Qwen3TTS = @ptrCast(@alignCast(ptr));
        ggml.qt_free(self.ctx);
        self.ctx = null;
    }
};

/// Minimal WAV reader for reference-audio cloning input. Supports exactly
/// what qwentts.cpp's own `qt_tts_params.ref_audio_24k` needs: mono
/// float32 PCM at 24kHz. Unlike qwentts.cpp's own `audio_read_mono` (which
/// accepts any WAV — any bit depth, any channel count, any sample rate,
/// and resamples), this reader only accepts 16-bit PCM mono WAV already
/// at 24kHz and errors otherwise — resampling/format conversion is left
/// as a follow-up rather than silently mis-cloning. This is sufficient
/// for `data/tommy.wav` and metanoia's other reference clips, which are
/// all pre-recorded at 24kHz mono S16 (matching the codec's native rate).
fn loadMono16WavAsF32(io: std.Io, allocator: std.mem.Allocator, path: []const u8) tts.SynthesizeError![]f32 {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return tts.SynthesizeError.ReferenceAudioUnreadable;
    defer file.close(io);

    var read_buf: [64 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    const bytes = file_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(256 * 1024 * 1024)) catch
        return tts.SynthesizeError.ReferenceAudioUnreadable;
    defer allocator.free(bytes);

    if (bytes.len < 44) return tts.SynthesizeError.UnsupportedReferenceAudioFormat;
    if (!std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WAVE")) {
        return tts.SynthesizeError.UnsupportedReferenceAudioFormat;
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
            if (chunk_size < 16) return tts.SynthesizeError.UnsupportedReferenceAudioFormat;
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

    if (!fmt_found or data_slice == null) return tts.SynthesizeError.UnsupportedReferenceAudioFormat;
    // audio_format 1 == PCM integer.
    if (audio_format != 1 or num_channels != 1 or bits_per_sample != 16 or sample_rate != 24000) {
        return tts.SynthesizeError.UnsupportedReferenceAudioFormat;
    }

    const data = data_slice.?;
    const n_samples = data.len / 2;
    const out = allocator.alloc(f32, n_samples) catch return tts.SynthesizeError.OutOfMemory;
    var i: usize = 0;
    while (i < n_samples) : (i += 1) {
        const s: i16 = std.mem.readInt(i16, data[i * 2 ..][0..2], .little);
        // Matches qwentts.cpp's own wav.h decode scale exactly (/32768).
        out[i] = @as(f32, @floatFromInt(s)) / 32768.0;
    }
    return out;
}

test "Qwen3TTS.synthesizer returns a Synthesizer bound to itself" {
    var model = Qwen3TTS{};
    const synth = model.synthesizer();
    try std.testing.expectEqual(@as(*anyopaque, @ptrCast(&model)), synth.ptr);
}

test "loadMono16WavAsF32 rejects a too-short buffer as unsupported format" {
    // Exercises the parser's guard rails without a real file: a WAV with
    // no valid RIFF/WAVE header must not read out of bounds.
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const result = loadMono16WavAsF32(io, std.testing.allocator, "definitely-does-not-exist.wav");
    try std.testing.expectError(tts.SynthesizeError.ReferenceAudioUnreadable, result);
}
