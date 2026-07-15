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

    pub fn deinit(self: *LLMEngine) void {
        self.allocator.destroy(self);
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

                // Step 0: Check for lexicon data, scrape from BibleHub if missing
                s.cb.onStep("Step 0/4: Checking for factual data...");
                {
                    const test_lex = bible.get_verse_lexicon_context(allocator, s.engine.db.?, s.book, s.chapter, s.verse) catch "";
                    defer if (test_lex.len > 0) allocator.free(test_lex);
                    if (test_lex.len == 0) {
                        s.cb.onStep("Auto-Tooling: Fetching Interlinear Data from BibleHub...");
                        scraper.scrape_interlinear(s.engine.io, s.book, s.chapter) catch {};
                        scraper.scrape_lexicon(s.engine.io) catch {};
                    }
                }

                // Step 1: Gather historical/lexical facts
                s.cb.onStep("Step 1/4: Gathering Historical & Lexical Facts...");

                const lex_context = bible.get_verse_lexicon_context(allocator, s.engine.db.?, s.book, s.chapter, s.verse) catch "";
                defer if (lex_context.len > 0) allocator.free(lex_context);

                const xref_context = bible.get_cross_references(allocator, s.engine.db.?, s.book, s.chapter, s.verse) catch "";
                defer if (xref_context.len > 0) allocator.free(xref_context);

                const hist_context = bible.get_book_metadata(allocator, s.engine.db.?, s.book) catch "";
                defer if (hist_context.len > 0) allocator.free(hist_context);

                // Step 2: Create chapter summary (check cache, generate via Ollama if missing)
                var summary_context = bible.get_chapter_summary(allocator, s.engine.db.?, s.book, s.chapter) catch "";
                const summary_was_missing = std.mem.containsAtLeast(u8, summary_context, 1, "No literary summary found");

                if (summary_was_missing) {
                    s.cb.onStep("Step 2/4: Creating Literary Context (Summarizing)...");
                    allocator.free(summary_context);

                    const chapter_verses = bible.get_chapter_verses(allocator, s.engine.db.?, s.book, s.chapter) catch null;
                    if (chapter_verses) |cv| {
                        defer {
                            for (cv.items) |v| allocator.free(v);
                            var list = cv;
                            list.deinit(allocator);
                        }
                        var full_text = std.ArrayListUnmanaged(u8).empty;
                        defer full_text.deinit(allocator);
                        for (cv.items) |v| {
                            full_text.appendSlice(allocator, v) catch {};
                            full_text.append(allocator, ' ') catch {};
                        }

                        const summary_prompt = std.fmt.allocPrint(allocator,
                            "Summarize the following Bible chapter in one concise sentence: {s} {d} - \"{s}\"",
                            .{ s.book, s.chapter, full_text.items }
                        ) catch "No summary available.";
                        defer if (!std.mem.eql(u8, summary_prompt, "No summary available.")) allocator.free(summary_prompt);

                        summary_context = ollama.generate_response(allocator, s.engine.io, summary_prompt) catch (allocator.dupe(u8, "No summary available.") catch "");
                        if (summary_context.len > 0 and !std.mem.eql(u8, summary_context, "No summary available.")) {
                            bible.save_chapter_summary(s.engine.db.?, s.book, s.chapter, summary_context) catch {};
                        }
                    } else {
                        summary_context = allocator.dupe(u8, "No summary available.") catch "";
                    }
                }
                defer if (summary_context.len > 0) allocator.free(summary_context);

                s.cb.onSummary(summary_context);

                // Step 3: Synthesize scholarly insight using Ollama
                s.cb.onStep("Step 3/4: Synthesizing Scholarly Insight...");

                const prompt = std.fmt.allocPrint(allocator,
                    "System: You are a precise biblical scholar. Use ONLY the provided data to explain the verse.\n\n" ++
                    "Verse: {s} {d}:{d}\n" ++
                    "Text: \"{s}\"\n\n" ++
                    "Historical Context: {s}\n\n" ++
                    "Chapter Summary: {s}\n\n" ++
                    "Lexicon & Morphology:\n{s}\n\n" ++
                    "Cross References:\n{s}\n\n" ++
                    "Instruction: Provide a concise scholarly insight. Explain how the historical setting and chapter summary (literary context) inform the original word meanings to clarify the verse's intent. Connect it to a cross-reference.",
                    .{ s.book, s.chapter, s.verse, s.text, hist_context, summary_context, lex_context, xref_context }
                ) catch return null;
                defer allocator.free(prompt);

                const response = ollama.generate_response(allocator, s.engine.io, prompt) catch |err| {
                    const err_msg = std.fmt.allocPrint(allocator, "LLM Error: {any}", .{err}) catch return null;
                    defer allocator.free(err_msg);
                    s.cb.onError(err_msg);
                    return null;
                };
                defer allocator.free(response);

                s.cb.onResult(response);

                allocator.free(s.book);
                allocator.free(s.text);
                allocator.destroy(s);
                return null;
            }
        };

        const task = self.allocator.create(Task) catch return;
        task.* = .{
            .engine = self,
            .book = self.allocator.dupe(u8, book) catch return,
            .chapter = chapter,
            .verse = verse,
            .text = self.allocator.dupe(u8, text) catch return,
            .cb = callbacks,
        };
        _ = gtk.g_thread_new("llm-analysis", &Task.run, task);
    }
};
