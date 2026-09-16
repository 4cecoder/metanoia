//! Volatile maintenance binary for native interlinear/lexicon scraping.
//!
//! The GTK reader launches this companion when it needs live original-language
//! data. Keeping the network/HTML implementation in a separate executable
//! means scraper markup changes do not enter the reader's link graph.

const std = @import("std");
const core = @import("core");
const native_scraper = @import("native_scraper.zig");

const bible = core.bible;

fn usage() void {
    std.debug.print(
        "Usage: metanoia-scraper <interlinear|lexicon> <book> <chapter>\n",
        .{},
    );
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) {
        usage();
        return;
    }

    const chapter = std.fmt.parseInt(i32, args[3], 10) catch {
        std.debug.print("Invalid chapter: {s}\n", .{args[3]});
        return error.InvalidArguments;
    };

    var threaded_io = std.Io.Threaded.init(init.arena.allocator(), .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    var db: ?*bible.sqlite3 = null;
    if (bible.sqlite3_open("data/bible.db", @ptrCast(&db)) != bible.SQLITE_OK or db == null) {
        std.debug.print("Failed to open data/bible.db\n", .{});
        return error.DatabaseOpenFailed;
    }
    defer _ = bible.sqlite3_close(db.?);

    if (std.mem.eql(u8, args[1], "interlinear")) {
        try native_scraper.scrapeInterlinear(io, init.arena.allocator(), db.?, args[2], chapter);
    } else if (std.mem.eql(u8, args[1], "lexicon")) {
        try native_scraper.scrapeLexicon(io, init.arena.allocator(), db.?, args[2], chapter);
    } else {
        usage();
        return error.InvalidArguments;
    }
}
