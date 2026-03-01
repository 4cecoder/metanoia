const std = @import("std");

pub const sqlite3 = anyopaque;
pub const sqlite3_stmt = anyopaque;
pub extern fn sqlite3_open(filename: [*:0]const u8, ppDb: **sqlite3) i32;
pub extern fn sqlite3_close(db: *sqlite3) i32;
pub extern fn sqlite3_prepare_v2(db: *sqlite3, zSql: [*:0]const u8, nByte: i32, ppStmt: **sqlite3_stmt, pzTail: ?**const u8) i32;
pub extern fn sqlite3_step(stmt: *sqlite3_stmt) i32;
pub extern fn sqlite3_column_text(stmt: *sqlite3_stmt, iCol: i32) ?[*:0]const u8;
pub extern fn sqlite3_finalize(stmt: *sqlite3_stmt) i32;

pub fn main() !void {
    var db: ?*sqlite3 = null;
    _ = sqlite3_open("data/bible.db", @ptrCast(&db));
    defer _ = sqlite3_close(db.?);

    var stmt: ?*sqlite3_stmt = null;
    const sql = "SELECT original_text FROM interlinear WHERE book='John' AND chapter=3 AND verse=1 LIMIT 5";
    if (sqlite3_prepare_v2(db.?, sql, -1, @ptrCast(&stmt), null) == 0) {
        while (sqlite3_step(stmt.?) == 100) {
            const text = sqlite3_column_text(stmt.?, 0);
            std.debug.print("Word: {s}\n", .{text.?});
        }
        _ = sqlite3_finalize(stmt.?);
    }
}
