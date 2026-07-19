const std = @import("std");

pub const sqlite3 = anyopaque;
pub const sqlite3_stmt = anyopaque;

/// Every function below shares the single sqlite3 connection opened once in
/// main() (state.db), and llm_engine.zig fires background scrapes/analysis
/// on detached GTK threads (g_thread_new) that call into it concurrently
/// with the UI thread. The system libsqlite3 on both Homebrew (macOS) and
/// apt (Linux) is commonly built with `-DSQLITE_THREADSAFE=2` ("multi-thread"
/// mode), which explicitly forbids using *the same connection* from more
/// than one thread at a time — verified locally via `sqlite3_threadsafe()`
/// returning the multi-thread compile option, and confirmed by a real SEGV
/// from concurrent unsynchronized writes (see the "concurrent writers"
/// test below). This mutex is the portable fix: it doesn't depend on how
/// any given platform happened to compile its sqlite3.
///
/// std.Thread.Mutex doesn't exist in this Zig nightly (blocking mutexes moved
/// to std.Io.Mutex, which needs an `Io` threaded through every call site just
/// to lock — not worth it for critical sections this short). std.atomic.Mutex
/// only exposes tryLock/unlock, so lockDb()/unlockDb() below add the
/// blocking wait via a yielding spin loop.
var db_mutex: std.atomic.Mutex = .unlocked;

fn lockDb() void {
    while (!db_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}

fn unlockDb() void {
    db_mutex.unlock();
}
pub extern fn sqlite3_open(filename: [*:0]const u8, ppDb: **sqlite3) i32;
pub extern fn sqlite3_close(db: *sqlite3) i32;
pub extern fn sqlite3_prepare_v2(db: *sqlite3, zSql: [*:0]const u8, nByte: i32, ppStmt: **sqlite3_stmt, pzTail: ?**const u8) i32;
pub extern fn sqlite3_step(stmt: *sqlite3_stmt) i32;
pub extern fn sqlite3_column_text(stmt: *sqlite3_stmt, iCol: i32) ?[*:0]const u8;
pub extern fn sqlite3_column_int(stmt: *sqlite3_stmt, iCol: i32) i32;
pub extern fn sqlite3_finalize(stmt: *sqlite3_stmt) i32;
// Parameterized-bind API (added for native_scraper.zig): unlike every read/write
// function above, which builds SQL by string-interpolating values straight into
// the query text (a pre-existing pattern in this file, not introduced here),
// scraped web content is untrusted and can contain single quotes (e.g. an
// English gloss like "Paul's"), so the scraper writes below use real bound
// parameters instead of interpolation. This also matches tools/*_scraper.py,
// whose sqlite3 `cursor.execute(sql, params)` calls were already parameterized.
// The destructor parameter is typed as `?*const anyopaque` rather than the C
// header's precise `void(*)(void*)` function-pointer type: we only ever pass
// the two sentinel values SQLITE_STATIC (0) / SQLITE_TRANSIENT (-1), never a
// real callback, and @ptrFromInt(maxInt(usize)) doesn't satisfy a function
// pointer's alignment requirement but does satisfy anyopaque's (1). The
// bytes crossing the C ABI boundary are identical either way.
pub extern fn sqlite3_bind_text(stmt: *sqlite3_stmt, idx: i32, val: [*]const u8, len: i32, destructor: ?*const anyopaque) i32;
pub extern fn sqlite3_bind_int(stmt: *sqlite3_stmt, idx: i32, val: i32) i32;

pub const SQLITE_ROW = 100;
pub const SQLITE_OK = 0;
/// SQLITE_TRANSIENT: tells sqlite3 to copy the bound bytes immediately
/// (rather than assume the pointer outlives the statement, as SQLITE_STATIC
/// (0) would), since the []const u8 slices bound below are freed by the
/// caller shortly after sqlite3_step().
const SQLITE_TRANSIENT: ?*const anyopaque = @ptrFromInt(std.math.maxInt(usize));

fn bindText(stmt: *sqlite3_stmt, idx: i32, val: []const u8) void {
    _ = sqlite3_bind_text(stmt, idx, val.ptr, @intCast(val.len), SQLITE_TRANSIENT);
}

pub fn init_db(db: *sqlite3) !void {
    lockDb();
    defer unlockDb();
    // Every table here must exist for a *freshly created* db, not just the
    // pre-populated data/bible.db shipped in the repo — otherwise a missing
    // table and "no rows yet" look identical to callers (sqlite3_prepare_v2
    // just fails and the read functions below fall through to their "not
    // found" default), which is exactly the kind of silent gap that made the
    // original-language caching bug hard to notice.
    const queries = [_][*:0]const u8{
        "CREATE TABLE IF NOT EXISTS highlights (book TEXT, chapter INTEGER, verse INTEGER, color TEXT, PRIMARY KEY(book, chapter, verse))",
        "CREATE TABLE IF NOT EXISTS lexical_favorites (strongs TEXT PRIMARY KEY, lemma TEXT, definition TEXT)",
        "CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, chapter INTEGER, verse INTEGER, content TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)",
        "CREATE TABLE IF NOT EXISTS book_metadata (book TEXT PRIMARY KEY, author TEXT, date TEXT, audience TEXT, context TEXT)",
        "CREATE TABLE IF NOT EXISTS chapter_summaries (book TEXT, chapter INTEGER, summary TEXT, PRIMARY KEY(book, chapter))",
        "CREATE TABLE IF NOT EXISTS verses (id INTEGER PRIMARY KEY, book TEXT, chapter INTEGER, verse INTEGER, text TEXT, version TEXT, footnotes TEXT)",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_verse_lookup ON verses (book, chapter, verse, version)",
        "CREATE TABLE IF NOT EXISTS cross_references (id INTEGER PRIMARY KEY, from_book TEXT, from_chapter INTEGER, from_verse INTEGER, to_book TEXT, to_chapter INTEGER, to_verse INTEGER)",
        "CREATE INDEX IF NOT EXISTS idx_xref_lookup ON cross_references (from_book, from_chapter, from_verse)",
        "CREATE TABLE IF NOT EXISTS interlinear (id INTEGER PRIMARY KEY, book TEXT, chapter INTEGER, verse INTEGER, word_index INTEGER, original_text TEXT, translation TEXT, strongs TEXT, morphology TEXT)",
        "CREATE INDEX IF NOT EXISTS idx_interlinear_lookup ON interlinear (book, chapter, verse)",
        "CREATE INDEX IF NOT EXISTS idx_interlinear_strongs ON interlinear (strongs)",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_interlinear_unique ON interlinear (book, chapter, verse, word_index)",
        "CREATE TABLE IF NOT EXISTS lexicon (strongs TEXT PRIMARY KEY, language TEXT, lemma TEXT, transliteration TEXT, definition TEXT, usage TEXT)",
        "CREATE INDEX IF NOT EXISTS idx_lexicon_lang ON lexicon (language)",
    };
    for (queries) |q| {
        var stmt: ?*sqlite3_stmt = null;
        if (sqlite3_prepare_v2(db, q, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
            _ = sqlite3_step(stmt.?);
            _ = sqlite3_finalize(stmt.?);
        }
    }
}

pub fn get_chapter_summary(allocator: std.mem.Allocator, db: *sqlite3, book: []const u8, chapter: i32) ![]const u8 {
    lockDb();
    defer unlockDb();
    const sql = try std.fmt.allocPrintSentinel(allocator, "SELECT summary FROM chapter_summaries WHERE book='{s}' AND chapter={d}", .{ book, chapter }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        if (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const summary = sqlite3_column_text(stmt.?, 0) orelse "No summary available.";
            const res = try allocator.dupe(u8, std.mem.span(summary));
            _ = sqlite3_finalize(stmt.?);
            return res;
        }
        _ = sqlite3_finalize(stmt.?);
    }
    return try allocator.dupe(u8, "No literary summary found for this chapter.");
}

pub fn save_chapter_summary(db: *sqlite3, book: []const u8, chapter: i32, summary: []const u8) !void {
    lockDb();
    defer unlockDb();
    const allocator = std.heap.page_allocator;
    const sql = try std.fmt.allocPrintSentinel(allocator, "INSERT OR REPLACE INTO chapter_summaries (book, chapter, summary) VALUES ('{s}', {d}, '{s}')", .{ book, chapter, summary }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        _ = sqlite3_step(stmt.?);
        _ = sqlite3_finalize(stmt.?);
    }
}

pub fn get_verse_note(allocator: std.mem.Allocator, db: *sqlite3, book: []const u8, chapter: i32, verse: i32) ![]const u8 {
    lockDb();
    defer unlockDb();
    const sql = try std.fmt.allocPrintSentinel(allocator, "SELECT content FROM notes WHERE book='{s}' AND chapter={d} AND verse={d} ORDER BY created_at DESC LIMIT 1", .{ book, chapter, verse }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        if (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const content = sqlite3_column_text(stmt.?, 0) orelse "";
            const res = try allocator.dupe(u8, std.mem.span(content));
            _ = sqlite3_finalize(stmt.?);
            return res;
        }
        _ = sqlite3_finalize(stmt.?);
    }
    return try allocator.dupe(u8, "");
}

pub fn save_verse_note(db: *sqlite3, book: []const u8, chapter: i32, verse: i32, content: []const u8) !void {
    lockDb();
    defer unlockDb();
    const allocator = std.heap.page_allocator;
    const sql = try std.fmt.allocPrintSentinel(allocator, "INSERT INTO notes (book, chapter, verse, content) VALUES ('{s}', {d}, {d}, '{s}')", .{ book, chapter, verse, content }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        _ = sqlite3_step(stmt.?);
        _ = sqlite3_finalize(stmt.?);
    }
}

pub fn set_verse_highlight(db: *sqlite3, book: []const u8, chapter: i32, verse: i32, color: []const u8) !void {
    lockDb();
    defer unlockDb();
    const allocator = std.heap.page_allocator;
    const sql = try std.fmt.allocPrintSentinel(allocator, "INSERT OR REPLACE INTO highlights (book, chapter, verse, color) VALUES ('{s}', {d}, {d}, '{s}')", .{ book, chapter, verse, color }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        _ = sqlite3_step(stmt.?);
        _ = sqlite3_finalize(stmt.?);
    }
}

pub fn delete_verse_highlight(db: *sqlite3, book: []const u8, chapter: i32, verse: i32) !void {
    lockDb();
    defer unlockDb();
    const allocator = std.heap.page_allocator;
    const sql = try std.fmt.allocPrintSentinel(allocator, "DELETE FROM highlights WHERE book='{s}' AND chapter={d} AND verse={d}", .{ book, chapter, verse }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        _ = sqlite3_step(stmt.?);
        _ = sqlite3_finalize(stmt.?);
    }
}

pub fn get_chapter_highlights(allocator: std.mem.Allocator, db: *sqlite3, book: []const u8, chapter: i32) !std.AutoHashMapUnmanaged(i32, []const u8) {
    lockDb();
    defer unlockDb();
    var map = std.AutoHashMapUnmanaged(i32, []const u8).empty;
    const sql = try std.fmt.allocPrintSentinel(allocator, "SELECT verse, color FROM highlights WHERE book='{s}' AND chapter={d}", .{ book, chapter }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        while (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const verse = sqlite3_column_int(stmt.?, 0);
            const color = sqlite3_column_text(stmt.?, 1) orelse "#7aa2f7";
            try map.put(allocator, verse, try allocator.dupe(u8, std.mem.span(color)));
        }
        _ = sqlite3_finalize(stmt.?);
    }
    return map;
}

pub fn get_book_metadata(allocator: std.mem.Allocator, db: *sqlite3, book: []const u8) ![]const u8 {
    lockDb();
    defer unlockDb();
    const sql = try std.fmt.allocPrintSentinel(allocator, "SELECT author, date, audience, context FROM book_metadata WHERE book='{s}'", .{book}, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        if (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const author = sqlite3_column_text(stmt.?, 0) orelse "Unknown";
            const date = sqlite3_column_text(stmt.?, 1) orelse "Unknown";
            const audience = sqlite3_column_text(stmt.?, 2) orelse "General";
            const context = sqlite3_column_text(stmt.?, 3) orelse "No historical context available.";

            const res = try std.fmt.allocPrint(allocator, "Author: {s}, Date: {s}, Audience: {s}. Context: {s}", .{ author, date, audience, context });
            _ = sqlite3_finalize(stmt.?);
            return res;
        }
        _ = sqlite3_finalize(stmt.?);
    }
    return try allocator.dupe(u8, "No historical metadata found for this book.");
}

pub const Testament = enum { Old, New, EthiopiaExpanded };
pub const BibleBook = struct { name: [*:0]const u8, chapters: i32, testament: Testament };

pub const BIBLE_BOOKS = [_]BibleBook{
    .{ .name = "Genesis", .chapters = 50, .testament = .Old },
    .{ .name = "Exodus", .chapters = 40, .testament = .Old },
    .{ .name = "Leviticus", .chapters = 27, .testament = .Old },
    .{ .name = "Numbers", .chapters = 36, .testament = .Old },
    .{ .name = "Deuteronomy", .chapters = 34, .testament = .Old },
    .{ .name = "Joshua", .chapters = 24, .testament = .Old },
    .{ .name = "Judges", .chapters = 21, .testament = .Old },
    .{ .name = "Ruth", .chapters = 4, .testament = .Old },
    .{ .name = "1Samuel", .chapters = 31, .testament = .Old },
    .{ .name = "2Samuel", .chapters = 24, .testament = .Old },
    .{ .name = "1Kings", .chapters = 22, .testament = .Old },
    .{ .name = "2Kings", .chapters = 25, .testament = .Old },
    .{ .name = "1Chronicles", .chapters = 29, .testament = .Old },
    .{ .name = "2Chronicles", .chapters = 36, .testament = .Old },
    .{ .name = "Ezra", .chapters = 10, .testament = .Old },
    .{ .name = "Nehemiah", .chapters = 13, .testament = .Old },
    .{ .name = "Tobit", .chapters = 14, .testament = .Old },
    .{ .name = "Judith", .chapters = 16, .testament = .Old },
    .{ .name = "Esther", .chapters = 10, .testament = .Old },
    .{ .name = "1Meqabyan", .chapters = 36, .testament = .Old },
    .{ .name = "2Meqabyan", .chapters = 21, .testament = .Old },
    .{ .name = "3Meqabyan", .chapters = 15, .testament = .Old },
    .{ .name = "Job", .chapters = 42, .testament = .Old },
    .{ .name = "Psalms", .chapters = 150, .testament = .Old },
    .{ .name = "Proverbs", .chapters = 31, .testament = .Old },
    .{ .name = "Tegsas", .chapters = 31, .testament = .Old },
    .{ .name = "Wisdom", .chapters = 19, .testament = .Old },
    .{ .name = "Ecclesiastes", .chapters = 12, .testament = .Old },
    .{ .name = "SongofSolomon", .chapters = 8, .testament = .Old },
    .{ .name = "Sirach", .chapters = 51, .testament = .Old },
    .{ .name = "Isaiah", .chapters = 66, .testament = .Old },
    .{ .name = "Jeremiah", .chapters = 52, .testament = .Old },
    .{ .name = "Lamentations", .chapters = 5, .testament = .Old },
    .{ .name = "Ezekiel", .chapters = 48, .testament = .Old },
    .{ .name = "Daniel", .chapters = 12, .testament = .Old },
    .{ .name = "Hosea", .chapters = 14, .testament = .Old },
    .{ .name = "Amos", .chapters = 9, .testament = .Old },
    .{ .name = "Micah", .chapters = 7, .testament = .Old },
    .{ .name = "Joel", .chapters = 3, .testament = .Old },
    .{ .name = "Obadiah", .chapters = 1, .testament = .Old },
    .{ .name = "Jonah", .chapters = 4, .testament = .Old },
    .{ .name = "Nahum", .chapters = 3, .testament = .Old },
    .{ .name = "Habakkuk", .chapters = 3, .testament = .Old },
    .{ .name = "Zephaniah", .chapters = 3, .testament = .Old },
    .{ .name = "Haggai", .chapters = 2, .testament = .Old },
    .{ .name = "Zechariah", .chapters = 14, .testament = .Old },
    .{ .name = "Malachi", .chapters = 4, .testament = .Old },
    .{ .name = "Enoch", .chapters = 108, .testament = .Old },
    .{ .name = "Jubilees", .chapters = 50, .testament = .Old },
    .{ .name = "Matthew", .chapters = 28, .testament = .New },
    .{ .name = "Mark", .chapters = 16, .testament = .New },
    .{ .name = "Luke", .chapters = 24, .testament = .New },
    .{ .name = "John", .chapters = 21, .testament = .New },
    .{ .name = "Acts", .chapters = 28, .testament = .New },
    .{ .name = "Romans", .chapters = 16, .testament = .New },
    .{ .name = "1Corinthians", .chapters = 16, .testament = .New },
    .{ .name = "2Corinthians", .chapters = 13, .testament = .New },
    .{ .name = "Galatians", .chapters = 6, .testament = .New },
    .{ .name = "Ephesians", .chapters = 6, .testament = .New },
    .{ .name = "Philippians", .chapters = 4, .testament = .New },
    .{ .name = "Colossians", .chapters = 4, .testament = .New },
    .{ .name = "1Thessalonians", .chapters = 5, .testament = .New },
    .{ .name = "2Thessalonians", .chapters = 3, .testament = .New },
    .{ .name = "1Timothy", .chapters = 6, .testament = .New },
    .{ .name = "2Timothy", .chapters = 4, .testament = .New },
    .{ .name = "Titus", .chapters = 3, .testament = .New },
    .{ .name = "Philemon", .chapters = 1, .testament = .New },
    .{ .name = "Hebrews", .chapters = 13, .testament = .New },
    .{ .name = "1Peter", .chapters = 5, .testament = .New },
    .{ .name = "2Peter", .chapters = 3, .testament = .New },
    .{ .name = "1John", .chapters = 5, .testament = .New },
    .{ .name = "2John", .chapters = 1, .testament = .New },
    .{ .name = "3John", .chapters = 1, .testament = .New },
    .{ .name = "James", .chapters = 5, .testament = .New },
    .{ .name = "Jude", .chapters = 1, .testament = .New },
    .{ .name = "Revelation", .chapters = 22, .testament = .New },
    .{ .name = "SirateTsion", .chapters = 1, .testament = .EthiopiaExpanded },
    .{ .name = "Tizaz", .chapters = 1, .testament = .EthiopiaExpanded },
    .{ .name = "Gitsiw", .chapters = 1, .testament = .EthiopiaExpanded },
    .{ .name = "Abtilis", .chapters = 1, .testament = .EthiopiaExpanded },
    .{ .name = "1Dominos", .chapters = 1, .testament = .EthiopiaExpanded },
    .{ .name = "2Dominos", .chapters = 1, .testament = .EthiopiaExpanded },
    .{ .name = "Qalementos", .chapters = 1, .testament = .EthiopiaExpanded },
    .{ .name = "Didasqalia", .chapters = 1, .testament = .EthiopiaExpanded },
};

pub const BIBLE_ABBREVIATIONS = [_]struct { abbr: []const u8, full: []const u8 }{
    .{ .abbr = "gen", .full = "Genesis" }, .{ .abbr = "ex", .full = "Exodus" }, .{ .abbr = "lev", .full = "Leviticus" },
    .{ .abbr = "num", .full = "Numbers" }, .{ .abbr = "deut", .full = "Deuteronomy" }, .{ .abbr = "josh", .full = "Joshua" },
    .{ .abbr = "judg", .full = "Judges" }, .{ .abbr = "ruth", .full = "Ruth" }, .{ .abbr = "1sam", .full = "1Samuel" },
    .{ .abbr = "2sam", .full = "2Samuel" }, .{ .abbr = "1ki", .full = "1Kings" }, .{ .abbr = "2ki", .full = "2Kings" },
    .{ .abbr = "1chr", .full = "1Chronicles" }, .{ .abbr = "2chr", .full = "2Chronicles" }, .{ .abbr = "ezr", .full = "Ezra" },
    .{ .abbr = "neh", .full = "Nehemiah" }, .{ .abbr = "ps", .full = "Psalms" }, .{ .abbr = "prov", .full = "Proverbs" },
    .{ .abbr = "eccl", .full = "Ecclesiastes" }, .{ .abbr = "song", .full = "SongofSolomon" }, .{ .abbr = "isa", .full = "Isaiah" },
    .{ .abbr = "jer", .full = "Jeremiah" }, .{ .abbr = "lam", .full = "Lamentations" }, .{ .abbr = "eze", .full = "Ezekiel" },
    .{ .abbr = "dan", .full = "Daniel" }, .{ .abbr = "hos", .full = "Hosea" }, .{ .abbr = "joe", .full = "Joel" },
    .{ .abbr = "am", .full = "Amos" }, .{ .abbr = "oba", .full = "Obadiah" }, .{ .abbr = "jon", .full = "Jonah" },
    .{ .abbr = "mic", .full = "Micah" }, .{ .abbr = "nah", .full = "Nahum" }, .{ .abbr = "hab", .full = "Habakkuk" },
    .{ .abbr = "zep", .full = "Zephaniah" }, .{ .abbr = "hag", .full = "Haggai" }, .{ .abbr = "zec", .full = "Zechariah" },
    .{ .abbr = "mal", .full = "Malachi" }, .{ .abbr = "matt", .full = "Matthew" }, .{ .abbr = "mk", .full = "Mark" },
    .{ .abbr = "lk", .full = "Luke" }, .{ .abbr = "jn", .full = "John" }, .{ .abbr = "act", .full = "Acts" },
    .{ .abbr = "rom", .full = "Romans" }, .{ .abbr = "1cor", .full = "1Corinthians" }, .{ .abbr = "2cor", .full = "2Corinthians" },
    .{ .abbr = "gal", .full = "Galatians" }, .{ .abbr = "eph", .full = "Ephesians" }, .{ .abbr = "phi", .full = "Philippians" },
    .{ .abbr = "col", .full = "Colossians" }, .{ .abbr = "1the", .full = "1Thessalonians" }, .{ .abbr = "2the", .full = "2Thessalonians" },
    .{ .abbr = "1tim", .full = "1Timothy" }, .{ .abbr = "2tim", .full = "2Timothy" }, .{ .abbr = "tit", .full = "Titus" },
    .{ .abbr = "phm", .full = "Philemon" }, .{ .abbr = "heb", .full = "Hebrews" }, .{ .abbr = "jam", .full = "James" },
    .{ .abbr = "1pet", .full = "1Peter" }, .{ .abbr = "2pet", .full = "2Peter" }, .{ .abbr = "1jn", .full = "1John" },
    .{ .abbr = "2jn", .full = "2John" }, .{ .abbr = "3jn", .full = "3John" }, .{ .abbr = "jud", .full = "Jude" },
    .{ .abbr = "rev", .full = "Revelation" },
};

pub const SearchResult = struct {
    book: [64]u8,
    chapter: i32,
    verse: i32,
    text: ?[]const u8 = null,
};

pub fn get_chapter_verses(allocator: std.mem.Allocator, db: *sqlite3, book: []const u8, chapter: i32) !std.ArrayListUnmanaged([]const u8) {
    lockDb();
    defer unlockDb();
    var list = std.ArrayListUnmanaged([]const u8).empty;
    const sql = try std.fmt.allocPrintSentinel(allocator, "SELECT text FROM verses WHERE book='{s}' AND chapter={d} ORDER BY verse ASC", .{ book, chapter }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        while (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const t = sqlite3_column_text(stmt.?, 0);
            if (t) |text| {
                try list.append(allocator, try allocator.dupe(u8, std.mem.span(text)));
            }
        }
        _ = sqlite3_finalize(stmt.?);
    }
    return list;
}

test "bible books integrity" {
    try std.testing.expect(BIBLE_BOOKS.len > 66);
    try std.testing.expectEqualStrings("Genesis", std.mem.span(BIBLE_BOOKS[0].name));
    try std.testing.expectEqualStrings("Revelation", std.mem.span(BIBLE_BOOKS[BIBLE_BOOKS.len - 9].name));
}

test "BIBLE_BOOKS testament data matches tools/bible_books.json" {
    // tools/interlinear_scraper.py determines the Hebrew ("H") vs Greek ("G")
    // Strong's-number prefix from tools/bible_books.json, a canonical copy of
    // this array's (name, testament) pairs kept there because Python can't
    // import Zig source. If the two ever drift, original-language caching
    // silently mislabels or skips books (this test exists because that
    // already happened: "Song of Solomon" vs "SongofSolomon", plus every
    // deuterocanonical/Ethiopian OT book was missing entirely).
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const contents = try std.Io.Dir.cwd().readFileAlloc(io, "tools/bible_books.json", std.testing.allocator, std.Io.Limit.limited(1024 * 1024));
    defer std.testing.allocator.free(contents);

    const Entry = struct { name: []const u8, testament: Testament };
    const parsed = try std.json.parseFromSlice([]const Entry, std.testing.allocator, contents, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(BIBLE_BOOKS.len, parsed.value.len);
    for (BIBLE_BOOKS, parsed.value) |book, entry| {
        try std.testing.expectEqualStrings(std.mem.span(book.name), entry.name);
        try std.testing.expectEqual(book.testament, entry.testament);
    }
}

test "abbreviations" {
    var found_gen = false;
    for (BIBLE_ABBREVIATIONS) |abbr| {
        if (std.mem.eql(u8, abbr.abbr, "gen")) {
            try std.testing.expectEqualStrings("Genesis", abbr.full);
            found_gen = true;
        }
    }
    try std.testing.expect(found_gen);
}

pub const LexiconDetail = struct {
    strongs: []const u8,
    lemma: []const u8,
    transliteration: []const u8,
    definition: []const u8,
    language: []const u8,
};

pub fn get_lexicon_detail(allocator: std.mem.Allocator, db: *sqlite3, strongs: []const u8) !?LexiconDetail {
    lockDb();
    defer unlockDb();
    const sql = try std.fmt.allocPrintSentinel(allocator, "SELECT strongs, lemma, transliteration, definition, language FROM lexicon WHERE strongs='{s}'", .{strongs}, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        if (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const res = LexiconDetail{
                .strongs = try allocator.dupe(u8, std.mem.span(sqlite3_column_text(stmt.?, 0) orelse "")),
                .lemma = try allocator.dupe(u8, std.mem.span(sqlite3_column_text(stmt.?, 1) orelse "")),
                .transliteration = try allocator.dupe(u8, std.mem.span(sqlite3_column_text(stmt.?, 2) orelse "")),
                .definition = try allocator.dupe(u8, std.mem.span(sqlite3_column_text(stmt.?, 3) orelse "")),
                .language = try allocator.dupe(u8, std.mem.span(sqlite3_column_text(stmt.?, 4) orelse "")),
            };
            _ = sqlite3_finalize(stmt.?);
            return res;
        }
        _ = sqlite3_finalize(stmt.?);
    }
    return null;
}

pub fn get_verse_lexicon_context(allocator: std.mem.Allocator, db: *sqlite3, book: []const u8, chapter: i32, verse: i32) ![]const u8 {
    lockDb();
    defer unlockDb();
    var context = std.ArrayListUnmanaged(u8).empty;
    errdefer context.deinit(allocator);

    const sql = try std.fmt.allocPrintSentinel(allocator, 
        "SELECT original_text, translation, lemma, definition, usage, morphology FROM interlinear " ++
        "LEFT JOIN lexicon ON interlinear.strongs = lexicon.strongs " ++
        "WHERE book='{s}' AND chapter={d} AND verse={d} ORDER BY word_index ASC", 
        .{ book, chapter, verse }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        while (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const orig = sqlite3_column_text(stmt.?, 0) orelse "?";
            const trans = sqlite3_column_text(stmt.?, 1) orelse "?";
            const lemma = sqlite3_column_text(stmt.?, 2) orelse "";
            const def = sqlite3_column_text(stmt.?, 3) orelse "";
            const usage = sqlite3_column_text(stmt.?, 4) orelse "";
            const morph = sqlite3_column_text(stmt.?, 5) orelse "";

            const line = try std.fmt.allocPrint(allocator, "Word: {s} ({s}), Lemma: {s}, Morph: {s}, Definition: {s}, Usage: {s}\n", .{ orig, trans, lemma, morph, def, usage });
            defer allocator.free(line);
            try context.appendSlice(allocator, line);
        }
        _ = sqlite3_finalize(stmt.?);
    }
    return context.toOwnedSlice(allocator);
}

pub fn get_cross_references(allocator: std.mem.Allocator, db: *sqlite3, book: []const u8, chapter: i32, verse: i32) ![]const u8 {
    lockDb();
    defer unlockDb();
    var xrefs = std.ArrayListUnmanaged(u8).empty;
    errdefer xrefs.deinit(allocator);

    const sql = try std.fmt.allocPrintSentinel(allocator, 
        "SELECT to_book, to_chapter, to_verse FROM cross_references " ++
        "WHERE from_book='{s}' AND from_chapter={d} AND from_verse={d} LIMIT 10", 
        .{ book, chapter, verse }, 0);
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        while (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const b = sqlite3_column_text(stmt.?, 0) orelse "?";
            const c = sqlite3_column_int(stmt.?, 1);
            const v = sqlite3_column_int(stmt.?, 2);

            const line = try std.fmt.allocPrint(allocator, "- {s} {d}:{d}\n", .{ b, c, v });
            defer allocator.free(line);
            try xrefs.appendSlice(allocator, line);
        }
        _ = sqlite3_finalize(stmt.?);
    }
    
    if (xrefs.items.len == 0) return try allocator.dupe(u8, "No direct cross-references found.");
    return xrefs.toOwnedSlice(allocator);
}

// --- Scraper writes (src/native_scraper.zig) --------------------------------
// Mirror the exact INSERT shapes tools/interlinear_scraper.py and
// tools/lexicon_scraper.py use (INSERT OR REPLACE, same column order), so a
// native-Zig scrape and a Python scrape produce identical rows.

pub fn insert_interlinear_word(db: *sqlite3, book: []const u8, chapter: i32, verse: i32, word_index: i32, original_text: []const u8, translation: []const u8, strongs: []const u8, morphology: []const u8) void {
    lockDb();
    defer unlockDb();
    const sql = "INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs, morphology) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) != SQLITE_OK) return;
    defer _ = sqlite3_finalize(stmt.?);
    bindText(stmt.?, 1, book);
    _ = sqlite3_bind_int(stmt.?, 2, chapter);
    _ = sqlite3_bind_int(stmt.?, 3, verse);
    _ = sqlite3_bind_int(stmt.?, 4, word_index);
    bindText(stmt.?, 5, original_text);
    bindText(stmt.?, 6, translation);
    bindText(stmt.?, 7, strongs);
    bindText(stmt.?, 8, morphology);
    _ = sqlite3_step(stmt.?);
}

pub fn insert_lexicon_entry(db: *sqlite3, strongs: []const u8, language: []const u8, lemma: []const u8, transliteration: []const u8, definition: []const u8, usage: []const u8) void {
    lockDb();
    defer unlockDb();
    const sql = "INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition, usage) VALUES (?, ?, ?, ?, ?, ?)";
    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) != SQLITE_OK) return;
    defer _ = sqlite3_finalize(stmt.?);
    bindText(stmt.?, 1, strongs);
    bindText(stmt.?, 2, language);
    bindText(stmt.?, 3, lemma);
    bindText(stmt.?, 4, transliteration);
    bindText(stmt.?, 5, definition);
    bindText(stmt.?, 6, usage);
    _ = sqlite3_step(stmt.?);
}

pub fn lexicon_has_strongs(db: *sqlite3, strongs: []const u8) bool {
    lockDb();
    defer unlockDb();
    const sql = "SELECT 1 FROM lexicon WHERE strongs = ?";
    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) != SQLITE_OK) return false;
    defer _ = sqlite3_finalize(stmt.?);
    bindText(stmt.?, 1, strongs);
    return sqlite3_step(stmt.?) == SQLITE_ROW;
}

/// Distinct, non-empty Strong's numbers referenced by the interlinear table,
/// optionally scoped to one book/chapter -- mirrors tools/lexicon_scraper.py's
/// cache_lexicon_from_db(book, chapter) scoping (see that function's
/// docstring). Caller owns the returned slice and each string in it.
pub fn distinct_interlinear_strongs(allocator: std.mem.Allocator, db: *sqlite3, book: ?[]const u8, chapter: ?i32) ![][]const u8 {
    lockDb();
    defer unlockDb();
    var list = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (list.items) |s| allocator.free(s);
        list.deinit(allocator);
    }

    const scoped = book != null and chapter != null;
    const sql: [*:0]const u8 = if (scoped)
        "SELECT DISTINCT strongs FROM interlinear WHERE strongs != '' AND book = ? AND chapter = ?"
    else
        "SELECT DISTINCT strongs FROM interlinear WHERE strongs != ''";

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) != SQLITE_OK) return list.toOwnedSlice(allocator);
    defer _ = sqlite3_finalize(stmt.?);
    if (scoped) {
        bindText(stmt.?, 1, book.?);
        _ = sqlite3_bind_int(stmt.?, 2, chapter.?);
    }
    while (sqlite3_step(stmt.?) == SQLITE_ROW) {
        const s = sqlite3_column_text(stmt.?, 0) orelse continue;
        try list.append(allocator, try allocator.dupe(u8, std.mem.span(s)));
    }
    return list.toOwnedSlice(allocator);
}

// --- SQL round-trip tests ---------------------------------------------------
// Before these, none of bible_db.zig's SQL read/write paths had any test
// coverage at all — including get_verse_lexicon_context, the exact function
// llm_engine.zig checks to decide whether original-language data needs to be
// (re-)scraped. An in-memory db + init_db() gives each test a real, isolated
// SQLite connection with no filesystem side effects.

fn openTestDb() *sqlite3 {
    var db: ?*sqlite3 = null;
    const rc = sqlite3_open(":memory:", @ptrCast(&db));
    std.debug.assert(rc == SQLITE_OK);
    init_db(db.?) catch unreachable;
    return db.?;
}

test "chapter summary: missing then round-trips after save" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    const missing = try get_chapter_summary(std.testing.allocator, db, "John", 3);
    defer std.testing.allocator.free(missing);
    try std.testing.expectEqualStrings("No literary summary found for this chapter.", missing);

    try save_chapter_summary(db, "John", 3, "For God so loved the world.");
    const found = try get_chapter_summary(std.testing.allocator, db, "John", 3);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqualStrings("For God so loved the world.", found);
}

test "verse note: empty then round-trips after save" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    const empty = try get_verse_note(std.testing.allocator, db, "Genesis", 1, 1);
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqualStrings("", empty);

    try save_verse_note(db, "Genesis", 1, 1, "In the beginning.");
    const note = try get_verse_note(std.testing.allocator, db, "Genesis", 1, 1);
    defer std.testing.allocator.free(note);
    try std.testing.expectEqualStrings("In the beginning.", note);
}

test "verse highlight: set, read, delete" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    try set_verse_highlight(db, "Genesis", 1, 1, "#7aa2f7");
    {
        var highlights = try get_chapter_highlights(std.testing.allocator, db, "Genesis", 1);
        defer {
            var it = highlights.valueIterator();
            while (it.next()) |v| std.testing.allocator.free(v.*);
            highlights.deinit(std.testing.allocator);
        }
        try std.testing.expectEqualStrings("#7aa2f7", highlights.get(1).?);
    }

    try delete_verse_highlight(db, "Genesis", 1, 1);
    {
        var highlights = try get_chapter_highlights(std.testing.allocator, db, "Genesis", 1);
        defer highlights.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), highlights.count());
    }
}

test "book metadata: unknown then round-trips after insert" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    const unknown = try get_book_metadata(std.testing.allocator, db, "John");
    defer std.testing.allocator.free(unknown);
    try std.testing.expectEqualStrings("No historical metadata found for this book.", unknown);

    const sql = try std.fmt.allocPrintSentinel(std.testing.allocator, "INSERT INTO book_metadata (book, author, date, audience, context) VALUES ('John', 'John the Apostle', 'c. 90 AD', 'Early Christians', 'Written to affirm the divinity of Christ')", .{}, 0);
    defer std.testing.allocator.free(sql);
    var stmt: ?*sqlite3_stmt = null;
    try std.testing.expectEqual(SQLITE_OK, sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null));
    _ = sqlite3_step(stmt.?);
    _ = sqlite3_finalize(stmt.?);

    const found = try get_book_metadata(std.testing.allocator, db, "John");
    defer std.testing.allocator.free(found);
    try std.testing.expect(std.mem.indexOf(u8, found, "John the Apostle") != null);
}

test "get_chapter_verses: returns verses in verse order" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    const inserts = [_][*:0]const u8{
        "INSERT INTO verses (book, chapter, verse, text, version) VALUES ('John', 3, 16, 'For God so loved the world.', 'NKJV')",
        "INSERT INTO verses (book, chapter, verse, text, version) VALUES ('John', 3, 17, 'For God did not send His Son to condemn.', 'NKJV')",
    };
    for (inserts) |q| {
        var stmt: ?*sqlite3_stmt = null;
        try std.testing.expectEqual(SQLITE_OK, sqlite3_prepare_v2(db, q, -1, @ptrCast(&stmt), null));
        _ = sqlite3_step(stmt.?);
        _ = sqlite3_finalize(stmt.?);
    }

    var verses = try get_chapter_verses(std.testing.allocator, db, "John", 3);
    defer {
        for (verses.items) |v| std.testing.allocator.free(v);
        verses.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(usize, 2), verses.items.len);
    try std.testing.expect(std.mem.startsWith(u8, verses.items[0], "For God so loved"));
    try std.testing.expect(std.mem.startsWith(u8, verses.items[1], "For God did not send"));
}

test "get_verse_lexicon_context: this is what llm_engine checks to decide whether to (re-)scrape" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    // Nothing cached yet -> empty context, exactly what llm_engine.zig treats
    // as "needs scraping".
    {
        const ctx = try get_verse_lexicon_context(std.testing.allocator, db, "John", 3, 16);
        defer std.testing.allocator.free(ctx);
        try std.testing.expectEqual(@as(usize, 0), ctx.len);
    }

    const interlinear_sql = "INSERT INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs, morphology) VALUES ('John', 3, 16, 0, '\u{3fc}\u{3b3}\u{3ac}\u{3c0}\u{3b7}\u{3c3}\u{3b5}\u{3bd}', 'loved', 'G25', 'V-AAI-3S')";
    {
        var stmt: ?*sqlite3_stmt = null;
        try std.testing.expectEqual(SQLITE_OK, sqlite3_prepare_v2(db, interlinear_sql, -1, @ptrCast(&stmt), null));
        _ = sqlite3_step(stmt.?);
        _ = sqlite3_finalize(stmt.?);
    }
    const lexicon_sql = "INSERT INTO lexicon (strongs, language, lemma, transliteration, definition, usage) VALUES ('G25', 'greek', '\u{3b1}\u{3b3}\u{3b1}\u{3c0}\u{3ac}\u{3c9}', 'agapao', 'to love', 'to love, wish well to')";
    {
        var stmt: ?*sqlite3_stmt = null;
        try std.testing.expectEqual(SQLITE_OK, sqlite3_prepare_v2(db, lexicon_sql, -1, @ptrCast(&stmt), null));
        _ = sqlite3_step(stmt.?);
        _ = sqlite3_finalize(stmt.?);
    }

    // Now cached -> non-empty context that carries the joined lexicon fields
    // (get_verse_lexicon_context selects original_text/translation/morphology
    // from interlinear and lemma/definition/usage from the lexicon join —
    // note it does NOT select transliteration, unlike get_lexicon_detail).
    const ctx = try get_verse_lexicon_context(std.testing.allocator, db, "John", 3, 16);
    defer std.testing.allocator.free(ctx);
    try std.testing.expect(ctx.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, ctx, "loved") != null);
    try std.testing.expect(std.mem.indexOf(u8, ctx, "V-AAI-3S") != null);
    try std.testing.expect(std.mem.indexOf(u8, ctx, "to love") != null);

    // A different, uncached verse must still read as empty.
    const other = try get_verse_lexicon_context(std.testing.allocator, db, "John", 3, 17);
    defer std.testing.allocator.free(other);
    try std.testing.expectEqual(@as(usize, 0), other.len);
}

test "insert_interlinear_word / insert_lexicon_entry: parameterized binds round-trip values containing single quotes" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    // A translation gloss with an apostrophe would corrupt a string-interpolated
    // INSERT (like every other write helper in this file uses); the bound
    // version added for the scraper must not have that problem.
    insert_interlinear_word(db, "Genesis", 1, 27, 3, "בְּצֶ֥לֶם", "God's own image", "H6754", "N-msc");
    insert_lexicon_entry(db, "H6754", "hebrew", "צֶ֫לֶם", "tselem", "Adam's likeness, an image", "");

    const ctx = try get_verse_lexicon_context(std.testing.allocator, db, "Genesis", 1, 27);
    defer std.testing.allocator.free(ctx);
    try std.testing.expect(std.mem.indexOf(u8, ctx, "God's own image") != null);
    try std.testing.expect(std.mem.indexOf(u8, ctx, "Adam's likeness, an image") != null);

    try std.testing.expect(lexicon_has_strongs(db, "H6754"));
    try std.testing.expect(!lexicon_has_strongs(db, "H0000"));

    // INSERT OR REPLACE: re-inserting the same (book, chapter, verse, word_index)
    // updates in place rather than duplicating the row.
    insert_interlinear_word(db, "Genesis", 1, 27, 3, "בְּצֶ֥לֶם", "in the image of", "H6754", "N-msc");
    const ctx2 = try get_verse_lexicon_context(std.testing.allocator, db, "Genesis", 1, 27);
    defer std.testing.allocator.free(ctx2);
    try std.testing.expect(std.mem.indexOf(u8, ctx2, "in the image of") != null);
    try std.testing.expect(std.mem.indexOf(u8, ctx2, "God's own image") == null);
}

test "distinct_interlinear_strongs: unscoped vs scoped to one book/chapter" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    insert_interlinear_word(db, "Genesis", 1, 1, 0, "orig1", "In", "H7225", "");
    insert_interlinear_word(db, "Genesis", 1, 1, 1, "orig2", "beginning", "H7225", ""); // duplicate strongs, same chapter
    insert_interlinear_word(db, "Genesis", 2, 1, 0, "orig3", "thus", "H3541", "");
    insert_interlinear_word(db, "John", 3, 16, 0, "orig4", "For", "G1063", "");
    insert_interlinear_word(db, "John", 3, 16, 1, "orig5", ".", "", ""); // empty strongs excluded

    {
        const all = try distinct_interlinear_strongs(std.testing.allocator, db, null, null);
        defer {
            for (all) |s| std.testing.allocator.free(s);
            std.testing.allocator.free(all);
        }
        try std.testing.expectEqual(@as(usize, 3), all.len);
    }

    {
        const scoped = try distinct_interlinear_strongs(std.testing.allocator, db, "Genesis", 1);
        defer {
            for (scoped) |s| std.testing.allocator.free(s);
            std.testing.allocator.free(scoped);
        }
        try std.testing.expectEqual(@as(usize, 1), scoped.len);
        try std.testing.expectEqualStrings("H7225", scoped[0]);
    }

    {
        const scoped_ch2 = try distinct_interlinear_strongs(std.testing.allocator, db, "Genesis", 2);
        defer {
            for (scoped_ch2) |s| std.testing.allocator.free(s);
            std.testing.allocator.free(scoped_ch2);
        }
        try std.testing.expectEqual(@as(usize, 1), scoped_ch2.len);
        try std.testing.expectEqualStrings("H3541", scoped_ch2[0]);
    }
}

test "get_lexicon_detail: found vs not found" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    try std.testing.expectEqual(@as(?LexiconDetail, null), try get_lexicon_detail(std.testing.allocator, db, "G25"));

    const sql = "INSERT INTO lexicon (strongs, language, lemma, transliteration, definition, usage) VALUES ('G25', 'greek', 'lemma', 'agapao', 'to love', 'usage')";
    var stmt: ?*sqlite3_stmt = null;
    try std.testing.expectEqual(SQLITE_OK, sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null));
    _ = sqlite3_step(stmt.?);
    _ = sqlite3_finalize(stmt.?);

    const detail = (try get_lexicon_detail(std.testing.allocator, db, "G25")).?;
    defer {
        std.testing.allocator.free(detail.strongs);
        std.testing.allocator.free(detail.lemma);
        std.testing.allocator.free(detail.transliteration);
        std.testing.allocator.free(detail.definition);
        std.testing.allocator.free(detail.language);
    }
    try std.testing.expectEqualStrings("agapao", detail.transliteration);
    try std.testing.expectEqualStrings("greek", detail.language);
}

test "get_cross_references: none found vs found" {
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    const none = try get_cross_references(std.testing.allocator, db, "John", 3, 16);
    defer std.testing.allocator.free(none);
    try std.testing.expectEqualStrings("No direct cross-references found.", none);

    const sql = "INSERT INTO cross_references (from_book, from_chapter, from_verse, to_book, to_chapter, to_verse) VALUES ('John', 3, 16, 'Romans', 5, 8)";
    var stmt: ?*sqlite3_stmt = null;
    try std.testing.expectEqual(SQLITE_OK, sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null));
    _ = sqlite3_step(stmt.?);
    _ = sqlite3_finalize(stmt.?);

    const found = try get_cross_references(std.testing.allocator, db, "John", 3, 16);
    defer std.testing.allocator.free(found);
    try std.testing.expect(std.mem.indexOf(u8, found, "Romans 5:8") != null);
}

test "concurrent writers on a shared connection don't corrupt or drop data" {
    // llm_engine.zig's analyzeVerse runs on a detached GTK thread per click
    // (g_thread_new in services/llm_engine.zig), all sharing the single
    // sqlite3 connection opened once in main() (state.db) — nothing stops
    // two overlapping clicks, or a click racing a background scrape, from
    // writing through that same handle concurrently. This is the
    // race-condition regression guard: N threads write distinct rows through
    // one shared *sqlite3 concurrently, and every write must land with none
    // corrupted or silently lost.
    const db = openTestDb();
    defer _ = sqlite3_close(db);

    const thread_count = 8;
    const Writer = struct {
        db: *sqlite3,
        index: usize,

        fn run(self: *const @This()) void {
            var buf: [8]u8 = undefined;
            const color = std.fmt.bufPrint(&buf, "#{d:0>6}", .{self.index}) catch unreachable;
            set_verse_highlight(self.db, "Psalms", 119, @intCast(self.index + 1), color) catch unreachable;
        }
    };

    var writers: [thread_count]Writer = undefined;
    var threads: [thread_count]std.Thread = undefined;
    for (0..thread_count) |i| {
        writers[i] = .{ .db = db, .index = i };
        threads[i] = try std.Thread.spawn(.{}, Writer.run, .{&writers[i]});
    }
    for (&threads) |*t| t.join();

    var highlights = try get_chapter_highlights(std.testing.allocator, db, "Psalms", 119);
    defer {
        var it = highlights.valueIterator();
        while (it.next()) |v| std.testing.allocator.free(v.*);
        highlights.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, thread_count), highlights.count());
    for (0..thread_count) |i| {
        var expected_buf: [8]u8 = undefined;
        const expected = std.fmt.bufPrint(&expected_buf, "#{d:0>6}", .{i}) catch unreachable;
        const got = highlights.get(@intCast(i + 1)) orelse return error.MissingWrite;
        try std.testing.expectEqualStrings(expected, got);
    }
}

// --- Real shipped-data completeness check ---------------------------------
// Everything above uses an in-memory db with synthetic rows. This test opens
// the actual data/bible.db that ships with the app (tracked in git as of
// 2026-07-19, see .gitignore's data/*.db exception + docs/PACKAGING.md) and
// checks the real content isn't truncated/corrupted — a regression here
// means the shipped Bible text itself broke, not just a code path.

// BIBLE_BOOKS entries known to have NO verse text in data/bible.db today —
// BibleHub-sourced content only covers the standard 66-book Protestant
// canon; these deuterocanonical/Ethiopian-canon books are listed (and
// selectable in the book picker) but have never had verse text sourced for
// them. This is a known content gap (see docs/MAINTENANCE.md), not a bug —
// listed explicitly here so if one of these gets real content in the
// future, this test starts telling you to remove it from the list instead
// of silently gaining unasserted coverage.
const books_with_no_verse_text = [_][]const u8{
    "Tobit",     "Judith",       "1Meqabyan",  "2Meqabyan", "3Meqabyan",
    "Tegsas",    "Wisdom",       "Sirach",     "Enoch",     "Jubilees",
    "SirateTsion", "Tizaz",      "Gitsiw",     "Abtilis",
    "1Dominos",  "2Dominos",     "Qalementos", "Didasqalia",
};

fn hasKnownGap(name: []const u8) bool {
    for (books_with_no_verse_text) |gap| {
        if (std.mem.eql(u8, gap, name)) return true;
    }
    return false;
}

test "shipped data/bible.db has verse text for every canonical (non-gap) book" {
    var db: ?*sqlite3 = null;
    if (sqlite3_open("data/bible.db", @ptrCast(&db)) != SQLITE_OK) {
        return error.SkipZigTest; // not every checkout/environment has it; CI does.
    }
    defer _ = sqlite3_close(db.?);

    var total_covered: usize = 0;
    for (BIBLE_BOOKS) |book| {
        const name = std.mem.span(book.name);
        const sql = try std.fmt.allocPrintSentinel(std.testing.allocator, "SELECT COUNT(*) FROM verses WHERE book='{s}'", .{name}, 0);
        defer std.testing.allocator.free(sql);

        var stmt: ?*sqlite3_stmt = null;
        try std.testing.expectEqual(SQLITE_OK, sqlite3_prepare_v2(db.?, sql, -1, @ptrCast(&stmt), null));
        defer _ = sqlite3_finalize(stmt.?);
        try std.testing.expectEqual(SQLITE_ROW, sqlite3_step(stmt.?));
        const count = sqlite3_column_int(stmt.?, 0);

        if (hasKnownGap(name)) continue;
        if (count == 0) {
            std.debug.print("REGRESSION: '{s}' has zero verses in data/bible.db and is not in the known-gap list\n", .{name});
            return error.MissingVerseText;
        }
        total_covered += 1;
    }

    try std.testing.expectEqual(@as(usize, BIBLE_BOOKS.len - books_with_no_verse_text.len), total_covered);

    var stmt: ?*sqlite3_stmt = null;
    try std.testing.expectEqual(SQLITE_OK, sqlite3_prepare_v2(db.?, "SELECT COUNT(*) FROM verses", -1, @ptrCast(&stmt), null));
    defer _ = sqlite3_finalize(stmt.?);
    try std.testing.expectEqual(SQLITE_ROW, sqlite3_step(stmt.?));
    const total_verses = sqlite3_column_int(stmt.?, 0);
    // NKJV is ~31,102 verses; give some slack but catch gross truncation.
    try std.testing.expect(total_verses > 25000);
}
