//! Stable line protocol shared by the native TTS worker and its client.
//!
//! One JSON object is sent per line.  Audio never travels through the
//! protocol: the worker writes the requested WAV path and returns a small
//! acknowledgement, which keeps IPC memory bounded for long chapters.

const std = @import("std");

pub const Request = struct {
    id: []const u8,
    text: []const u8,
    voice: []const u8 = "",
    output: []const u8,
    reference_audio: ?[]const u8 = null,
    reference_text: ?[]const u8 = null,
    speed: f32 = 1.0,
    seed: ?u64 = null,
};

pub const Response = struct {
    id: []const u8,
    ok: bool,
    output: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    sample_rate: u32 = 0,
};

pub fn parseRequest(allocator: std.mem.Allocator, line: []const u8) !Request {
    const request = std.json.parseFromSliceLeaky(Request, allocator, line, .{}) catch return error.InvalidRequest;
    if (request.id.len == 0 or request.text.len == 0 or request.output.len == 0) {
        return error.InvalidRequest;
    }
    if (!std.math.isFinite(request.speed) or request.speed <= 0.0) {
        return error.InvalidRequest;
    }
    return request;
}

/// Read one complete protocol line and consume its newline. The distinction
/// from `takeDelimiterExclusive` matters here: that lower-level helper leaves
/// the delimiter in the reader, which would make a line-oriented worker spin
/// forever on the same empty newline after its first request.
pub fn readLine(reader: *std.Io.Reader) !?[]u8 {
    return reader.takeDelimiter('\n');
}

pub fn writeResponse(writer: *std.Io.Writer, response: Response) !void {
    var stringify: std.json.Stringify = .{ .writer = writer };
    try stringify.write(response);
    try writer.writeAll("\n");
    try writer.flush();
}

test "request parser accepts a clone request" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const request = try parseRequest(arena.allocator(),
        "{\"id\":\"1\",\"text\":\"hello\",\"voice\":\"jordan\",\"output\":\"cache/a.wav\",\"reference_audio\":\"data/jordan_ref.wav\",\"reference_text\":\"hello\",\"speed\":1.0}",
    );
    try std.testing.expectEqualStrings("1", request.id);
    try std.testing.expectEqualStrings("jordan", request.voice);
    try std.testing.expectEqualStrings("data/jordan_ref.wav", request.reference_audio.?);
}

test "request parser rejects missing required fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidRequest, parseRequest(arena.allocator(), "{\"id\":\"1\",\"text\":\"hello\"}"));
}

test "request parser rejects invalid speed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidRequest, parseRequest(arena.allocator(), "{\"id\":\"1\",\"text\":\"hello\",\"output\":\"a.wav\",\"speed\":0}"));
}

test "line reader consumes delimiters for resident workers" {
    var reader: std.Io.Reader = .fixed("one\ntwo\n");
    try std.testing.expectEqualStrings("one", (try readLine(&reader)).?);
    try std.testing.expectEqualStrings("two", (try readLine(&reader)).?);
    try std.testing.expectEqual(@as(?[]u8, null), try readLine(&reader));
}
