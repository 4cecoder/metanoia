//! A from-scratch Zig implementation of byte-level BPE tokenization,
//! compatible with HuggingFace `tokenizers` library JSON exports
//! (`tokenizer.json`) for models in the GPT-2 tokenizer family — Qwen2/
//! Qwen2.5 included, which is what this was built and tested against.
//!
//! Placement note: this lives at the top level (`src/tokenizer.zig`), not
//! under `backend/` (raw C FFI to a native inference library — this is
//! pure Zig, nothing to FFI-bind) or `models/` (a concrete implementation
//! of a `capabilities/*.zig` vtable interface — tokenization isn't a
//! swappable-backend concept the way `tts.Synthesizer` is: there's one
//! algorithm, byte-level BPE, and no interface worth abstracting yet). It
//! *is* backend-agnostic the way `capabilities/` is meant to be, so it's
//! reasonable to think of this as a capability-shaped utility without the
//! ceremony of a vtable — a future `models/qwen2_*.zig` LLM capability
//! (see README.md's "LLM inference" section) would depend on this the
//! same way it'd depend on `backend/mlx.zig` for tensor ops.
//!
//! What this implements, end to end:
//!  - the GPT-2 byte<->unicode remapping (every raw byte 0-255 gets a
//!    printable, independently-mergeable character)
//!  - the GPT-2/Qwen pre-tokenizer regex, hand-rolled as a codepoint
//!    scanning state machine (Zig's std has no Unicode regex engine)
//!    rather than a literal regex — HF's pattern is fixed and well-known:
//!    `(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}|
//!     ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+`
//!  - greedy lowest-merge-rank BPE, applied per pre-tokenized chunk
//!  - added/special-token handling (`<|im_start|>` etc.) — split out of
//!    the text and passed through as literal ids/text, bypassing BPE
//!
//! Known limitation: `\p{L}` / `\p{N}` Unicode general-category tests are
//! approximated, not the full Unicode Character Database — exact for
//! ASCII (and this file's test oracle is ASCII), best-effort for other
//! scripts (non-ASCII codepoints are classified as letters unless they
//! fall in a handful of known whitespace/punctuation blocks).

const std = @import("std");

/// One BPE token, as loaded from `tokenizer.json`'s `model.vocab`.
const SpecialToken = struct {
    text: []const u8,
    id: u32,
};

const SpecialMatch = struct { start: usize, len: usize, id: u32 };

pub const Tokenizer = struct {
    allocator: std.mem.Allocator,
    /// Byte-level-mapped token string -> id (e.g. "Ġcapital" -> 6722).
    vocab: std.StringHashMap(u32),
    /// Reverse of `vocab`: id -> byte-level-mapped token string. Values
    /// alias `vocab`'s keys (same allocation) — see `deinit`.
    id_to_token: std.AutoHashMap(u32, []const u8),
    /// "left\x00right" -> merge rank (lower = merges first), built from
    /// `model.merges`.
    merge_rank: std.StringHashMap(u32),
    /// `added_tokens` entries (special tokens like `<|im_start|>`), tried
    /// against raw text before BPE pre-tokenization.
    special_tokens: std.ArrayList(SpecialToken),
    /// id -> literal text for special tokens, for `decode`. Values alias
    /// `special_tokens[].text`.
    special_by_id: std.AutoHashMap(u32, []const u8),
    /// Backs every allocation above (vocab/merge-key strings, the maps'
    /// own bucket storage, special-token text). A real `tokenizer.json`
    /// has ~150k vocab entries and ~150k merges; routing each individual
    /// small string through the caller's allocator directly (e.g. a
    /// debug/testing allocator) turns into ~300k+ separate allocation
    /// calls and was measured to take tens of seconds. A single arena
    /// collapses that into a handful of chunk growths, and makes
    /// `deinit` a single call instead of iterate-and-free-each-key.
    ///
    /// Heap-allocated (not embedded by value) on purpose: `vocab` etc.
    /// store an `Allocator` derived from `arena.allocator()`, which
    /// captures the *address* of the arena. `initFromJson` returns
    /// `Tokenizer` by value, and an embedded `ArenaAllocator` would move
    /// to a new address on that copy while the maps' already-captured
    /// `Allocator.ptr` kept pointing at the old (now-dead) stack slot —
    /// silent corruption/leaks, not a compile error. A stable heap
    /// address sidesteps that regardless of how many times the
    /// `Tokenizer` value itself gets copied/moved afterward.
    arena: *std.heap.ArenaAllocator,

    /// Loads a full `tokenizer.json` file. `io` follows this codebase's
    /// existing convention (see `../../src/models/config.zig`) — pass
    /// `std.Io.Threaded.init(allocator, .{}).io()` or equivalent.
    pub fn initFromFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Tokenizer {
        const file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);

        var buf: [64 * 1024]u8 = undefined;
        var f_reader = file.reader(io, &buf);
        const content = try f_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(64 * 1024 * 1024));
        defer allocator.free(content);

        return initFromJson(allocator, content);
    }

    /// Core parsing logic, independent of file I/O — see `initFromFile`.
    pub fn initFromJson(allocator: std.mem.Allocator, json_bytes: []const u8) !Tokenizer {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
        defer parsed.deinit();
        const root = parsed.value;

        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer {
            arena.deinit();
            allocator.destroy(arena);
        }
        const perm = arena.allocator();

        var self = Tokenizer{
            .allocator = allocator,
            .vocab = std.StringHashMap(u32).init(perm),
            .id_to_token = std.AutoHashMap(u32, []const u8).init(perm),
            .merge_rank = std.StringHashMap(u32).init(perm),
            .special_tokens = .empty,
            .special_by_id = std.AutoHashMap(u32, []const u8).init(perm),
            .arena = arena,
        };

        const model = root.object.get("model") orelse return error.InvalidTokenizerJson;
        const vocab_obj = (model.object.get("vocab") orelse return error.InvalidTokenizerJson).object;

        var vit = vocab_obj.iterator();
        while (vit.next()) |entry| {
            const tok_str = try perm.dupe(u8, entry.key_ptr.*);
            const id: u32 = @intCast(entry.value_ptr.integer);
            try self.vocab.put(tok_str, id);
            try self.id_to_token.put(id, tok_str);
        }

        const merges_arr = (model.object.get("merges") orelse return error.InvalidTokenizerJson).array;
        for (merges_arr.items, 0..) |merge_val, rank| {
            var left: []const u8 = undefined;
            var right: []const u8 = undefined;
            switch (merge_val) {
                // Older tokenizers versions store merges as "left right"
                // strings; newer ones store [left, right] pairs. Support
                // both.
                .string => |s| {
                    const sp = std.mem.indexOfScalar(u8, s, ' ') orelse return error.InvalidTokenizerJson;
                    left = s[0..sp];
                    right = s[sp + 1 ..];
                },
                .array => |arr| {
                    left = arr.items[0].string;
                    right = arr.items[1].string;
                },
                else => return error.InvalidTokenizerJson,
            }
            const key = try std.mem.concat(perm, u8, &.{ left, "\x00", right });
            try self.merge_rank.put(key, @intCast(rank));
        }

        if (root.object.get("added_tokens")) |added| {
            for (added.array.items) |tok| {
                const content = try perm.dupe(u8, tok.object.get("content").?.string);
                const id: u32 = @intCast(tok.object.get("id").?.integer);
                try self.special_tokens.append(perm, .{ .text = content, .id = id });
                try self.special_by_id.put(id, content);
            }
        }

        return self;
    }

    pub fn deinit(self: *Tokenizer) void {
        self.arena.deinit();
        self.allocator.destroy(self.arena);
    }

    /// Encodes `text` into token ids. Special tokens (e.g. `<|im_start|>`)
    /// are matched literally and bypass BPE; everything else goes through
    /// the regex pre-tokenizer + byte-level BPE merge loop.
    pub fn encode(self: *const Tokenizer, allocator: std.mem.Allocator, text: []const u8) ![]u32 {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        var out: std.ArrayList(u32) = .empty;
        errdefer out.deinit(allocator);

        var pos: usize = 0;
        while (pos < text.len) {
            const found = self.findNextSpecial(text, pos);
            const seg_end = if (found) |f| f.start else text.len;
            if (seg_end > pos) {
                const chunks = try pretokenize(arena, text[pos..seg_end]);
                for (chunks) |chunk| {
                    try self.encodeChunk(arena, allocator, chunk, &out);
                }
            }
            if (found) |f| {
                try out.append(allocator, f.id);
                pos = f.start + f.len;
            } else {
                pos = seg_end;
            }
        }

        return out.toOwnedSlice(allocator);
    }

    /// Decodes token ids back to UTF-8 text. Special-token ids are
    /// emitted as their literal `content`; ordinary ids go through the
    /// byte-level reverse mapping.
    pub fn decode(self: *const Tokenizer, allocator: std.mem.Allocator, ids: []const u32) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        for (ids) |id| {
            if (self.special_by_id.get(id)) |txt| {
                try out.appendSlice(allocator, txt);
                continue;
            }
            const mapped = self.id_to_token.get(id) orelse return error.UnknownTokenId;
            const view = try std.unicode.Utf8View.init(mapped);
            var it = view.iterator();
            while (it.nextCodepoint()) |cp| {
                if (cp >= byte_decoder_table.len) return error.InvalidByteMapping;
                const b = byte_decoder_table[cp] orelse return error.InvalidByteMapping;
                try out.append(allocator, b);
            }
        }

        return out.toOwnedSlice(allocator);
    }

    fn findNextSpecial(self: *const Tokenizer, text: []const u8, pos: usize) ?SpecialMatch {
        var best: ?SpecialMatch = null;
        for (self.special_tokens.items) |st| {
            if (st.text.len == 0) continue;
            if (std.mem.indexOfPos(u8, text, pos, st.text)) |idx| {
                if (best == null or idx < best.?.start or (idx == best.?.start and st.text.len > best.?.len)) {
                    best = .{ .start = idx, .len = st.text.len, .id = st.id };
                }
            }
        }
        return best;
    }

    /// Byte-level-encodes then BPE-merges a single pre-tokenized chunk,
    /// appending resulting token ids to `out`.
    fn encodeChunk(self: *const Tokenizer, arena: std.mem.Allocator, out_allocator: std.mem.Allocator, chunk: []const u8, out: *std.ArrayList(u32)) !void {
        var symbols: std.ArrayList([]const u8) = .empty;
        for (chunk) |b| {
            const cp = byte_encoder[b];
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cp, &buf) catch unreachable;
            try symbols.append(arena, try arena.dupe(u8, buf[0..len]));
        }

        while (symbols.items.len > 1) {
            var best_rank: ?u32 = null;
            var best_idx: usize = 0;
            var idx: usize = 0;
            while (idx < symbols.items.len - 1) : (idx += 1) {
                if (self.lookupMergeRank(arena, symbols.items[idx], symbols.items[idx + 1])) |r| {
                    if (best_rank == null or r < best_rank.?) {
                        best_rank = r;
                        best_idx = idx;
                    }
                }
            }
            if (best_rank == null) break;
            const merged = try std.mem.concat(arena, u8, &.{ symbols.items[best_idx], symbols.items[best_idx + 1] });
            symbols.items[best_idx] = merged;
            _ = symbols.orderedRemove(best_idx + 1);
        }

        for (symbols.items) |sym| {
            const id = self.vocab.get(sym) orelse return error.UnknownToken;
            try out.append(out_allocator, id);
        }
    }

    fn lookupMergeRank(self: *const Tokenizer, arena: std.mem.Allocator, left: []const u8, right: []const u8) ?u32 {
        const key = std.mem.concat(arena, u8, &.{ left, "\x00", right }) catch return null;
        return self.merge_rank.get(key);
    }
};

// --- GPT-2 byte<->unicode remapping ------------------------------------

const byte_encoder: [256]u21 = computeByteEncoder();

fn computeByteEncoder() [256]u21 {
    @setEvalBranchQuota(10_000);
    var table: [256]u21 = undefined;
    var assigned: [256]bool = @splat(false);

    var b: usize = '!';
    while (b <= '~') : (b += 1) {
        table[b] = @intCast(b);
        assigned[b] = true;
    }
    b = 0xA1;
    while (b <= 0xAC) : (b += 1) {
        table[b] = @intCast(b);
        assigned[b] = true;
    }
    b = 0xAE;
    while (b <= 0xFF) : (b += 1) {
        table[b] = @intCast(b);
        assigned[b] = true;
    }

    var n: u21 = 0;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        if (!assigned[i]) {
            table[i] = 256 + n;
            n += 1;
        }
    }
    return table;
}

// Max codepoint produced by computeByteEncoder is 256 + 67 = 323, well
// under 512.
const byte_decoder_table: [512]?u8 = computeByteDecoder();

fn computeByteDecoder() [512]?u8 {
    @setEvalBranchQuota(10_000);
    var table: [512]?u8 = @splat(null);
    var b: usize = 0;
    while (b < 256) : (b += 1) {
        table[byte_encoder[b]] = @intCast(b);
    }
    return table;
}

// --- Pre-tokenizer regex, hand-rolled -----------------------------------
//
// Reimplements, as a scanning state machine over decoded codepoints:
//   (?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}|
//    ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+

const CpInfo = struct { cp: u21, start: usize };

fn isNewlineCp(cp: u21) bool {
    return cp == '\r' or cp == '\n';
}

/// `\s` minus `\r\n` (kept separate so callers can distinguish "plain
/// space-like" from "line break" the way the regex's rule ordering does).
fn isSpaceCp(cp: u21) bool {
    return switch (cp) {
        ' ', '\t', 0x0B, 0x0C, 0x85, 0xA0, 0x1680 => true,
        0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 => true,
        else => false,
    };
}

fn isWhitespaceFullCp(cp: u21) bool {
    return isSpaceCp(cp) or isNewlineCp(cp);
}

fn isDigitCp(cp: u21) bool {
    return cp >= '0' and cp <= '9';
}

/// Approximates common non-ASCII punctuation/symbol blocks that should
/// *not* count as `\p{L}` letters — see the file-level doc comment's
/// "Known limitation".
fn isPunctOrSymbolCp(cp: u21) bool {
    return switch (cp) {
        0x2000...0x206F => true, // general punctuation
        0x3000...0x303F => true, // CJK punctuation
        0xFF00...0xFF0F, 0xFF1A...0xFF20, 0xFF3B...0xFF40, 0xFF5B...0xFF65 => true, // fullwidth punctuation
        else => false,
    };
}

fn isLetterCp(cp: u21) bool {
    if (cp < 0x80) {
        return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z');
    }
    if (isWhitespaceFullCp(cp) or isDigitCp(cp) or isPunctOrSymbolCp(cp)) return false;
    return true;
}

fn toLowerCp(cp: u21) u21 {
    if (cp >= 'A' and cp <= 'Z') return cp + 32;
    return cp;
}

/// Tries to match one of `'s 't 're 've 'm 'll 'd` (case-insensitive)
/// starting at `cps[i]` (which must be `'`). Returns the index just past
/// the match, or null.
fn matchContraction(cps: []const CpInfo, i: usize, n: usize) ?usize {
    const suffixes = [_][]const u21{
        &[_]u21{'s'},
        &[_]u21{'t'},
        &[_]u21{ 'r', 'e' },
        &[_]u21{ 'v', 'e' },
        &[_]u21{'m'},
        &[_]u21{ 'l', 'l' },
        &[_]u21{'d'},
    };
    outer: for (suffixes) |suf| {
        if (i + 1 + suf.len > n) continue;
        for (suf, 0..) |c, k| {
            if (toLowerCp(cps[i + 1 + k].cp) != c) continue :outer;
        }
        return i + 1 + suf.len;
    }
    return null;
}

fn decodeCodepoints(arena: std.mem.Allocator, text: []const u8) ![]CpInfo {
    var list: std.ArrayList(CpInfo) = .empty;
    const view = try std.unicode.Utf8View.init(text);
    var it = view.iterator();
    while (it.nextCodepointSlice()) |slice| {
        const cp = std.unicode.utf8Decode(slice) catch unreachable;
        const start = @intFromPtr(slice.ptr) - @intFromPtr(text.ptr);
        try list.append(arena, .{ .cp = cp, .start = start });
    }
    // Sentinel: cp = 0 never matches any classifier above, so the main
    // loop can safely index one past the last real codepoint without
    // special-casing the end of input.
    try list.append(arena, .{ .cp = 0, .start = text.len });
    return list.toOwnedSlice(arena);
}

/// Splits `text` into pre-tokenized chunks (byte slices into `text`)
/// following the GPT-2/Qwen regex, described at the top of this section.
fn pretokenize(arena: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var chunks: std.ArrayList([]const u8) = .empty;
    if (text.len == 0) return chunks.toOwnedSlice(arena);

    const cps = try decodeCodepoints(arena, text);
    const n = cps.len - 1; // real codepoint count (sentinel excluded)

    var i: usize = 0;
    while (i < n) {
        const start_byte = cps[i].start;

        // Rule 1: contraction suffixes.
        if (cps[i].cp == '\'') {
            if (matchContraction(cps, i, n)) |end_idx| {
                try chunks.append(arena, text[start_byte..cps[end_idx].start]);
                i = end_idx;
                continue;
            }
        }

        // Rule 2: [^\r\n\p{L}\p{N}]? \p{L}+
        rule2: {
            var j = i;
            if (!isNewlineCp(cps[j].cp) and !isLetterCp(cps[j].cp) and !isDigitCp(cps[j].cp)) {
                if (isLetterCp(cps[j + 1].cp)) j += 1;
            }
            if (!isLetterCp(cps[j].cp)) break :rule2;
            while (isLetterCp(cps[j].cp)) : (j += 1) {}
            try chunks.append(arena, text[start_byte..cps[j].start]);
            i = j;
            continue;
        }

        // Rule 3: \p{N} (single digit per match — GPT-2's pattern has no
        // `+` here, so runs of digits become separate tokens).
        if (isDigitCp(cps[i].cp)) {
            try chunks.append(arena, text[start_byte..cps[i + 1].start]);
            i += 1;
            continue;
        }

        // Rule 4: ` ?[^\s\p{L}\p{N}]+[\r\n]*`
        rule4: {
            var j = i;
            if (cps[j].cp == ' ') {
                const next = cps[j + 1].cp;
                if (next != 0 and !isWhitespaceFullCp(next) and !isLetterCp(next) and !isDigitCp(next)) j += 1;
            }
            const sym_start = j;
            while (cps[j].cp != 0 and !isWhitespaceFullCp(cps[j].cp) and !isLetterCp(cps[j].cp) and !isDigitCp(cps[j].cp)) : (j += 1) {}
            if (j == sym_start) break :rule4;
            while (isNewlineCp(cps[j].cp)) : (j += 1) {}
            try chunks.append(arena, text[start_byte..cps[j].start]);
            i = j;
            continue;
        }

        // Rule 5: \s*[\r\n]+ — the longest whitespace run ending in a
        // newline, if the run contains one at all.
        rule5: {
            var k = i;
            while (isWhitespaceFullCp(cps[k].cp)) : (k += 1) {}
            if (k == i) break :rule5;
            var last_nl: ?usize = null;
            var m = i;
            while (m < k) : (m += 1) {
                if (isNewlineCp(cps[m].cp)) last_nl = m;
            }
            const ln = last_nl orelse break :rule5;
            const end = ln + 1;
            try chunks.append(arena, text[start_byte..cps[end].start]);
            i = end;
            continue;
        }

        // Rule 6/7: \s+(?!\S) merged with its \s+ fallback — a run of
        // (non-newline, already excluded by rule 5 above) whitespace
        // matches in full at end-of-input or when length 1, otherwise
        // holds back its last char so a following word's leading space
        // (rule 2/4's optional leading char) gets it instead.
        rule67: {
            var k = i;
            while (isSpaceCp(cps[k].cp)) : (k += 1) {}
            if (k == i) break :rule67;
            const end = if (k == n or (k - i) == 1) k else k - 1;
            try chunks.append(arena, text[start_byte..cps[end].start]);
            i = end;
            continue;
        }

        // Unreachable for well-formed Unicode input (every codepoint
        // classifies as newline/letter/digit/other-symbol/whitespace,
        // and each of those is handled by rules 1-7 above) — guarded
        // here only so malformed input can't spin forever instead of
        // erroring or misbehaving loudly.
        try chunks.append(arena, text[start_byte..cps[i + 1].start]);
        i += 1;
    }

    return chunks.toOwnedSlice(arena);
}

// --- Tests ---------------------------------------------------------------

const qwen25_tokenizer_json_path = "/Users/fource/.cache/huggingface/hub/models--mlx-community--Qwen2.5-0.5B-Instruct-4bit/snapshots/a5339a4131f135d0fdc6a5c8b5bbed2753bbe0f3/tokenizer.json";

fn loadQwenTokenizerForTest(allocator: std.mem.Allocator, io: std.Io) !?Tokenizer {
    return Tokenizer.initFromFile(allocator, io, qwen25_tokenizer_json_path) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
}

test "Tokenizer.encode matches the Python mlx_lm/tokenizers reference for \"The capital of France is\"" {
    const gpa = std.testing.allocator;
    var threaded_io = std.Io.Threaded.init(gpa, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    var tok = try loadQwenTokenizerForTest(gpa, io) orelse return error.SkipZigTest;
    defer tok.deinit();

    const ids = try tok.encode(gpa, "The capital of France is");
    defer gpa.free(ids);

    // QA oracle (Python `tokenizers`/mlx_lm against the real
    // mlx-community/Qwen2.5-0.5B-Instruct-4bit tokenizer.json):
    //   [785, 6722, 315, 9625, 374] -> The / Ġcapital / Ġof / ĠFrance / Ġis
    try std.testing.expectEqualSlices(u32, &[_]u32{ 785, 6722, 315, 9625, 374 }, ids);
}

test "Tokenizer.decode reproduces the reference 10-token greedy continuation" {
    const gpa = std.testing.allocator;
    var threaded_io = std.Io.Threaded.init(gpa, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    var tok = try loadQwenTokenizerForTest(gpa, io) orelse return error.SkipZigTest;
    defer tok.deinit();

    // QA oracle's 10-token greedy continuation ids, decoded to
    // " Paris. It is the largest city in the world".
    const ids = [_]u32{ 12095, 13, 1084, 374, 279, 7772, 3283, 304, 279, 1879 };
    const text = try tok.decode(gpa, &ids);
    defer gpa.free(text);

    try std.testing.expectEqualStrings(" Paris. It is the largest city in the world", text);
}

test "Tokenizer.encode round-trips through Tokenizer.decode for the full oracle prompt+continuation" {
    const gpa = std.testing.allocator;
    var threaded_io = std.Io.Threaded.init(gpa, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    var tok = try loadQwenTokenizerForTest(gpa, io) orelse return error.SkipZigTest;
    defer tok.deinit();

    const ids = try tok.encode(gpa, "The capital of France is");
    defer gpa.free(ids);
    const text = try tok.decode(gpa, ids);
    defer gpa.free(text);

    try std.testing.expectEqualStrings("The capital of France is", text);
}

test "Tokenizer: minimal synthetic vocab exercises BPE merge + byte-level round trip without the real model file" {
    const gpa = std.testing.allocator;

    // Byte-level base tokens for 'a' (U+0061) and 'b' (U+0062) are their
    // own bytes under the GPT-2 mapping (both fall in the '!'..'~'
    // printable range), plus one merge "a b" -> "ab".
    const synthetic_json =
        \\{
        \\  "added_tokens": [
        \\    {"id": 99, "content": "<|special|>", "single_word": false, "lstrip": false, "rstrip": false, "normalized": false, "special": true}
        \\  ],
        \\  "model": {
        \\    "type": "BPE",
        \\    "vocab": {"a": 0, "b": 1, "ab": 2},
        \\    "merges": ["a b"]
        \\  }
        \\}
    ;

    var tok = try Tokenizer.initFromJson(gpa, synthetic_json);
    defer tok.deinit();

    const ids = try tok.encode(gpa, "ab");
    defer gpa.free(ids);
    try std.testing.expectEqualSlices(u32, &[_]u32{2}, ids);

    const text = try tok.decode(gpa, ids);
    defer gpa.free(text);
    try std.testing.expectEqualStrings("ab", text);

    const with_special = try tok.encode(gpa, "ab<|special|>ab");
    defer gpa.free(with_special);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 99, 2 }, with_special);
}
