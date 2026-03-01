const std = @import("std");

pub fn scrape_verses(engine: std.Io, book: []const u8, chapter: i32) !void {
    const ch_str = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{chapter});
    defer std.heap.page_allocator.free(ch_str);

    var child = try std.process.spawn(engine, .{
        .argv = &.{ "uv", "run", "python", "tools/scraper.py", book, ch_str },
    });
    _ = try child.wait(engine);
}

pub fn scrape_interlinear(engine: std.Io, book: []const u8, chapter: i32) !void {
    const ch_str = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{chapter});
    defer std.heap.page_allocator.free(ch_str);

    var child = try std.process.spawn(engine, .{
        .argv = &.{ "uv", "run", "python", "tools/interlinear_scraper.py", book, ch_str },
    });
    _ = try child.wait(engine);
}

pub fn scrape_lexicon(engine: std.Io) !void {
    var child = try std.process.spawn(engine, .{
        .argv = &.{ "uv", "run", "python", "tools/lexicon_scraper.py" },
    });
    _ = try child.wait(engine);
}
