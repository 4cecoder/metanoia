const std = @import("std");
const gtk = @import("gtk.zig");
const aikit = @import("aikit");

pub const TTSRequest = struct {
    text: []const u8,
    voice: []const u8,
    speed: f32,
    emotion: []const u8,
    mode: []const u8,
    force_refresh: bool,
    temperature: f32,
    cfg_scale: f32,
};

pub fn get_cache_key(allocator: std.mem.Allocator, text: []const u8, voice: []const u8, speed: f32, emotion: []const u8, mode: []const u8) ![]const u8 {
    const clean_text = std.mem.trim(u8, text, " \n\r\t");
    
    // Exact match of Python's cache_parts logic
    // [clean_text, selected_voice, str(request.speed), str(request.emotion), mode, str(request.temperature), str(request.cfg_scale)]
    const parts_str = try std.fmt.allocPrint(allocator, "{s}|{s}|{d:.1}|{s}|{s}|0.5|2.0", .{
        clean_text, voice, speed, if (emotion.len > 0) emotion else "Neutral, clear narration", mode,
    });
    defer allocator.free(parts_str);

    var hash: [std.crypto.hash.Md5.digest_length]u8 = undefined;
    std.crypto.hash.Md5.hash(parts_str, &hash, .{});
    
    const hex_chars = "0123456789abcdef";
    var result_hex: [32]u8 = undefined;
    for (hash, 0..) |b, i| {
        result_hex[i * 2] = hex_chars[b >> 4];
        result_hex[i * 2 + 1] = hex_chars[b & 0x0f];
    }

    return try allocator.dupe(u8, &result_hex);
}

/// Pure decision: does `cfg_tts_backend` (the raw `tts_backend` string from
/// `data/config.json`, see `src/models/config.zig`) select the native
/// (in-process aikit/qwentts.cpp) path over the default remote (curl to the
/// Python/MLX server) path? Only the exact string "native" opts in — any
/// other value, including the default "remote", an empty string (config key
/// absent from a very old config file), or an unrecognized value, safely
/// falls back to the remote path so behavior for existing users/configs is
/// unchanged unless they explicitly ask for "native".
pub fn shouldUseNativeBackend(cfg_tts_backend: []const u8) bool {
    return std.mem.eql(u8, cfg_tts_backend, "native");
}

pub fn generate_speech(engine: std.Io, text: []const u8, voice: []const u8, speed: f32, emotion: []const u8, mode: []const u8, force_refresh: bool) ![]const u8 {
    const allocator = std.heap.page_allocator;

    // 0. Load server address + backend selection from config
    var server_url: []const u8 = "http://127.0.0.1:8000";
    var tts_backend: []const u8 = "remote";
    var tts_backend_owned = false;
    if (std.Io.Dir.cwd().readFileAlloc(engine, "data/config.json", allocator, std.Io.Limit.limited(4096))) |config_data| {
        defer allocator.free(config_data);
        if (std.json.parseFromSlice(std.json.Value, allocator, config_data, .{})) |parsed| {
            defer parsed.deinit();
            if (parsed.value.object.get("tts_server_url")) |url| {
                server_url = try allocator.dupe(u8, url.string);
            }
            if (parsed.value.object.get("tts_backend")) |backend| {
                tts_backend = try allocator.dupe(u8, backend.string);
                tts_backend_owned = true;
            }
        } else |_| {}
    } else |_| {}
    defer if (!std.mem.eql(u8, server_url, "http://127.0.0.1:8000")) allocator.free(server_url);
    defer if (tts_backend_owned) allocator.free(tts_backend);

    const cache_key = try get_cache_key(allocator, text, voice, speed, emotion, mode);
    // Note: Caller is responsible for this memory if we return it, but here we use it for path

    const out_audio_path = try std.fmt.allocPrint(allocator, "cache/tts_{s}.wav", .{cache_key});
    defer allocator.free(out_audio_path);

    // 1. Local Cache Fast-Path (shared by both backends — same cache key,
    // same file location, so switching tts_backend doesn't invalidate
    // previously-cached audio and both backends see each other's cache hits)
    if (!force_refresh) {
        if (std.Io.Dir.cwd().statFile(engine, out_audio_path, .{})) |_| {
            return try allocator.dupe(u8, out_audio_path);
        } else |_| {}
    }

    // 1.5. Native backend: in-process aikit/qwentts.cpp synthesis, no
    // server/network involved. Branches away entirely before the remote
    // path's request-building/curl logic below, which stays untouched.
    if (shouldUseNativeBackend(tts_backend)) {
        try generateSpeechNative(engine, allocator, text, voice, out_audio_path);
        return try allocator.dupe(u8, out_audio_path);
    }

    // 2. Cache Miss - Call Server
    const req = TTSRequest{
        .text = text,
        .voice = voice,
        .speed = speed,
        .emotion = if (emotion.len > 0) emotion else "Neutral, clear narration",
        .mode = mode,
        .force_refresh = force_refresh,
        .temperature = 0.5,
        .cfg_scale = 2.0,
    };

    var json_buf: [16384]u8 = undefined;
    var json_writer = std.Io.Writer.fixed(&json_buf);
    var stringifier: std.json.Stringify = .{ .writer = &json_writer };
    try stringifier.write(req);
    const json_str = json_buf[0..json_writer.end];

    const full_endpoint = try std.fmt.allocPrint(allocator, "{s}/generate", .{server_url});
    defer allocator.free(full_endpoint);

    const start_time = gtk.g_get_monotonic_time();
    
    // Add retry loop (up to 3 attempts) for network resilience
    var attempt: u8 = 0;
    while (attempt < 3) : (attempt += 1) {
        var child = try std.process.spawn(engine, .{
            .argv = &.{ 
                "curl", "-4", "-s", "-f", 
                "--connect-timeout", "5",
                "--max-time", "60",
                "-X", "POST", 
                full_endpoint, 
                "-H", "Content-Type: application/json", 
                "--data-raw", json_str, 
                "-o", out_audio_path 
            },
        });
        const term = try child.wait(engine);
        
        if (term == .exited and term.exited == 0) break;
        
        if (attempt < 2) {
            std.debug.print("TTS Attempt {d} failed, retrying in 1s...\n", .{attempt + 1});
            gtk.g_usleep(1_000_000); // 1 second
        } else {
            const end_time = gtk.g_get_monotonic_time();
            const elapsed_ms = @divTrunc(end_time - start_time, 1000);
            std.debug.print("TTS Server Error: curl exited with {d} after 3 attempts in {d}ms\n", .{term.exited, elapsed_ms});
            return error.TtsServerError;
        }
    }

    const end_time = gtk.g_get_monotonic_time();
    const elapsed_ms = @divTrunc(end_time - start_time, 1000);
    std.debug.print("TTS generated in {d}ms: {s}\n", .{ elapsed_ms, out_audio_path });
    return try allocator.dupe(u8, out_audio_path);
}

// --- Native backend (aikit / qwentts.cpp) -----------------------------
//
// Model weights: expected at vendor/qwentts.cpp/models/*.gguf, relative to
// the metanoia repo root — same location aikit/examples/tommy_test.zig
// already downloads them to (via ../vendor/qwentts.cpp/models when run from
// aikit/), and the same relative-path-from-repo-root convention already
// used elsewhere for runtime assets (e.g. data/bible.db). Not moved into a
// metanoia-owned data/ or models/ dir: they're qwentts.cpp's own vendored
// build+model tree, and duplicating ~1.3GB of weights into a second
// location would be wasteful with no benefit.
const native_model_path = "vendor/qwentts.cpp/models/qwen-talker-0.6b-base-Q8_0.gguf";
const native_codec_path = "vendor/qwentts.cpp/models/qwen-tokenizer-12hz-Q8_0.gguf";

// Loaded lazily on first native-backend synthesis and kept for the life of
// the process — loading is the expensive part (~1.3GB of weights), and
// generate_speech is called once per verse/regeneration, so reloading per
// call would be prohibitively slow. `native_synth_mutex` both guards the
// lazy init and serializes calls into the (Metal/GGML) backend across
// concurrent callers — src/services/tts_engine.zig can have a lookahead
// thread and a "regenerate verse" thread both calling generate_speech at
// once — mirroring tools/metanoia_server's own `gpu_lock = Semaphore(1)`
// that serializes all generation through the engine.
var native_synth_mutex: std.Io.Mutex = .init;
var native_synth: ?aikit.models.qwen3_tts.Qwen3TTS = null;

/// Releases the lazily-loaded native model, if one was loaded. Not called
/// anywhere in normal app operation — `generate_speech`'s native path is
/// designed to keep the model resident for the process's whole lifetime
/// (see `native_synth`'s doc comment), and the OS reclaims everything on
/// exit regardless. This exists purely so short-lived processes that use
/// the native backend just once (namely `src/native_tts_test.zig`) can
/// explicitly release Metal/GGML resources before exiting — ggml-metal's
/// own global device-registry destructor otherwise asserts
/// (`[rsets->data count] == 0`) if a loaded context's residency sets were
/// never released via `qt_free` before process teardown.
pub fn shutdownNativeBackendForTesting() void {
    if (native_synth) |*synth| {
        synth.synthesizer().deinit();
        native_synth = null;
    }
}

const VoiceReference = struct {
    audio_path: []const u8,
    text: []const u8,
};

/// Resolves `voice` (e.g. "tommy") to its ICL reference clip + transcript
/// via data/voices.json, mirroring how
/// tools/metanoia_server/routes/generation.py resolves the same file for
/// the remote backend (lowercased lookup, `"audio"`/`"text"` fields).
/// Returns null — rather than an error — when the voice isn't found or has
/// no reference clip (e.g. the "custom" placeholder voices in voices.json
/// with `"audio": null`), so callers can honestly fall back to the
/// backend's base voice instead of failing outright, same spirit as
/// aikit/examples/tommy_test.zig's own missing-reference fallback.
fn loadVoiceReference(io: std.Io, allocator: std.mem.Allocator, voice: []const u8) !?VoiceReference {
    const data = std.Io.Dir.cwd().readFileAlloc(io, "data/voices.json", allocator, std.Io.Limit.limited(1 << 20)) catch return null;
    defer allocator.free(data);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;

    const voice_lower = try allocator.alloc(u8, voice.len);
    defer allocator.free(voice_lower);
    for (voice, 0..) |c, i| voice_lower[i] = std.ascii.toLower(c);

    const entry = parsed.value.object.get(voice_lower) orelse return null;
    if (entry != .object) return null;

    const audio_val = entry.object.get("audio") orelse return null;
    const text_val = entry.object.get("text") orelse return null;
    if (audio_val != .string or text_val != .string) return null;

    return VoiceReference{
        .audio_path = try allocator.dupe(u8, audio_val.string),
        .text = try allocator.dupe(u8, text_val.string),
    };
}

/// Minimal canonical-PCM WAV writer, same format aikit/examples/tommy_test.zig
/// writes (44-byte header, mono/stereo S16) — kept local to tts_client.zig
/// rather than added to aikit's public interface, since it's purely a
/// metanoia-side integration concern (aikit's `Audio` type is
/// backend-agnostic and intentionally has no file-format opinion).
fn writeWavFile(io: std.Io, path: []const u8, audio: aikit.tts.Audio) !void {
    const byte_rate = audio.sample_rate * @as(u32, audio.channels) * 2;
    const block_align: u16 = @as(u16, audio.channels) * 2;
    const data_size: u32 = @intCast(audio.samples.len * 2);

    var header: [44]u8 = undefined;
    @memcpy(header[0..4], "RIFF");
    std.mem.writeInt(u32, header[4..8], 36 + data_size, .little);
    @memcpy(header[8..12], "WAVE");
    @memcpy(header[12..16], "fmt ");
    std.mem.writeInt(u32, header[16..20], 16, .little);
    std.mem.writeInt(u16, header[20..22], 1, .little);
    std.mem.writeInt(u16, header[22..24], audio.channels, .little);
    std.mem.writeInt(u32, header[24..28], audio.sample_rate, .little);
    std.mem.writeInt(u32, header[28..32], byte_rate, .little);
    std.mem.writeInt(u16, header[32..34], block_align, .little);
    std.mem.writeInt(u16, header[34..36], 16, .little);
    @memcpy(header[36..40], "data");
    std.mem.writeInt(u32, header[40..44], data_size, .little);

    try std.Io.Dir.cwd().createDirPath(io, "cache");
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    var write_buf: [64 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    try file_writer.interface.writeAll(&header);

    var sample_bytes: [4096]u8 = undefined;
    var i: usize = 0;
    while (i < audio.samples.len) {
        var n: usize = 0;
        while (i < audio.samples.len and n + 2 <= sample_bytes.len) : (i += 1) {
            std.mem.writeInt(i16, sample_bytes[n..][0..2], audio.samples[i], .little);
            n += 2;
        }
        try file_writer.interface.writeAll(sample_bytes[0..n]);
    }
    try file_writer.interface.flush();
}

/// Synthesizes `text` via aikit's native GGML/Metal backend and writes the
/// result to `out_audio_path`. Voice cloning: if `voice` resolves to a
/// reference clip in data/voices.json, uses ICL cloning against it (same
/// clip+transcript the remote/Python backend would use for that voice);
/// otherwise falls back to the backend's base voice honestly rather than
/// failing.
fn generateSpeechNative(engine: std.Io, allocator: std.mem.Allocator, text: []const u8, voice: []const u8, out_audio_path: []const u8) !void {
    native_synth_mutex.lockUncancelable(engine);
    defer native_synth_mutex.unlock(engine);

    if (native_synth == null) {
        native_synth = try aikit.models.qwen3_tts.Qwen3TTS.init(native_model_path, native_codec_path);
    }
    const synthesizer = native_synth.?.synthesizer();

    const maybe_ref = loadVoiceReference(engine, allocator, voice) catch null;
    defer if (maybe_ref) |ref| {
        allocator.free(ref.audio_path);
        allocator.free(ref.text);
    };

    const options: aikit.tts.SynthesizeOptions = if (maybe_ref) |ref| .{
        .reference_audio_path = ref.audio_path,
        .reference_text = ref.text,
    } else .{};

    const audio = synthesizer.synthesize(engine, allocator, text, options) catch |err| {
        std.debug.print("Native TTS synthesis failed: {any}\n", .{err});
        return error.TtsServerError;
    };
    defer audio.deinit(allocator);

    try writeWavFile(engine, out_audio_path, audio);
}

test "shouldUseNativeBackend picks native only for the exact string \"native\"" {
    try std.testing.expect(shouldUseNativeBackend("native"));
    try std.testing.expect(!shouldUseNativeBackend("remote"));
    try std.testing.expect(!shouldUseNativeBackend(""));
    try std.testing.expect(!shouldUseNativeBackend("Native")); // case-sensitive, no fuzzy matching
    try std.testing.expect(!shouldUseNativeBackend("bogus"));
}

test "tts request json" {
    const req = TTSRequest{
        .text = "hello",
        .voice = "tommy",
        .speed = 1.0,
        .emotion = "neutral",
        .mode = "base",
        .force_refresh = false,
        .temperature = 0.5,
        .cfg_scale = 2.0,
    };
    var buf: [512]u8 = undefined;
    var f_writer = std.Io.Writer.fixed(&buf);
    var stringifier: std.json.Stringify = .{ .writer = &f_writer };
    try stringifier.write(req);
    
    const result = buf[0..f_writer.end];
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"text\":\"hello\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"temperature\":0.5"));
}
