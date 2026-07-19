const std = @import("std");
const bible = @import("bible_db.zig");
const native_scraper = @import("native_scraper.zig");

/// Errors returned by scraper subprocesses beyond spawn/wait failures.
pub const ScraperError = error{ScraperFailed};

/// Runs argv to completion and turns a non-zero/abnormal exit into
/// error.ScraperFailed, so callers can tell "the scrape failed" apart from
/// "the scrape succeeded but there was nothing to cache" instead of both
/// looking identical (see services/llm_engine.zig).
fn runScraperScript(engine: std.Io, argv: []const []const u8) !void {
    var child = try std.process.spawn(engine, .{ .argv = argv });
    const term = try child.wait(engine);
    if (!term.success()) return ScraperError.ScraperFailed;
}

pub fn scrape_verses(engine: std.Io, book: []const u8, chapter: i32) !void {
    const ch_str = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{chapter});
    defer std.heap.page_allocator.free(ch_str);

    try runScraperScript(engine, &.{ "uv", "run", "python", "tools/scraper.py", book, ch_str });
}

/// Fetches original-language interlinear data for one chapter and caches it
/// into `db`. Was a `uv run python tools/interlinear_scraper.py` subprocess
/// call; now a native Zig implementation (see native_scraper.zig), which was
/// verified to be a faithful behavioral port of that script (same URLs, same
/// BibleHub CSS classes, same INSERT OR REPLACE shape, same retry/timeout
/// semantics) before this swap -- see native_scraper.zig's tests and
/// docstring for the porting notes.
pub fn scrape_interlinear(engine: std.Io, allocator: std.mem.Allocator, db: *bible.sqlite3, book: []const u8, chapter: i32) !void {
    try native_scraper.scrapeInterlinear(engine, allocator, db, book, chapter);
}

/// Scopes the lexicon backfill to the Strong's numbers introduced by one
/// book/chapter, instead of scanning the whole interlinear table (see
/// tools/lexicon_scraper.py's cache_lexicon_from_db). Was a Python subprocess
/// call; now native (see scrape_interlinear's doc comment above).
pub fn scrape_lexicon(engine: std.Io, allocator: std.mem.Allocator, db: *bible.sqlite3, book: []const u8, chapter: i32) !void {
    try native_scraper.scrapeLexicon(engine, allocator, db, book, chapter);
}

test "runScraperScript succeeds on zero exit" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    try runScraperScript(io, &.{ "/bin/sh", "-c", "exit 0" });
}

test "runScraperScript surfaces non-zero exit as ScraperFailed" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    try std.testing.expectError(ScraperError.ScraperFailed, runScraperScript(io, &.{ "/bin/sh", "-c", "exit 1" }));
}

test "runScraperScript surfaces signal termination as ScraperFailed" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    try std.testing.expectError(ScraperError.ScraperFailed, runScraperScript(io, &.{ "/bin/sh", "-c", "kill -TERM $$" }));
}
