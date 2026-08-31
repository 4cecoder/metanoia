//! Native-Zig replacement for tools/interlinear_scraper.py and
//! tools/lexicon_scraper.py: fetches original-language (Greek/Hebrew) word
//! data and Strong's-number lexicon entries from BibleHub and caches them
//! into data/bible.db, without shelling out to Python (see scraper_client.zig).
//!
//! Design: HTML parsing is fully decoupled from network fetching (parseXHtml
//! functions take a `[]const u8` and never touch `std.Io`), so the parser can
//! be unit-tested against fixture strings with zero network access. Only
//! scrapeInterlinear/scrapeLexicon and fetchWithRetry touch the network.
//!
//! The BibleHub HTML structure below (tag names, CSS classes, nesting) was
//! captured 2026-07-19 by fetching real pages directly:
//!   curl -A "Mozilla/5.0" https://biblehub.com/interlinear/philemon/1.htm
//!   curl -A "Mozilla/5.0" https://biblehub.com/interlinear/obadiah/1.htm
//!   curl -A "Mozilla/5.0" https://biblehub.com/greek/3972.htm
//! rather than re-derived from tools/interlinear_scraper.py's intent alone —
//! see the "KNOWN BEHAVIORAL NOTE" comments below for two places where the
//! live site's markup has drifted from what that Python code's CSS-class
//! selectors actually match today (bugs this port deliberately *preserves*,
//! per the "replicate exact behavior" brief, rather than silently fixing).

const std = @import("std");
const bible = @import("bible_db.zig");

// ============================================================================
// Tiny hand-rolled HTML scanner
// ============================================================================
// BibleHub's interlinear/lexicon pages are not general HTML we need a real
// parser for -- we need to find specific tag+class elements and read their
// text, mirroring BeautifulSoup's `.find()`/`.find_all()` calls in the Python
// scrapers. This section is a byte-scanner for exactly that: tag/class
// matching with depth-aware close-tag matching (needed because BibleHub
// nests a plain <table> inside each Hebrew "tablefloatheb" word cell).

const Element = struct {
    /// Byte offset of the first byte after the start tag's '>'.
    content_start: usize,
    /// Byte offset of the '<' that begins the matching close tag (exclusive
    /// end of this element's inner content).
    content_end: usize,
    /// Byte offset of the first byte after the close tag's '>' -- where a
    /// caller doing find_all-style iteration should resume scanning from.
    tag_end: usize,
};

fn isTagNameBoundary(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '>' or c == '/';
}

fn tagNameMatchesAt(html: []const u8, idx: usize, tag: []const u8) bool {
    if (idx + tag.len > html.len) return false;
    if (!std.ascii.eqlIgnoreCase(html[idx .. idx + tag.len], tag)) return false;
    if (idx + tag.len == html.len) return true;
    return isTagNameBoundary(html[idx + tag.len]);
}

/// Extracts the value of `attr="..."` (or `attr='...'`) from a start-tag's
/// raw text, requiring `attr` to be preceded by whitespace/`<` (so `class=`
/// doesn't spuriously match on some hypothetical `dataclass=`).
fn extractAttr(tag_text: []const u8, attr: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, tag_text, i, attr)) |idx| {
        const boundary_ok = idx == 0 or tag_text[idx - 1] == ' ' or tag_text[idx - 1] == '\t' or
            tag_text[idx - 1] == '\n' or tag_text[idx - 1] == '\r' or tag_text[idx - 1] == '<';
        const after = idx + attr.len;
        if (boundary_ok and after < tag_text.len and tag_text[after] == '=') {
            const qpos = after + 1;
            if (qpos < tag_text.len and (tag_text[qpos] == '"' or tag_text[qpos] == '\'')) {
                const quote = tag_text[qpos];
                if (std.mem.indexOfScalarPos(u8, tag_text, qpos + 1, quote)) |endq| {
                    return tag_text[qpos + 1 .. endq];
                }
                return null;
            }
        }
        i = idx + attr.len;
    }
    return null;
}

fn hasAnyClass(start_tag: []const u8, classes: []const []const u8) bool {
    if (classes.len == 0) return true;
    const val = extractAttr(start_tag, "class") orelse return false;
    var it = std.mem.tokenizeAny(u8, val, " \t\n\r");
    while (it.next()) |tok| {
        for (classes) |c| {
            if (std.mem.eql(u8, tok, c)) return true;
        }
    }
    return false;
}

fn hasIdEqual(start_tag: []const u8, id: []const u8) bool {
    const val = extractAttr(start_tag, "id") orelse return false;
    return std.mem.eql(u8, val, id);
}

/// Depth-counts nested same-named tags starting right after a start tag's
/// '>' (`from`), returning the index of the matching close tag's '<'.
fn findMatchingClose(html: []const u8, from: usize, tag: []const u8) ?usize {
    var depth: usize = 1;
    var i = from;
    while (i < html.len) {
        const lt = std.mem.indexOfScalarPos(u8, html, i, '<') orelse return null;
        if (lt + 1 < html.len and html[lt + 1] == '/') {
            if (tagNameMatchesAt(html, lt + 2, tag)) {
                depth -= 1;
                if (depth == 0) return lt;
            }
            const gt = std.mem.indexOfScalarPos(u8, html, lt, '>') orelse return null;
            i = gt + 1;
            continue;
        }
        if (tagNameMatchesAt(html, lt + 1, tag)) {
            const gt = std.mem.indexOfScalarPos(u8, html, lt, '>') orelse return null;
            const self_closing = gt > lt and html[gt - 1] == '/';
            if (!self_closing) depth += 1;
            i = gt + 1;
            continue;
        }
        i = lt + 1;
    }
    return null;
}

/// Finds the next `<tag ...>` at or after `from` whose class attribute
/// contains one of `classes` as a whitespace-delimited token (an empty
/// `classes` slice matches any element of that tag, used to mirror
/// BeautifulSoup's plain `.find("a")`). Mirrors `.find()`: first match only.
fn findElement(html: []const u8, from: usize, tag: []const u8, classes: []const []const u8) ?Element {
    var i = from;
    while (i < html.len) {
        const lt = std.mem.indexOfScalarPos(u8, html, i, '<') orelse return null;
        if (lt + 1 >= html.len or html[lt + 1] == '/' or !tagNameMatchesAt(html, lt + 1, tag)) {
            i = lt + 1;
            continue;
        }
        const gt = std.mem.indexOfScalarPos(u8, html, lt, '>') orelse return null;
        const start_tag = html[lt .. gt + 1];
        if (!hasAnyClass(start_tag, classes)) {
            i = gt + 1;
            continue;
        }
        const self_closing = gt > lt and html[gt - 1] == '/';
        if (self_closing) return .{ .content_start = gt + 1, .content_end = gt + 1, .tag_end = gt + 1 };
        const close_lt = findMatchingClose(html, gt + 1, tag) orelse return null;
        const close_gt = std.mem.indexOfScalarPos(u8, html, close_lt, '>') orelse return null;
        return .{ .content_start = gt + 1, .content_end = close_lt, .tag_end = close_gt + 1 };
    }
    return null;
}

/// Like `findElement` but matches on an exact `id="..."` instead of a class
/// token, for `soup.find("div", id="leftbox")`.
fn findElementById(html: []const u8, from: usize, tag: []const u8, id: []const u8) ?Element {
    var i = from;
    while (i < html.len) {
        const lt = std.mem.indexOfScalarPos(u8, html, i, '<') orelse return null;
        if (lt + 1 >= html.len or html[lt + 1] == '/' or !tagNameMatchesAt(html, lt + 1, tag)) {
            i = lt + 1;
            continue;
        }
        const gt = std.mem.indexOfScalarPos(u8, html, lt, '>') orelse return null;
        const start_tag = html[lt .. gt + 1];
        if (!hasIdEqual(start_tag, id)) {
            i = gt + 1;
            continue;
        }
        const self_closing = gt > lt and html[gt - 1] == '/';
        if (self_closing) return .{ .content_start = gt + 1, .content_end = gt + 1, .tag_end = gt + 1 };
        const close_lt = findMatchingClose(html, gt + 1, tag) orelse return null;
        const close_gt = std.mem.indexOfScalarPos(u8, html, close_lt, '>') orelse return null;
        return .{ .content_start = gt + 1, .content_end = close_lt, .tag_end = close_gt + 1 };
    }
    return null;
}

/// True if `frag` contains an `<a href="...">` whose href contains `needle`
/// as a substring -- mirrors Python's `ms.find("a", href=re.compile(needle))`.
fn fragmentHasHrefContaining(frag: []const u8, needle: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, frag, i, "<a")) |lt| {
        if (lt + 2 >= frag.len or !isTagNameBoundary(frag[lt + 2])) {
            i = lt + 2;
            continue;
        }
        const gt = std.mem.indexOfScalarPos(u8, frag, lt, '>') orelse return false;
        const start_tag = frag[lt .. gt + 1];
        if (extractAttr(start_tag, "href")) |href| {
            if (std.mem.indexOf(u8, href, needle) != null) return true;
        }
        i = gt + 1;
    }
    return false;
}

// --- Text extraction: tag-stripping + entity decoding + Python-style strip -

fn decodeOneEntity(ent: []const u8) ?u21 {
    if (ent.len == 0) return null;
    if (ent[0] == '#') {
        if (ent.len > 1 and (ent[1] == 'x' or ent[1] == 'X')) {
            return std.fmt.parseInt(u21, ent[2..], 16) catch null;
        }
        return std.fmt.parseInt(u21, ent[1..], 10) catch null;
    }
    if (std.mem.eql(u8, ent, "nbsp")) return 0x00A0;
    if (std.mem.eql(u8, ent, "amp")) return '&';
    if (std.mem.eql(u8, ent, "lt")) return '<';
    if (std.mem.eql(u8, ent, "gt")) return '>';
    if (std.mem.eql(u8, ent, "quot")) return '"';
    if (std.mem.eql(u8, ent, "apos")) return '\'';
    return null;
}

fn decodeEntities(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (std.mem.indexOfScalarPos(u8, s, i, ';')) |semi| {
                if (decodeOneEntity(s[i + 1 .. semi])) |cp| {
                    var buf: [4]u8 = undefined;
                    if (std.unicode.utf8Encode(cp, &buf)) |n| {
                        try out.appendSlice(allocator, buf[0..n]);
                        i = semi + 1;
                        continue;
                    } else |_| {}
                }
            }
        }
        try out.append(allocator, s[i]);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

/// Width (in bytes) of a single Python-whitespace unit starting at `s[i]`, or
/// 0 if `s[i]` isn't whitespace. Python's `str.strip()`/`str.split()` treat
/// U+00A0 (NBSP, `&nbsp;`'s decoded form) as whitespace, unlike ASCII-only
/// trimming -- this matters because BibleHub's `eng` spans join words with
/// `&nbsp;` instead of a plain space (confirmed against data/bible.db: stored
/// translations contain literal U+00A0 between words, e.g. "In\xa0the\xa0beginning").
fn pyWsWidthAt(s: []const u8, i: usize) usize {
    const c = s[i];
    if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0B or c == 0x0C) return 1;
    if (c == 0xC2 and i + 1 < s.len and s[i + 1] == 0xA0) return 2;
    return 0;
}

fn trimPy(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var start: usize = 0;
    while (start < s.len) {
        const w = pyWsWidthAt(s, start);
        if (w == 0) break;
        start += w;
    }
    var end: usize = s.len;
    while (end > start) {
        if (end - start >= 1 and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\n' or s[end - 1] == '\r' or s[end - 1] == 0x0B or s[end - 1] == 0x0C)) {
            end -= 1;
            continue;
        }
        if (end - start >= 2 and s[end - 2] == 0xC2 and s[end - 1] == 0xA0) {
            end -= 2;
            continue;
        }
        break;
    }
    return allocator.dupe(u8, s[start..end]);
}

/// Mirrors BeautifulSoup's `element.get_text().strip()`: strips all tags from
/// `fragment`, decodes HTML entities, and trims Python-whitespace from both
/// ends. Caller owns the returned slice.
fn extractText(allocator: std.mem.Allocator, fragment: []const u8) ![]u8 {
    var stripped = std.ArrayListUnmanaged(u8).empty;
    defer stripped.deinit(allocator);
    var i: usize = 0;
    while (i < fragment.len) {
        if (fragment[i] == '<') {
            const gt = std.mem.indexOfScalarPos(u8, fragment, i, '>') orelse {
                break;
            };
            i = gt + 1;
            continue;
        }
        try stripped.append(allocator, fragment[i]);
        i += 1;
    }
    const decoded = try decodeEntities(allocator, stripped.items);
    defer allocator.free(decoded);
    return trimPy(allocator, decoded);
}

fn digitsOnly(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    for (s) |c| {
        if (c >= '0' and c <= '9') try out.append(allocator, c);
    }
    return out.toOwnedSlice(allocator);
}

// ============================================================================
// tools/bible_books.json -> language prefix (H/G)
// ============================================================================

/// Old Testament -> Hebrew ("H"), everything else (New/EthiopiaExpanded, or
/// a book absent from the list entirely) -> Greek ("G"). Mirrors
/// tools/interlinear_scraper.py's language_prefix() exactly, including its
/// "unknown book defaults to Greek" fallback (`testament_map.get(book)`
/// returning `None` on a dict miss).
pub fn languagePrefix(allocator: std.mem.Allocator, io: std.Io, book: []const u8) !u8 {
    const contents = try std.Io.Dir.cwd().readFileAlloc(io, "tools/bible_books.json", allocator, std.Io.Limit.limited(1024 * 1024));
    defer allocator.free(contents);

    // tools/bible_books.json also carries a `canon` field (see
    // bible_db.zig's Canon doc comment) this function doesn't need --
    // ignore_unknown_fields so adding fields to the JSON for other
    // consumers doesn't break this parse.
    const Entry = struct { name: []const u8, testament: bible.Testament };
    const parsed = try std.json.parseFromSlice([]const Entry, allocator, contents, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    for (parsed.value) |entry| {
        if (std.mem.eql(u8, entry.name, book)) {
            return if (entry.testament == .Old) 'H' else 'G';
        }
    }
    return 'G';
}

// ============================================================================
// Interlinear parsing (parseInterlinearHtml) -- no network, pure function
// ============================================================================

pub const InterlinearWord = struct {
    verse: i32,
    word_index: i32,
    original_text: []const u8,
    translation: []const u8,
    strongs: []const u8,
    morphology: []const u8,

    fn free(self: InterlinearWord, allocator: std.mem.Allocator) void {
        allocator.free(self.original_text);
        allocator.free(self.translation);
        allocator.free(self.strongs);
        allocator.free(self.morphology);
    }
};

fn freeWords(allocator: std.mem.Allocator, words: []const InterlinearWord) void {
    for (words) |w| w.free(allocator);
    allocator.free(words);
}

fn parseStrongsSpan(allocator: std.mem.Allocator, table_html: []const u8, prefix: u8) ![]u8 {
    // KNOWN BEHAVIORAL NOTE (preserved from tools/interlinear_scraper.py):
    // this looks for `class="pos"` or `class="strongs"`. On today's live
    // BibleHub markup that only ever matches on Greek word tables -- Hebrew
    // ("tablefloatheb") word tables use `class="strongsnt"` for the same
    // purpose instead (see the docstring at the top of this file for the
    // real pages this was checked against). The Python scraper has this
    // exact same class list, so it has the exact same gap on today's site:
    // Hebrew/OT strongs numbers come back empty. Ported faithfully, not fixed.
    const s_span = findElement(table_html, 0, "span", &.{ "pos", "strongs" }) orelse return allocator.dupe(u8, "");
    const frag = table_html[s_span.content_start..s_span.content_end];

    const raw = raw: {
        if (findElement(frag, 0, "a", &.{})) |a_el| {
            break :raw try extractText(allocator, frag[a_el.content_start..a_el.content_end]);
        }
        break :raw try extractText(allocator, frag);
    };
    defer allocator.free(raw);

    if (raw.len > 0 and (raw[0] == 'G' or raw[0] == 'H')) {
        return allocator.dupe(u8, raw);
    }
    const digits = try digitsOnly(allocator, raw);
    defer allocator.free(digits);
    return std.fmt.allocPrint(allocator, "{c}{s}", .{ prefix, digits });
}

fn parseMorphSpans(allocator: std.mem.Allocator, table_html: []const u8) ![]u8 {
    // KNOWN BEHAVIORAL NOTE (preserved from tools/interlinear_scraper.py):
    // looks for the first `class="strongsnt2"`/`class="strongsnt"` span whose
    // `<a>` href contains "/grammar/". On today's live site Greek morphology
    // links do (`/grammar/n-nms.htm`), but Hebrew ones link to
    // `/hebrewparse.htm` instead -- so, like parseStrongsSpan above, Hebrew
    // morphology also comes back empty today. Same gap as the Python source.
    var pos: usize = 0;
    while (findElement(table_html, pos, "span", &.{ "strongsnt2", "strongsnt" })) |el| {
        pos = el.tag_end;
        const frag = table_html[el.content_start..el.content_end];
        if (fragmentHasHrefContaining(frag, "/grammar/")) {
            return extractText(allocator, frag);
        }
    }
    return allocator.dupe(u8, "");
}

/// Parses one BibleHub interlinear chapter page into per-word rows, mirroring
/// tools/interlinear_scraper.py's scrape_interlinear() loop body exactly
/// (same table/span classes, same verse-number-reset/word-index bookkeeping).
/// Pure function: does not touch the network or the database. Caller owns
/// the returned slice (see freeWords).
pub fn parseInterlinearHtml(allocator: std.mem.Allocator, html: []const u8, prefix: u8) ![]InterlinearWord {
    var out = std.ArrayListUnmanaged(InterlinearWord).empty;
    errdefer freeWords(allocator, out.toOwnedSlice(allocator) catch &.{});

    var current_verse: i32 = 0;
    var verse_word_index: i32 = 0;
    var pos: usize = 0;

    while (findElement(html, pos, "table", &.{ "tablefloat", "tablefloatheb" })) |tbl| {
        pos = tbl.tag_end;
        const table_html = html[tbl.content_start..tbl.content_end];

        if (findElement(table_html, 0, "span", &.{ "reftop3", "reftop" })) |vs| {
            const vtext = try extractText(allocator, table_html[vs.content_start..vs.content_end]);
            defer allocator.free(vtext);
            const digits = try digitsOnly(allocator, vtext);
            defer allocator.free(digits);
            if (digits.len > 0) {
                const new_v = std.fmt.parseInt(i32, digits, 10) catch current_verse;
                if (new_v != current_verse) {
                    current_verse = new_v;
                    verse_word_index = 0;
                }
            }
        }

        if (current_verse == 0) continue;

        const orig_el = findElement(table_html, 0, "span", &.{ "greek", "heb", "hebrew" }) orelse continue;
        const original_text = try extractText(allocator, table_html[orig_el.content_start..orig_el.content_end]);
        errdefer allocator.free(original_text);

        const strongs = try parseStrongsSpan(allocator, table_html, prefix);
        errdefer allocator.free(strongs);

        var translation: []u8 = undefined;
        if (findElement(table_html, 0, "span", &.{"eng"})) |eng_el| {
            translation = try extractText(allocator, table_html[eng_el.content_start..eng_el.content_end]);
        } else {
            translation = try allocator.dupe(u8, "");
        }
        errdefer allocator.free(translation);

        const morphology = try parseMorphSpans(allocator, table_html);

        try out.append(allocator, .{
            .verse = current_verse,
            .word_index = verse_word_index,
            .original_text = original_text,
            .translation = translation,
            .strongs = strongs,
            .morphology = morphology,
        });
        verse_word_index += 1;
    }

    return out.toOwnedSlice(allocator);
}

// ============================================================================
// Lexicon parsing (parseLexiconHtml) -- no network, pure function
// ============================================================================

pub const LexiconFields = struct {
    lemma: []const u8,
    transliteration: []const u8,
    definition: []const u8,
    usage: []const u8,

    fn free(self: LexiconFields, allocator: std.mem.Allocator) void {
        allocator.free(self.lemma);
        allocator.free(self.transliteration);
        allocator.free(self.definition);
        allocator.free(self.usage);
    }
};

fn firstNWordsJoined(allocator: std.mem.Allocator, text: []const u8, n: usize) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    var count: usize = 0;
    var i: usize = 0;
    while (i < text.len and count < n) {
        while (i < text.len) {
            const w = pyWsWidthAt(text, i);
            if (w == 0) break;
            i += w;
        }
        if (i >= text.len) break;
        const word_start = i;
        while (i < text.len and pyWsWidthAt(text, i) == 0) i += 1;
        if (count > 0) try out.append(allocator, ' ');
        try out.appendSlice(allocator, text[word_start..i]);
        count += 1;
    }
    return out.toOwnedSlice(allocator);
}

/// Parses one BibleHub Strong's-number page, mirroring
/// tools/lexicon_scraper.py's scrape_strongs() extraction exactly.
///
/// KNOWN BEHAVIORAL NOTE (preserved from tools/lexicon_scraper.py, and
/// confirmed against data/bible.db, where all 6190 existing lexicon rows
/// already have empty lemma/transliteration/definition/usage): `lemma`,
/// `transliteration`, and `usage` are *never* populated by this function --
/// the Python source only ever leaves them as "". `definition` is populated
/// only if the page has a `<div class="strongs">` (gates a leftbox summary
/// fallback) or a `<div class="strongsnt">` (used verbatim if present).
/// Real BibleHub `/greek/N.htm` and `/hebrew/N.htm` pages fetched
/// 2026-07-19 have neither element (confirmed via
/// `curl -A "Mozilla/5.0" https://biblehub.com/greek/3972.htm`) -- only a
/// `<div id="leftbox">`, which the "strongs" gate never opens -- so
/// `definition` also comes back "" on every real page today. This makes the
/// lexicon scraper (Python original and this port alike) currently cache
/// essentially-empty rows against the live site; ported faithfully rather
/// than "fixed", since silently changing the extracted fields would be a
/// bigger behavioral deviation than preserving a documented no-op.
pub fn parseLexiconHtml(allocator: std.mem.Allocator, html: []const u8) !LexiconFields {
    var definition: []u8 = try allocator.dupe(u8, "");
    errdefer allocator.free(definition);

    if (findElement(html, 0, "div", &.{"strongs"}) != null) {
        if (findElementById(html, 0, "div", "leftbox")) |lb| {
            const text = try extractText(allocator, html[lb.content_start..lb.content_end]);
            defer allocator.free(text);
            const words = try firstNWordsJoined(allocator, text, 100);
            allocator.free(definition);
            definition = words;
        }
    }
    if (findElement(html, 0, "div", &.{"strongsnt"})) |ds| {
        const text = try extractText(allocator, html[ds.content_start..ds.content_end]);
        allocator.free(definition);
        definition = text;
    }

    return .{
        .lemma = try allocator.dupe(u8, ""),
        .transliteration = try allocator.dupe(u8, ""),
        .definition = definition,
        .usage = try allocator.dupe(u8, ""),
    };
}

// ============================================================================
// HTTP fetch + retry-with-backoff (mirrors tools/scraper_common.py exactly)
// ============================================================================

pub const HttpResponse = struct {
    status: u16,
    body: []u8,
};

const FetchTaskResult = union(enum) {
    ok: HttpResponse,
    err: anyerror,
};

const RaceResult = union(enum) {
    fetch: FetchTaskResult,
    timed_out: void,
};

fn doFetchOnce(io: std.Io, allocator: std.mem.Allocator, url: []const u8) FetchTaskResult {
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &aw.writer,
        .extra_headers = &.{.{ .name = "User-Agent", .value = "Mozilla/5.0" }},
    }) catch |err| return .{ .err = err };

    const body = allocator.dupe(u8, aw.writer.buffer[0..aw.writer.end]) catch |err| return .{ .err = err };
    return .{ .ok = .{ .status = @intFromEnum(result.status), .body = body } };
}

fn sleepIgnoringCancel(io: std.Io, nanoseconds: i96) void {
    io.sleep(.{ .nanoseconds = nanoseconds }, .awake) catch {};
}

/// Performs one GET with a real wall-clock timeout, racing the fetch against
/// a timer via `Io.Select` and canceling whichever loses -- the closest
/// native-Zig equivalent of `requests.get(url, timeout=...)`, which
/// tools/scraper_common.py relies on for its 15s-per-attempt timeout.
fn httpGetOnce(io: std.Io, allocator: std.mem.Allocator, url: []const u8, timeout_ns: i96) !HttpResponse {
    var buf: [2]RaceResult = undefined;
    var select = std.Io.Select(RaceResult).init(io, &buf);

    select.async(.fetch, doFetchOnce, .{ io, allocator, url });
    select.async(.timed_out, sleepIgnoringCancel, .{ io, timeout_ns });

    const result = select.await() catch |err| {
        discardLeftover(allocator, select.cancel());
        return err;
    };
    discardLeftover(allocator, select.cancel());

    return switch (result) {
        .fetch => |fr| switch (fr) {
            .ok => |r| r,
            .err => |e| e,
        },
        .timed_out => error.Timeout,
    };
}

fn discardLeftover(allocator: std.mem.Allocator, leftover: ?RaceResult) void {
    const r = leftover orelse return;
    switch (r) {
        .fetch => |fr| switch (fr) {
            .ok => |resp| allocator.free(resp.body),
            .err => {},
        },
        .timed_out => {},
    }
}

pub const RetryConfig = struct {
    /// Matches fetch_with_retry(url, headers=headers, timeout=15) -- both
    /// tools/interlinear_scraper.py and tools/lexicon_scraper.py call it with
    /// the (also-default) attempts=3, backoff=1.0.
    attempts: u32 = 3,
    initial_backoff_ns: i96 = std.time.ns_per_s,
    timeout_ns: i96 = 15 * std.time.ns_per_s,
};

fn isTransientStatus(status: u16) bool {
    return switch (status) {
        500, 502, 503, 504 => true,
        else => false,
    };
}

/// A local approximation of Python's `except (requests.Timeout,
/// requests.ConnectionError)` retry gate: everything is treated as transient
/// (worth retrying) *except* the handful of errors that mean "this request
/// can never succeed regardless of the network" -- the Zig-error-set analog
/// of `requests.exceptions.InvalidURL`, which fetch_with_retry deliberately
/// does not catch and therefore does not retry either.
fn isPermanentFetchError(err: anyerror) bool {
    return switch (err) {
        error.UnsupportedUriScheme, error.UriMissingHost, error.InvalidHostName => true,
        else => false,
    };
}

/// GET `url`, retrying on transient failures with exponential backoff.
/// Mirrors tools/scraper_common.py's fetch_with_retry():
///   - retries (up to `config.attempts` tries, sleeping backoff, backoff*2, ...)
///     on timeout, connection failure, or HTTP 5xx
///   - does NOT retry HTTP 4xx (returned immediately on the first attempt)
///   - returns the last response even if the final attempt is still 5xx
///   - returns the last transient error if every attempt fails with one
pub fn fetchWithRetry(io: std.Io, allocator: std.mem.Allocator, url: []const u8, config: RetryConfig) !HttpResponse {
    var delay_ns = config.initial_backoff_ns;
    var attempt: u32 = 1;
    while (true) : (attempt += 1) {
        if (httpGetOnce(io, allocator, url, config.timeout_ns)) |resp| {
            if (isTransientStatus(resp.status) and attempt < config.attempts) {
                allocator.free(resp.body);
                sleepIgnoringCancel(io, delay_ns);
                delay_ns *= 2;
                continue;
            }
            return resp;
        } else |err| {
            if (isPermanentFetchError(err) or attempt >= config.attempts) return err;
            sleepIgnoringCancel(io, delay_ns);
            delay_ns *= 2;
            continue;
        }
    }
}

// ============================================================================
// Orchestration: scrapeInterlinear / scrapeLexicon
// ============================================================================

pub const ScraperError = error{HttpStatus};

fn lowercaseNoSpaces(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = try std.ArrayListUnmanaged(u8).initCapacity(allocator, s.len);
    errdefer out.deinit(allocator);
    for (s) |c| {
        if (c == ' ') continue;
        out.appendAssumeCapacity(std.ascii.toLower(c));
    }
    return out.toOwnedSlice(allocator);
}

/// Fetches https://biblehub.com/interlinear/{book}/{chapter}.htm and caches
/// every word's original text/translation/strongs/morphology into the
/// `interlinear` table. Mirrors tools/interlinear_scraper.py's
/// scrape_interlinear(book, chapter) end to end (URL construction, H/G
/// prefix via tools/bible_books.json, parsing, INSERT OR REPLACE shape).
pub fn scrapeInterlinear(io: std.Io, allocator: std.mem.Allocator, db: *bible.sqlite3, book: []const u8, chapter: i32) !void {
    const prefix = try languagePrefix(allocator, io, book);

    const book_url = try lowercaseNoSpaces(allocator, book);
    defer allocator.free(book_url);
    const url = try std.fmt.allocPrint(allocator, "https://biblehub.com/interlinear/{s}/{d}.htm", .{ book_url, chapter });
    defer allocator.free(url);

    const resp = try fetchWithRetry(io, allocator, url, .{});
    defer allocator.free(resp.body);
    // Mirrors response.raise_for_status() in the Python source, which turns
    // any non-2xx status into an exception the caller (llm_engine.zig) is
    // already set up to report as "Interlinear fetch failed" (see
    // scraper.scrape_interlinear's call site).
    if (resp.status < 200 or resp.status >= 300) return ScraperError.HttpStatus;

    const words = try parseInterlinearHtml(allocator, resp.body, prefix);
    defer freeWords(allocator, words);

    // This always hits the standard (non-apostolic) interlinear template,
    // so the language prefix fully determines the source: Hebrew pages are
    // Masoretic OT, Greek pages are New Testament. The Septuagint (LXX) is
    // only scraped via tools/bible/cache_lxx_interlinear.py's Python path
    // today (a different URL template — see interlinear_scraper.py).
    const source: []const u8 = if (prefix == 'H') "MT" else "GNT";
    for (words) |w| {
        bible.insert_interlinear_word(db, book, chapter, w.verse, w.word_index, w.original_text, w.translation, w.strongs, w.morphology, source);
    }
}

fn fetchLexiconEntry(io: std.Io, allocator: std.mem.Allocator, num: []const u8, language: []const u8) !?LexiconFields {
    const url = try std.fmt.allocPrint(allocator, "https://biblehub.com/{s}/{s}.htm", .{ language, num });
    defer allocator.free(url);

    // Mirrors scrape_strongs()'s `except requests.RequestException: return
    // None` -- a fully-exhausted-retry network failure just means "no
    // lexicon data for this Strong's number today", not an error that should
    // abort the whole backfill pass.
    const resp = fetchWithRetry(io, allocator, url, .{}) catch return null;
    defer allocator.free(resp.body);
    if (resp.status != 200) return null;

    return try parseLexiconHtml(allocator, resp.body);
}

fn strongsLessThan(_: void, a: []const u8, b: []const u8) bool {
    // (0 if x.startswith('G') else 1, x) -- Greek entries first, then
    // lexicographic within each language group, matching
    // cache_lexicon_from_db's sort key exactly.
    const ga = a.len > 0 and a[0] == 'G';
    const gb = b.len > 0 and b[0] == 'G';
    if (ga != gb) return ga;
    return std.mem.lessThan(u8, a, b);
}

/// Backfills the `lexicon` table with Strong's-number entries referenced by
/// the `interlinear` table but not yet cached. With `book`/`chapter` null,
/// scans the whole interlinear table; with both given, scopes the scan to
/// that chapter's Strong's numbers. Mirrors tools/lexicon_scraper.py's
/// cache_lexicon_from_db(book, chapter) exactly, including the 1s
/// "respectful delay" between successive *new* fetches and the
/// Greek-then-Hebrew sort order.
pub fn scrapeLexicon(io: std.Io, allocator: std.mem.Allocator, db: *bible.sqlite3, book: ?[]const u8, chapter: ?i32) !void {
    const strongs_list = try bible.distinct_interlinear_strongs(allocator, db, book, chapter);
    defer {
        for (strongs_list) |s| allocator.free(s);
        allocator.free(strongs_list);
    }

    const sorted = try allocator.dupe([]const u8, strongs_list);
    defer allocator.free(sorted);
    std.mem.sort([]const u8, sorted, {}, strongsLessThan);

    for (sorted) |s| {
        if (bible.lexicon_has_strongs(db, s)) continue;

        const language: []const u8 = if (s.len > 0 and s[0] == 'G') "greek" else "hebrew";
        const digits = try digitsOnly(allocator, s);
        defer allocator.free(digits);

        const entry = try fetchLexiconEntry(io, allocator, digits, language) orelse continue;
        defer entry.free(allocator);

        const canonical_strongs = try std.fmt.allocPrint(allocator, "{s}{s}", .{ if (std.mem.eql(u8, language, "greek")) "G" else "H", digits });
        defer allocator.free(canonical_strongs);

        bible.insert_lexicon_entry(db, canonical_strongs, language, entry.lemma, entry.transliteration, entry.definition, entry.usage);
        sleepIgnoringCancel(io, std.time.ns_per_s);
    }
}

// ============================================================================
// Tests
// ============================================================================

fn testIo() struct { threaded: std.Io.Threaded, io: std.Io } {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    return .{ .threaded = threaded, .io = threaded.io() };
}

// --- Fixture HTML -----------------------------------------------------------
// Trimmed down from the real pages captured 2026-07-19 (see file-level
// docstring for the exact `curl` commands), keeping every class name, tag
// nesting level (including the nested plain <table> inside the Hebrew word
// cell), and entity-encoding quirk that the parser depends on.

const greek_fixture =
    \\<div class="chap">Philemon 1</div>
    \\<table border="0" cellspacing="0" cellpadding="0"><tr><td>
    \\<table class="tablefloat"><tr><td height="160" valign="middle" align="left">
    \\<span class="reftop3">1&nbsp;&nbsp;&nbsp;</span>
    \\<span class="pos"><a href="/greek/3972.htm" title="Strong's Greek 3972: Paul">3972</a></span>&nbsp;
    \\<span class="strongsnt"><a href="/greek/strongs_3972.htm" title="Englishman's Greek Concordance">[e]</a></span><br>
    \\<span class="translit"><a href="/greek/paulos_3972.htm" title="Paulos: Paul">Paulos</a></span><br>
    \\<span class="refmain">1&nbsp;&nbsp;&nbsp;</span><span class="greek">Παῦλος</span><span class="punct">&nbsp;&nbsp;,</span><br>
    \\<span class="refbot">1&nbsp;&nbsp;&nbsp;</span><span class="eng">Paul</span><br>
    \\<span class="reftop2">1&nbsp;&nbsp;&nbsp;</span><span class="strongsnt"><a href="/grammar/n-nms.htm" title="Noun - Nominative Masculine Singular">N-NMS</a></span>
    \\</td></tr></table>
    \\<table class="tablefloat"><tr><td height="160" valign="middle" align="left">
    \\<span class="pos"><a href="/greek/1198.htm" title="Strong's Greek 1198: prisoner">1198</a></span>&nbsp;
    \\<span class="strongsnt"><a href="/greek/strongs_1198.htm" title="Englishman's Greek Concordance">[e]</a></span><br>
    \\<span class="translit"><a href="/greek/desmios_1198.htm" title="desmios: prisoner">desmios</a></span><br>
    \\<span class="greek">δέσμιος</span><br>
    \\<span class="eng">a&nbsp;prisoner</span><br>
    \\<span class="strongsnt"><a href="/grammar/n-nms.htm" title="Noun - Nominative Masculine Singular">N-NMS</a></span>
    \\</td></tr></table>
    \\</td></tr></table>
;

const hebrew_fixture =
    \\<p class="hdg">The Destruction of Edom</p>
    \\<table class="tablefloatheb"><tbody><tr><td height="165" valign="middle" align="right">
    \\<span class="strongsnt"><a href="/hebrew/2377.htm" title="Strong's Hebrew 2377: The vision">2377</a></span>&nbsp;</span>
    \\<span class="strongsnt"><a href="/hebrew/strongs_2377.htm" title="Englishman's Hebrew Concordance">[e]</a></span>
    \\<span class="reftop">&nbsp;&nbsp;&nbsp;1</span><br>
    \\<span class="translit"><a href="/hebrew/chazon_2377.htm" title="chazown">chazown</a></span><span class="reftrans">&nbsp;&nbsp;&nbsp;1</span><br>
    \\<table cellpadding="0" cellspacing="0" align="right"><tr><td width="99%" align="right">
    \\<span class="hebrew">&#1495;&#1458;&#1494;&#1430;&#1493;&#1465;&#1503;</span></td><td width="1"><span class="refheb">&nbsp;&nbsp;&nbsp;1</span><br></td></tr>
    \\<tr><td colspan="2" align="right"><span class="eng">The&nbsp;vision</span><span class="refbot">&nbsp;&nbsp;&nbsp;1</span><br>
    \\<span class="strongsnt"><a href="/hebrewparse.htm" title="Noun - masculine singular construct">N&#8209;msc</a></span><span class="reftop2">&nbsp;&nbsp;&nbsp;1</span></td></tr>
    \\</table></td></tr></tbody></table>
    \\<table class="tablefloatheb"><tbody><tr><td height="165" valign="middle" align="right">
    \\<span class="strongsnt"><a href="/hebrew/5662.htm" title="Strong's Hebrew 5662: of Obadiah">5662</a></span>&nbsp;</span>
    \\<span class="strongsnt"><a href="/hebrew/strongs_5662.htm" title="Englishman's Hebrew Concordance">[e]</a></span><br>
    \\<span class="translit"><a href="/hebrew/oadyah_5662.htm" title="obadyah">obadyah</a></span><br>
    \\<span class="hebrew">&#1506;&#1465;&#1469;&#1489;&#1463;&#1491;&#1456;&#1497;&#1464;&#1425;&#1492;</span><br>
    \\<span class="eng">of&nbsp;Obadiah</span><br>
    \\<span class="strongsnt"><a href="/hebrewparse.htm" title="Noun - proper - masculine singular">N&#8209;proper&#8209;ms</a></span>
    \\</td></tr></tbody></table>
;

test "parseInterlinearHtml: Greek fixture extracts word/verse/strongs/morph" {
    const words = try parseInterlinearHtml(std.testing.allocator, greek_fixture, 'G');
    defer freeWords(std.testing.allocator, words);

    try std.testing.expectEqual(@as(usize, 2), words.len);

    try std.testing.expectEqual(@as(i32, 1), words[0].verse);
    try std.testing.expectEqual(@as(i32, 0), words[0].word_index);
    try std.testing.expectEqualStrings("Παῦλος", words[0].original_text);
    try std.testing.expectEqualStrings("Paul", words[0].translation);
    try std.testing.expectEqualStrings("G3972", words[0].strongs);
    try std.testing.expectEqualStrings("N-NMS", words[0].morphology);

    // Second word table has no reftop3 span -> verse stays 1, index continues.
    try std.testing.expectEqual(@as(i32, 1), words[1].verse);
    try std.testing.expectEqual(@as(i32, 1), words[1].word_index);
    try std.testing.expectEqualStrings("G1198", words[1].strongs);
    // &nbsp;-joined translation keeps the literal U+00A0, matching what's
    // already stored in data/bible.db for this same page's real translations.
    try std.testing.expectEqualStrings("a\u{00a0}prisoner", words[1].translation);
}

test "parseInterlinearHtml: Hebrew fixture decodes numeric entities and handles nested <table>" {
    const words = try parseInterlinearHtml(std.testing.allocator, hebrew_fixture, 'H');
    defer freeWords(std.testing.allocator, words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqual(@as(i32, 1), words[0].verse);
    try std.testing.expectEqualStrings("\u{05d7}\u{05b2}\u{05d6}\u{0596}\u{05d5}\u{05b9}\u{05df}", words[0].original_text);
    try std.testing.expectEqualStrings("The\u{00a0}vision", words[0].translation);
    // KNOWN BEHAVIORAL NOTE case: today's live Hebrew markup uses
    // class="strongsnt" (not "pos"/"strongs") for the number span, and links
    // morphology to /hebrewparse.htm (not /grammar/) -- both come back empty,
    // matching the Python source's same class-list gap on this same markup.
    try std.testing.expectEqualStrings("", words[0].strongs);
    try std.testing.expectEqualStrings("", words[0].morphology);

    try std.testing.expectEqual(@as(i32, 1), words[1].verse);
    try std.testing.expectEqual(@as(i32, 1), words[1].word_index);
    try std.testing.expectEqualStrings("of\u{00a0}Obadiah", words[1].translation);
}

test "parseInterlinearHtml: strongs already prefixed with G/H is kept as-is" {
    const html =
        \\<table class="tablefloat"><tr><td>
        \\<span class="reftop3">5</span>
        \\<span class="pos"><a href="/greek/25.htm">G25</a></span>
        \\<span class="greek">test</span>
        \\<span class="eng">love</span>
        \\</td></tr></table>
    ;
    const words = try parseInterlinearHtml(std.testing.allocator, html, 'G');
    defer freeWords(std.testing.allocator, words);
    try std.testing.expectEqual(@as(usize, 1), words.len);
    try std.testing.expectEqualStrings("G25", words[0].strongs);
}

test "parseInterlinearHtml: word tables before any verse span are skipped (current_verse == 0)" {
    const html =
        \\<table class="tablefloat"><tr><td>
        \\<span class="pos"><a href="/greek/1.htm">1</a></span>
        \\<span class="greek">orphan</span>
        \\</td></tr></table>
        \\<table class="tablefloat"><tr><td>
        \\<span class="reftop3">1</span>
        \\<span class="greek">real</span>
        \\</td></tr></table>
    ;
    const words = try parseInterlinearHtml(std.testing.allocator, html, 'G');
    defer freeWords(std.testing.allocator, words);
    try std.testing.expectEqual(@as(usize, 1), words.len);
    try std.testing.expectEqualStrings("real", words[0].original_text);
}

test "languagePrefix: Old Testament book -> H, New Testament book -> G, unknown book defaults to G" {
    const t = testIo();
    var threaded = t.threaded;
    defer threaded.deinit();

    try std.testing.expectEqual(@as(u8, 'H'), try languagePrefix(std.testing.allocator, t.io, "Genesis"));
    try std.testing.expectEqual(@as(u8, 'G'), try languagePrefix(std.testing.allocator, t.io, "John"));
    // "SongofSolomon" is Old Testament (Hebrew), per tools/bible_books.json --
    // this is the exact book name the "SongofSolomon" vs "Song of Solomon"
    // regression test in bible_db.zig exists to guard.
    try std.testing.expectEqual(@as(u8, 'H'), try languagePrefix(std.testing.allocator, t.io, "SongofSolomon"));
    try std.testing.expectEqual(@as(u8, 'H'), try languagePrefix(std.testing.allocator, t.io, "Obadiah"));
    try std.testing.expectEqual(@as(u8, 'G'), try languagePrefix(std.testing.allocator, t.io, "NotARealBook"));
}

test "parseLexiconHtml: no strongs/strongsnt divs -> all fields empty (matches live BibleHub page structure)" {
    const html =
        \\<div id="leftbox"><div class="padleft">Lexical Summary content here</div></div>
    ;
    const fields = try parseLexiconHtml(std.testing.allocator, html);
    defer fields.free(std.testing.allocator);
    try std.testing.expectEqualStrings("", fields.lemma);
    try std.testing.expectEqualStrings("", fields.transliteration);
    try std.testing.expectEqualStrings("", fields.definition);
    try std.testing.expectEqualStrings("", fields.usage);
}

test "parseLexiconHtml: strongsnt div present -> definition is its stripped text" {
    const html =
        \\<div class="strongs">gate</div>
        \\<div id="leftbox">ignored because strongsnt below wins</div>
        \\<div class="strongsnt">  to love, to have affection for  </div>
    ;
    const fields = try parseLexiconHtml(std.testing.allocator, html);
    defer fields.free(std.testing.allocator);
    try std.testing.expectEqualStrings("to love, to have affection for", fields.definition);
}

test "parseLexiconHtml: strongs div without strongsnt -> definition is first 100 words of leftbox" {
    const html =
        \\<div class="strongs">gate</div>
        \\<div id="leftbox">one two three</div>
    ;
    const fields = try parseLexiconHtml(std.testing.allocator, html);
    defer fields.free(std.testing.allocator);
    try std.testing.expectEqualStrings("one two three", fields.definition);
}

test "extractText: strips nested tags, decodes entities, trims NBSP like Python's .strip()" {
    const t = try extractText(std.testing.allocator, "&nbsp;<a href=\"/x\">3972</a>&nbsp;");
    defer std.testing.allocator.free(t);
    try std.testing.expectEqualStrings("3972", t);
}

test "extractText: decimal numeric entities decode to UTF-8" {
    const t = try extractText(std.testing.allocator, "&#1495;&#1458;");
    defer std.testing.allocator.free(t);
    try std.testing.expectEqualStrings("\u{05d7}\u{05b2}", t);
}

// --- Retry-with-backoff: tested via a fake attempt function, no network ----
// Following the parse/fetch split above, the retry *control flow* is tested
// against fetchWithRetry's actual sibling helper `isTransientStatus`/
// `isPermanentFetchError` plus a hand-rolled driver identical in shape to
// fetchWithRetry but parameterized over a fake "do one attempt" callback, so
// attempt counts and backoff/no-backoff decisions are asserted directly
// without opening a single socket.

const FakeAttempt = struct {
    responses: []const (anyerror!HttpResponse),
    calls: usize = 0,

    fn attempt(self: *FakeAttempt) anyerror!HttpResponse {
        const r = self.responses[self.calls];
        self.calls += 1;
        return r;
    }
};

fn retryDriver(fake: *FakeAttempt, config: RetryConfig) !HttpResponse {
    var attempt: u32 = 1;
    while (true) : (attempt += 1) {
        if (fake.attempt()) |resp| {
            if (isTransientStatus(resp.status) and attempt < config.attempts) continue;
            return resp;
        } else |err| {
            if (isPermanentFetchError(err) or attempt >= config.attempts) return err;
            continue;
        }
    }
}

test "retry driver: succeeds immediately on 200, no retries" {
    var responses = [_]anyerror!HttpResponse{.{ .status = 200, .body = &.{} }};
    var fake = FakeAttempt{ .responses = &responses };
    const resp = try retryDriver(&fake, .{});
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
}

test "retry driver: does not retry a 404 (matches fetch_with_retry's 4xx-is-final behavior)" {
    var responses = [_]anyerror!HttpResponse{.{ .status = 404, .body = &.{} }};
    var fake = FakeAttempt{ .responses = &responses };
    const resp = try retryDriver(&fake, .{});
    try std.testing.expectEqual(@as(u16, 404), resp.status);
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
}

test "retry driver: retries transient 503 up to `attempts`, then returns the last response" {
    var responses = [_]anyerror!HttpResponse{
        .{ .status = 503, .body = &.{} },
        .{ .status = 503, .body = &.{} },
        .{ .status = 503, .body = &.{} },
    };
    var fake = FakeAttempt{ .responses = &responses };
    const resp = try retryDriver(&fake, .{ .attempts = 3 });
    try std.testing.expectEqual(@as(u16, 503), resp.status);
    try std.testing.expectEqual(@as(usize, 3), fake.calls);
}

test "retry driver: recovers after a transient failure within the attempt budget" {
    var responses = [_]anyerror!HttpResponse{
        error.Timeout,
        .{ .status = 200, .body = &.{} },
    };
    var fake = FakeAttempt{ .responses = &responses };
    const resp = try retryDriver(&fake, .{ .attempts = 3 });
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqual(@as(usize, 2), fake.calls);
}

test "retry driver: does not retry a permanent (invalid-URL-shaped) error" {
    var responses = [_]anyerror!HttpResponse{error.UnsupportedUriScheme};
    var fake = FakeAttempt{ .responses = &responses };
    try std.testing.expectError(error.UnsupportedUriScheme, retryDriver(&fake, .{}));
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
}

test "retry driver: raises the last transient error once attempts are exhausted" {
    var responses = [_]anyerror!HttpResponse{ error.Timeout, error.Timeout, error.Timeout };
    var fake = FakeAttempt{ .responses = &responses };
    try std.testing.expectError(error.Timeout, retryDriver(&fake, .{ .attempts = 3 }));
    try std.testing.expectEqual(@as(usize, 3), fake.calls);
}

test "strongsLessThan: Greek before Hebrew, lexicographic within each group" {
    var list = [_][]const u8{ "H100", "G50", "G5", "H1", "G500" };
    std.mem.sort([]const u8, &list, {}, strongsLessThan);
    const expected = [_][]const u8{ "G5", "G50", "G500", "H1", "H100" };
    for (list, expected) |got, want| try std.testing.expectEqualStrings(want, got);
}

// --- End-to-end DB round trip: parse fixture -> insert -> read back --------

test "scrapeInterlinear-shaped round trip: parsed fixture rows land in the interlinear table" {
    var db: ?*bible.sqlite3 = null;
    _ = bible.sqlite3_open(":memory:", @ptrCast(&db));
    defer _ = bible.sqlite3_close(db.?);
    try bible.init_db(db.?);

    const words = try parseInterlinearHtml(std.testing.allocator, greek_fixture, 'G');
    defer freeWords(std.testing.allocator, words);

    for (words) |w| {
        bible.insert_interlinear_word(db.?, "Philemon", 1, w.verse, w.word_index, w.original_text, w.translation, w.strongs, w.morphology, "GNT");
    }

    const ctx = try bible.get_verse_lexicon_context(std.testing.allocator, db.?, "Philemon", 1, 1);
    defer std.testing.allocator.free(ctx);
    try std.testing.expect(std.mem.indexOf(u8, ctx, "Paul") != null);
    try std.testing.expect(std.mem.indexOf(u8, ctx, "N-NMS") != null);

    const strongs_list = try bible.distinct_interlinear_strongs(std.testing.allocator, db.?, "Philemon", 1);
    defer {
        for (strongs_list) |s| std.testing.allocator.free(s);
        std.testing.allocator.free(strongs_list);
    }
    try std.testing.expectEqual(@as(usize, 2), strongs_list.len);
}

// --- Live network smoke test -------------------------------------------
// Skipped by default (no network access assumed in ordinary `zig build
// test`/CI runs). Run explicitly with:
//   METANOIA_LIVE_SCRAPER_TEST=1 zig build test
// to verify the parser against a real, current BibleHub page rather than
// just the fixtures above.
test "LIVE: scrapeInterlinear against a real BibleHub page" {
    if (std.c.getenv("METANOIA_LIVE_SCRAPER_TEST") == null) {
        return error.SkipZigTest;
    }

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var db: ?*bible.sqlite3 = null;
    _ = bible.sqlite3_open(":memory:", @ptrCast(&db));
    defer _ = bible.sqlite3_close(db.?);
    try bible.init_db(db.?);

    try scrapeInterlinear(io, std.testing.allocator, db.?, "Philemon", 1);

    const strongs_list = try bible.distinct_interlinear_strongs(std.testing.allocator, db.?, "Philemon", 1);
    defer {
        for (strongs_list) |s| std.testing.allocator.free(s);
        std.testing.allocator.free(strongs_list);
    }
    std.debug.print("LIVE interlinear: {d} distinct strongs numbers cached for Philemon 1\n", .{strongs_list.len});
    try std.testing.expect(strongs_list.len > 0);

    try scrapeLexicon(io, std.testing.allocator, db.?, "Philemon", 1);
    if (strongs_list.len > 0) {
        const detail = try bible.get_lexicon_detail(std.testing.allocator, db.?, strongs_list[0]);
        if (detail) |d| {
            defer {
                std.testing.allocator.free(d.strongs);
                std.testing.allocator.free(d.lemma);
                std.testing.allocator.free(d.transliteration);
                std.testing.allocator.free(d.definition);
                std.testing.allocator.free(d.language);
            }
            std.debug.print("LIVE lexicon sample: strongs={s} language={s} lemma=\"{s}\" definition=\"{s}\"\n", .{ d.strongs, d.language, d.lemma, d.definition });
        }
    }
}
