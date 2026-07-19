const std = @import("std");

test "Config.parseJson defaults tts_backend to remote when key is absent" {
    // parseJson uses std.json's "Leaky" parser (matching load()'s existing
    // behavior — see comment on parseJson below), so scratch JSON
    // allocations are intentionally not freed individually; an arena is the
    // correct allocator for it, same as any other Leaky-parser caller.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cfg = Config.parseJson(arena.allocator(), "{}");
    try std.testing.expectEqualStrings("remote", cfg.tts_backend);
}

test "Config.parseJson loads tts_backend: native from JSON" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cfg = Config.parseJson(arena.allocator(), "{\"tts_backend\": \"native\"}");
    try std.testing.expectEqualStrings("native", cfg.tts_backend);
}

pub const Config = struct {
    english_font_size: i32 = 24,
    interlinear_font_size: i32 = 26,
    last_book: [64]u8 = "John".* ++ @as([60]u8, @splat(0)),
    last_chapter: i32 = 3,
    last_verse: i32 = 1,
    selected_voice: []const u8 = "",
    speed: f32 = 1.0,
    emotion: []const u8 = "",
    mode: []const u8 = "",
    tts_mode: []const u8 = "",
    sidebar_width: i32 = 300,
    tts_server_url: []const u8 = "",
    llm_server_url: []const u8 = "",
    tts_timeout_ms: u32 = 5000,
    tts_retry_count: u32 = 3,
    show_sidebar: bool = true,
    parallel_view: bool = false,
    /// Selects which TTS implementation `tts_client.zig`'s `generate_speech`
    /// uses: "remote" (default — curl to the Python/MLX server, unchanged
    /// existing behavior) or "native" (in-process aikit/qwentts.cpp GGML
    /// backend). Distinct from `tts_mode` above, which is an unrelated
    /// quality/speed preset ("speedy"/"gold"/"custom") matching
    /// data/voices.json's per-voice "mode" field. Defaults to "remote" so
    /// existing configs/users without this key see no behavior change.
    tts_backend: []const u8 = "",

    fn loadString(allocator: std.mem.Allocator, src: []const u8) []const u8 {
        return allocator.dupe(u8, src) catch @panic("OOM");
    }

    pub fn load(allocator: std.mem.Allocator, io: anytype) Config {
        const file = std.Io.Dir.cwd().openFile(io, "data/config.json", .{}) catch return parseJson(allocator, "");
        defer file.close(io);

        var buf: [4096]u8 = undefined;
        var f_reader = file.reader(io, &buf);
        const content = f_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(4096)) catch return parseJson(allocator, "");
        defer allocator.free(content);

        return parseJson(allocator, content);
    }

    /// Pure JSON->Config parsing, split out from `load()` so the mapping
    /// from JSON content to defaults/overrides is directly unit-testable
    /// without touching the filesystem (see tests above). `content` may be
    /// empty or malformed, in which case defaults are returned — matching
    /// `load()`'s existing behavior of falling back to defaults on any
    /// read/parse failure.
    pub fn parseJson(allocator: std.mem.Allocator, content: []const u8) Config {
        const defaults = struct {
            const selected_voice = "lennox";
            const emotion = "Neutral, clear narration";
            const mode = "base";
            const tts_mode = "speedy";
            const tts_server_url = "http://127.0.0.1:8000";
            const llm_server_url = "http://127.0.0.1:11434";
            const tts_backend = "remote";
        };
        var self = Config{
            .selected_voice = loadString(allocator, defaults.selected_voice),
            .emotion = loadString(allocator, defaults.emotion),
            .mode = loadString(allocator, defaults.mode),
            .tts_mode = loadString(allocator, defaults.tts_mode),
            .tts_server_url = loadString(allocator, defaults.tts_server_url),
            .llm_server_url = loadString(allocator, defaults.llm_server_url),
            .tts_backend = loadString(allocator, defaults.tts_backend),
        };

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
        if (parsed.object.get("selected_voice")) |v| {
            allocator.free(self.selected_voice);
            self.selected_voice = loadString(allocator, v.string);
        }
        if (parsed.object.get("emotion")) |v| {
            allocator.free(self.emotion);
            self.emotion = loadString(allocator, v.string);
        }
        if (parsed.object.get("mode")) |v| {
            allocator.free(self.mode);
            self.mode = loadString(allocator, v.string);
        }
        if (parsed.object.get("tts_mode")) |v| {
            allocator.free(self.tts_mode);
            self.tts_mode = loadString(allocator, v.string);
        }
        if (parsed.object.get("sidebar_width")) |v| self.sidebar_width = @intCast(v.integer);
        if (parsed.object.get("tts_server_url")) |v| {
            allocator.free(self.tts_server_url);
            self.tts_server_url = loadString(allocator, v.string);
        }
        if (parsed.object.get("llm_server_url")) |v| {
            allocator.free(self.llm_server_url);
            self.llm_server_url = loadString(allocator, v.string);
        }
        if (parsed.object.get("tts_timeout_ms")) |v| self.tts_timeout_ms = @intCast(v.integer);
        if (parsed.object.get("tts_retry_count")) |v| self.tts_retry_count = @intCast(v.integer);
        if (parsed.object.get("show_sidebar")) |v| self.show_sidebar = v.bool;
        if (parsed.object.get("parallel_view")) |v| self.parallel_view = v.bool;
        if (parsed.object.get("tts_backend")) |v| {
            allocator.free(self.tts_backend);
            self.tts_backend = loadString(allocator, v.string);
        }

        return self;
    }

    pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
        allocator.free(self.selected_voice);
        allocator.free(self.emotion);
        allocator.free(self.mode);
        allocator.free(self.tts_mode);
        allocator.free(self.tts_server_url);
        allocator.free(self.llm_server_url);
        allocator.free(self.tts_backend);
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
