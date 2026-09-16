const std = @import("std");
const bible = @import("core").bible;

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

    try runScraperScript(engine, &.{ "uv", "run", "python", "tools/bible/scraper.py", book, ch_str });
}

/// Returns the companion scraper path used by the reader. The environment
/// override makes development and recovery installs explicit; the remaining
/// candidates cover the macOS app bundle, Linux prefix, and repo checkout.
fn nativeScraperPath(engine: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    if (std.c.getenv("METANOIA_SCRAPER_BIN")) |path| {
        return try allocator.dupe(u8, std.mem.span(path));
    }

    const candidates = .{
        "../MacOS/metanoia-scraper",
        "bin/metanoia-scraper",
        "zig-out/bin/metanoia-scraper",
        "metanoia-scraper",
        "metanoia-scraper.exe",
    };
    inline for (candidates) |candidate| {
        if (std.Io.Dir.cwd().access(engine, candidate, .{})) |_| {
            return try allocator.dupe(u8, candidate);
        } else |_| {}
    }

    // Let the OS search PATH as a final fallback. This is useful for a
    // developer-installed companion and still gives the caller the same
    // ScraperFailed result if no executable is available.
    return try allocator.dupe(u8, "metanoia-scraper");
}

fn runNativeScraper(
    engine: std.Io,
    allocator: std.mem.Allocator,
    operation: []const u8,
    book: []const u8,
    chapter: i32,
) !void {
    const executable = try nativeScraperPath(engine, allocator);
    defer allocator.free(executable);
    const chapter_text = try std.fmt.allocPrint(allocator, "{d}", .{chapter});
    defer allocator.free(chapter_text);
    try runScraperScript(engine, &.{ executable, operation, book, chapter_text });
}

/// Fetches original-language interlinear data for one chapter and caches it
/// into `data/bible.db` through the separately-built `metanoia-scraper`
/// companion. The reader never imports the scraper implementation.
pub fn scrape_interlinear(engine: std.Io, allocator: std.mem.Allocator, db: *bible.sqlite3, book: []const u8, chapter: i32) !void {
    _ = db;
    try runNativeScraper(engine, allocator, "interlinear", book, chapter);
}

/// Scopes the lexicon backfill to the Strong's numbers introduced by one
/// book/chapter, instead of scanning the whole interlinear table (see
/// tools/lexicon_scraper.py's cache_lexicon_from_db). The companion performs
/// the same native implementation in its own process.
pub fn scrape_lexicon(engine: std.Io, allocator: std.mem.Allocator, db: *bible.sqlite3, book: []const u8, chapter: i32) !void {
    _ = db;
    try runNativeScraper(engine, allocator, "lexicon", book, chapter);
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
