const std = @import("std");

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
    const tts_json_path = try std.fmt.allocPrint(allocator, "data/tts_req_{s}.json", .{cache_key});
    defer allocator.free(tts_json_path);
    
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

    const f = try std.Io.Dir.cwd().createFile(engine, tts_json_path, .{});
    var fw = f.writer(engine, &.{});
    try fw.interface.writeAll(json_str);
    f.close(engine);

    const data_arg = try std.fmt.allocPrint(allocator, "@{s}", .{tts_json_path});
    defer allocator.free(data_arg);

    var child = try std.process.spawn(engine, .{
        .argv = &.{ "curl", "-s", "-f", "-X", "POST", "http://127.0.0.1:8000/generate", "-H", "Content-Type: application/json", "--data-binary", data_arg, "-o", out_audio_path },
    });
    const term = try child.wait(engine);
    if (term == .exited and term.exited != 0) return error.TtsServerError;

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
