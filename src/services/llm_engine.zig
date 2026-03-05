const std = @import("std");
const gtk = @import("../gtk.zig");
const ollama = @import("../ollama_client.zig");
const bible = @import("../bible_db.zig");
const scraper = @import("../scraper_client.zig");

const gpointer = gtk.gpointer;

pub const LLMEngine = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    db: ?*bible.sqlite3,
    
    pub const AnalysisCallbacks = struct {
        onStep: *const fn (msg: []const u8) void,
        onSummary: *const fn (summary: []const u8) void,
        onResult: *const fn (result: []const u8) void,
        onError: *const fn (err: []const u8) void,
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io, db: ?*bible.sqlite3) *LLMEngine {
        const self = allocator.create(LLMEngine) catch unreachable;
        self.* = .{
            .allocator = allocator,
            .io = io,
            .db = db,
        };
        return self;
    }

    pub fn analyzeVerse(self: *LLMEngine, book: []const u8, chapter: i32, verse: i32, text: []const u8, callbacks: AnalysisCallbacks) void {
        const Task = struct {
            engine: *LLMEngine,
            book: []const u8,
            chapter: i32,
            verse: i32,
            text: []const u8,
            cb: AnalysisCallbacks,

            fn run(p: gpointer) callconv(.c) gpointer {
                const s: *@This() = @ptrCast(@alignCast(p));
                const allocator = s.engine.allocator;
                
                // Step 1: Lexical Facts
                s.cb.onStep("Gathering Lexical & Historical Facts...");
                const lex = bible.get_verse_lexicon_context(allocator, s.engine.db.?, s.book, s.chapter, s.verse) catch "";
                defer if (lex.len > 0) allocator.free(lex);

                // Step 2: Contextual Summary
                s.cb.onStep("Synthesizing Literary Context...");
                var summary = bible.get_chapter_summary(allocator, s.engine.db.?, s.book, s.chapter) catch "";
                defer if (summary.len > 0) allocator.free(summary);
                s.cb.onSummary(summary);

                // Step 3: Neural Synthesis
                s.cb.onStep("Engaging Granite 4 Scholar...");
                const prompt = std.fmt.allocPrint(allocator, 
                    "Bible Verse: {s} {d}:{d}\nText: {s}\nContext: {s}\nSummary: {s}\nInsight:",
                    .{ s.book, s.chapter, s.verse, s.text, lex, summary }
                ) catch return null;
                defer allocator.free(prompt);

                if (ollama.generate_response(allocator, s.engine.io, prompt)) |res| {
                    s.cb.onResult(res);
                    allocator.free(res);
                } else |err| {
                    const err_msg = std.fmt.allocPrint(allocator, "LLM Failure: {any}", .{err}) catch "LLM Error";
                    s.cb.onError(err_msg);
                    if (!std.mem.eql(u8, err_msg, "LLM Error")) allocator.free(err_msg);
                }

                allocator.free(s.book);
                allocator.free(s.text);
                allocator.destroy(s);
                return null;
            }
        };

        const task = self.allocator.create(Task) catch return;
        task.* = .{
            .engine = self,
            .book = self.allocator.dupe(u8, book) catch "",
            .chapter = chapter,
            .verse = verse,
            .text = self.allocator.dupe(u8, text) catch "",
            .cb = callbacks,
        };
        _ = gtk.g_thread_new("llm-analysis", &Task.run, task);
    }
};
