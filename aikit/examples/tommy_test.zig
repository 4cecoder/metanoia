//! Runnable Phase 1 example: loads the Qwen3-TTS Base checkpoint through
//! aikit's native GGML/Metal backend, synthesizes a short test line cloned
//! against the "tommy" reference voice (in-context-learning cloning — a
//! reference clip plus its exact transcript, see `data/voices.json` in the
//! main metanoia repo), and writes the result to
//! examples/output/tommy_test.wav.
//!
//! Run from within aikit/:
//!   zig build run-example
//!
//! Assumes (see build.zig / README.md):
//!   - qwentts.cpp built at ../vendor/qwentts.cpp/build (sibling of aikit/
//!     within this worktree), producing libqwen.dylib.
//!   - GGUF weights downloaded to ../vendor/qwentts.cpp/models/:
//!       qwen-talker-0.6b-base-Q8_0.gguf
//!       qwen-tokenizer-12hz-Q8_0.gguf
//!     from https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF
//!   - testdata/tommy.wav (copied from the main repo's data/tommy.wav,
//!     read-only reference — 24kHz mono S16, matching what
//!     src/models/qwen3_tts.zig's WAV reader accepts).

const std = @import("std");
const aikit = @import("aikit");

const model_path = "../vendor/qwentts.cpp/models/qwen-talker-0.6b-base-Q8_0.gguf";
const codec_path = "../vendor/qwentts.cpp/models/qwen-tokenizer-12hz-Q8_0.gguf";
const reference_wav_path = "testdata/tommy.wav";
const reference_text = "Okay, I do believe I am live."; // data/voices.json "tommy" entry
const test_text = "In the beginning was the Word, and the Word was with God.";
const output_path = "examples/output/tommy_test.wav";

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var threaded_io = std.Io.Threaded.init(gpa, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    std.debug.print("[tommy_test] loading model={s} codec={s}\n", .{ model_path, codec_path });
    var model = aikit.models.qwen3_tts.Qwen3TTS.init(model_path, codec_path) catch |err| {
        std.debug.print(
            "[tommy_test] FAILED to load model: {any}\n" ++
                "  Did you build qwentts.cpp and download the GGUF weights? See aikit/README.md.\n",
            .{err},
        );
        return err;
    };
    defer model.synthesizer().deinit();
    std.debug.print("[tommy_test] model loaded\n", .{});

    // Confirm the reference clip is actually present before claiming a
    // cloned voice was used — if it's missing, fall back honestly to base
    // voice rather than silently pretending cloning happened.
    const have_reference = blk: {
        const f = std.Io.Dir.cwd().openFile(io, reference_wav_path, .{}) catch break :blk false;
        f.close(io);
        break :blk true;
    };

    const options: aikit.tts.SynthesizeOptions = if (have_reference) .{
        .seed = 42,
        .reference_audio_path = reference_wav_path,
        .reference_text = reference_text,
    } else .{
        .seed = 42,
    };

    std.debug.print(
        "[tommy_test] synthesizing (mode={s}): \"{s}\"\n",
        .{ if (have_reference) "tommy voice clone (ICL)" else "base voice (no reference found)", test_text },
    );

    const audio = model.synthesizer().synthesize(io, gpa, test_text, options) catch |err| {
        std.debug.print("[tommy_test] FAILED to synthesize: {any}\n", .{err});
        return err;
    };
    defer audio.deinit(gpa);

    std.debug.print(
        "[tommy_test] got {d} samples @ {d} Hz, {d} channel(s)\n",
        .{ audio.samples.len, audio.sample_rate, audio.channels },
    );

    try std.Io.Dir.cwd().createDirPath(io, "examples/output");
    try writeWav(io, gpa, output_path, audio);
    std.debug.print("[tommy_test] wrote {s}\n", .{output_path});

    // Basic sanity check, same spirit as the Phase 0 spike: non-silent,
    // plausible duration.
    var sum_abs: u64 = 0;
    var peak: i16 = 0;
    for (audio.samples) |s| {
        const a: u16 = @abs(s);
        sum_abs += a;
        if (a > @abs(peak)) peak = s;
    }
    const mean_abs = if (audio.samples.len > 0) sum_abs / audio.samples.len else 0;
    const duration_sec = if (audio.sample_rate > 0)
        @as(f32, @floatFromInt(audio.samples.len)) / @as(f32, @floatFromInt(audio.sample_rate))
    else
        0.0;
    std.debug.print(
        "[tommy_test] duration={d:.2}s mean|sample|={d} peak={d} (non-silent={})\n",
        .{ duration_sec, mean_abs, peak, mean_abs > 50 },
    );
}

/// Minimal canonical-PCM WAV writer: 44-byte header, mono/stereo S16.
fn writeWav(io: std.Io, allocator: std.mem.Allocator, path: []const u8, audio: aikit.tts.Audio) !void {
    const byte_rate = audio.sample_rate * @as(u32, audio.channels) * 2;
    const block_align: u16 = @as(u16, audio.channels) * 2;
    const data_size: u32 = @intCast(audio.samples.len * 2);

    var header: [44]u8 = undefined;
    @memcpy(header[0..4], "RIFF");
    std.mem.writeInt(u32, header[4..8], 36 + data_size, .little);
    @memcpy(header[8..12], "WAVE");
    @memcpy(header[12..16], "fmt ");
    std.mem.writeInt(u32, header[16..20], 16, .little); // fmt chunk size
    std.mem.writeInt(u16, header[20..22], 1, .little); // PCM
    std.mem.writeInt(u16, header[22..24], audio.channels, .little);
    std.mem.writeInt(u32, header[24..28], audio.sample_rate, .little);
    std.mem.writeInt(u32, header[28..32], byte_rate, .little);
    std.mem.writeInt(u16, header[32..34], block_align, .little);
    std.mem.writeInt(u16, header[34..36], 16, .little); // bits per sample
    @memcpy(header[36..40], "data");
    std.mem.writeInt(u32, header[40..44], data_size, .little);

    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    var write_buf: [64 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);

    try file_writer.interface.writeAll(&header);

    const samples_bytes = try allocator.alloc(u8, audio.samples.len * 2);
    defer allocator.free(samples_bytes);
    for (audio.samples, 0..) |s, i| {
        std.mem.writeInt(i16, samples_bytes[i * 2 ..][0..2], s, .little);
    }
    try file_writer.interface.writeAll(samples_bytes);
    try file_writer.interface.flush();
}
