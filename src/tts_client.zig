const std = @import("std");
const gtk = @import("gtk.zig");

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

pub fn generate_speech(engine: std.Io, text: []const u8, voice: []const u8, speed: f32, emotion: []const u8, mode: []const u8, force_refresh: bool) ![]const u8 {
    const allocator = std.heap.page_allocator;
    
    // 0. Load server address from config
    var server_url: []const u8 = "http://127.0.0.1:8000";
    if (std.Io.Dir.cwd().readFileAlloc(engine, "data/config.json", allocator, std.Io.Limit.limited(4096))) |config_data| {
        defer allocator.free(config_data);
        if (std.json.parseFromSlice(std.json.Value, allocator, config_data, .{})) |parsed| {
            defer parsed.deinit();
            if (parsed.value.object.get("tts_server_url")) |url| {
                server_url = try allocator.dupe(u8, url.string);
            }
        } else |_| {}
    } else |_| {}
    defer if (!std.mem.eql(u8, server_url, "http://127.0.0.1:8000")) allocator.free(server_url);

    const cache_key = try get_cache_key(allocator, text, voice, speed, emotion, mode);
    // Note: Caller is responsible for this memory if we return it, but here we use it for path
    
    const out_audio_path = try std.fmt.allocPrint(allocator, "cache/tts_{s}.wav", .{cache_key});
    defer allocator.free(out_audio_path);

    // 1. Local Cache Fast-Path
    if (!force_refresh) {
        if (std.Io.Dir.cwd().statFile(engine, out_audio_path, .{})) |_| {
            return try allocator.dupe(u8, out_audio_path);
        } else |_| {}
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
