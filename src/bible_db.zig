const std = @import("std");

pub const sqlite3 = anyopaque;
pub const sqlite3_stmt = anyopaque;
pub extern fn sqlite3_open(filename: [*:0]const u8, ppDb: **sqlite3) i32;
pub extern fn sqlite3_close(db: *sqlite3) i32;
pub extern fn sqlite3_prepare_v2(db: *sqlite3, zSql: [*:0]const u8, nByte: i32, ppStmt: **sqlite3_stmt, pzTail: ?**const u8) i32;
pub extern fn sqlite3_step(stmt: *sqlite3_stmt) i32;
pub extern fn sqlite3_column_text(stmt: *sqlite3_stmt, iCol: i32) ?[*:0]const u8;
pub extern fn sqlite3_column_int(stmt: *sqlite3_stmt, iCol: i32) i32;
pub extern fn sqlite3_finalize(stmt: *sqlite3_stmt) i32;

pub const SQLITE_ROW = 100;
pub const SQLITE_OK = 0;

pub fn init_db(db: *sqlite3) !void {
    const queries = [_][*:0]const u8{
        "CREATE TABLE IF NOT EXISTS highlights (book TEXT, chapter INTEGER, verse INTEGER, color TEXT, PRIMARY KEY(book, chapter, verse))",
        "CREATE TABLE IF NOT EXISTS lexical_favorites (strongs TEXT PRIMARY KEY, lemma TEXT, definition TEXT)",
        "CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, chapter INTEGER, verse INTEGER, content TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)",
        "CREATE TABLE IF NOT EXISTS book_metadata (book TEXT PRIMARY KEY, author TEXT, date TEXT, audience TEXT, context TEXT)",
        "CREATE TABLE IF NOT EXISTS chapter_summaries (book TEXT, chapter INTEGER, summary TEXT, PRIMARY KEY(book, chapter))",
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
