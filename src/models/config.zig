const std = @import("std");

pub const Config = struct {
    english_font_size: i32 = 24,
    interlinear_font_size: i32 = 26,
    last_book: [64]u8 = "John".* ++ @as([60]u8, @splat(0)),
    last_chapter: i32 = 3,
    last_verse: i32 = 1,
    selected_voice: []const u8 = "lennox",
    speed: f32 = 1.0,
    emotion: []const u8 = "Neutral, clear narration",
    mode: []const u8 = "base",
    tts_mode: []const u8 = "speedy",
    sidebar_width: i32 = 300,
    tts_server_url: []const u8 = "http://127.0.0.1:8000",
    llm_server_url: []const u8 = "http://127.0.0.1:11434",
    tts_timeout_ms: u32 = 5000,
    tts_retry_count: u32 = 3,
    show_sidebar: bool = true,
    parallel_view: bool = false,

    pub fn load(allocator: std.mem.Allocator, io: anytype) Config {
        var self = Config{};
        const file = std.Io.Dir.cwd().openFile(io, "data/config.json", .{}) catch return self;
        defer file.close(io);

        var buf: [4096]u8 = undefined;
        var f_reader = file.reader(io, &buf);
        const content = f_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(4096)) catch return self;
        defer allocator.free(content);

        const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, content, .{}) catch return self;
        if (parsed != .object) return self;

        if (parsed.object.get("english_font_size")) |v| self.english_font_size = @intCast(v.integer);
        if (parsed.object.get("interlinear_font_size")) |v| self.interlinear_font_size = @intCast(v.integer);
        if (parsed.object.get("last_chapter")) |v| self.last_chapter = @intCast(v.integer);
        if (parsed.object.get("last_verse")) |v| self.last_verse = @intCast(v.integer);
        if (parsed.object.get("last_book")) |v| {
            const name = v.string;
            @memset(&self.last_book, 0);
            @memcpy(self.last_book[0..@min(name.len, 63)], name[0..@min(name.len, 63)]);
        }
        if (parsed.object.get("speed")) |v| {
            self.speed = switch (v) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => 1.0,
            };
        }
        if (parsed.object.get("selected_voice")) |v| self.selected_voice = allocator.dupe(u8, v.string) catch "lennox";
        if (parsed.object.get("emotion")) |v| self.emotion = allocator.dupe(u8, v.string) catch "Neutral, clear narration";
        if (parsed.object.get("mode")) |v| self.mode = allocator.dupe(u8, v.string) catch "base";
        if (parsed.object.get("tts_mode")) |v| self.tts_mode = allocator.dupe(u8, v.string) catch "speedy";
        if (parsed.object.get("sidebar_width")) |v| self.sidebar_width = @intCast(v.integer);
        if (parsed.object.get("tts_server_url")) |v| self.tts_server_url = allocator.dupe(u8, v.string) catch "http://127.0.0.1:8000";
        if (parsed.object.get("llm_server_url")) |v| self.llm_server_url = allocator.dupe(u8, v.string) catch "http://127.0.0.1:11434";
        if (parsed.object.get("tts_timeout_ms")) |v| self.tts_timeout_ms = @intCast(v.integer);
        if (parsed.object.get("tts_retry_count")) |v| self.tts_retry_count = @intCast(v.integer);
        if (parsed.object.get("show_sidebar")) |v| self.show_sidebar = v.bool;
        if (parsed.object.get("parallel_view")) |v| self.parallel_view = v.bool;

        return self;
    }

    pub fn save(self: Config, io: anytype) void {
        const file = std.Io.Dir.cwd().createFile(io, "data/config.json", .{}) catch return;
        defer file.close(io);
        var buf: [2048]u8 = undefined;
        var f_writer = file.writer(io, &buf);

        var write_stream: std.json.Stringify = .{ .writer = &f_writer.interface };
        write_stream.write(self) catch return;
    }
};
