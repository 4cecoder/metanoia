//! Opt-in "is a newer build available?" checker for the rolling `latest`
//! GitHub Release (see .github/workflows/release-latest.yml, which
//! rebuilds and republishes this tag on every push to master). Desktop
//! mirror of mobile/app/src/main/java/com/bytecats/metanoia/update/
//! UpdateChecker.kt -- same split, same two real bugs that file's history
//! already found and fixed (see extractCommitSha below), same "notify only,
//! never auto-download/self-replace" scope.
//!
//! Split the same way as the Kotlin original: `extractCommitSha`,
//! `parseRelease`, and `isUpdateAvailable` are pure functions with no I/O,
//! testable against fixture strings; `fetchLatestRelease` is the only part
//! that touches the network, following src/native_scraper.zig's existing
//! std.http.Client + Io.Select timeout-race idiom (see doFetchOnce/
//! httpGetOnce there) rather than inventing a different HTTP approach.
//!
//! Wiring (see src/main.zig): run on a background g_thread_new thread at
//! startup, and if an update is available, post a plain-text notice
//! (including the releases page URL) via kit.components.StatusBar's
//! existing updateStatus() -- no new dialog/toast, no clickable link, no
//! silent auto-download. That's a deliberate, explicit scope decision, not
//! an oversight.

const std = @import("std");

pub const RELEASES_API_URL = "https://api.github.com/repos/4cecoder/metanoia/releases/tags/latest";

/// Result of parsing the GitHub Releases API response for the "latest"
/// rolling tag. `commit_sha` and `html_url` are separately-allocated
/// slices (or null) owned by the caller -- see `deinit`.
pub const ReleaseInfo = struct {
    commit_sha: ?[]const u8,
    html_url: ?[]const u8,

    pub fn deinit(self: ReleaseInfo, allocator: std.mem.Allocator) void {
        if (self.commit_sha) |s| allocator.free(s);
        if (self.html_url) |s| allocator.free(s);
    }
};

fn isHexDigit(c: u8) bool {
    return switch (c) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

fn isWordChar(c: u8) bool {
    return switch (c) {
        '0'...'9', 'a'...'z', 'A'...'Z', '_' => true,
        else => false,
    };
}

fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

/// Finds the first "commit:" label (case-insensitive, matching
/// UpdateChecker.kt's `(?i)commit:\s*([0-9a-f]{7,40})\s*` regex) and
/// returns the 7-40 hex-char token immediately following it (after
/// whitespace), or null if no such labeled sha is present anywhere in the
/// text.
fn findLabeledCommitSha(body: []const u8) ?[]const u8 {
    const needle = "commit:";
    var i: usize = 0;
    while (i + needle.len <= body.len) : (i += 1) {
        if (!asciiEqlIgnoreCase(body[i .. i + needle.len], needle)) continue;
        var j = i + needle.len;
        while (j < body.len and (body[j] == ' ' or body[j] == '\t')) : (j += 1) {}
        const start = j;
        while (j < body.len and isHexDigit(body[j])) : (j += 1) {}
        const len = j - start;
        if (len >= 7 and len <= 40) return body[start..j];
        // Not a valid labeled sha at this occurrence (e.g. "commit:" used
        // in an unrelated sentence) -- keep scanning for another one.
    }
    return null;
}

/// Finds the first bare 40-hex-char token in the text, with a word-boundary
/// check on both sides (mirroring the Kotlin regex's `\b...\b`) so a longer
/// alphanumeric run that merely contains 40 hex-looking characters doesn't
/// false-positive.
fn findBareFullSha(body: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < body.len) {
        if (!isHexDigit(body[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < body.len and isHexDigit(body[i])) : (i += 1) {}
        const len = i - start;
        const left_ok = start == 0 or !isWordChar(body[start - 1]);
        const right_ok = i == body.len or !isWordChar(body[i]);
        if (len == 40 and left_ok and right_ok) return body[start..i];
    }
    return null;
}

/// Extracts a commit sha from a release body: prefers an explicit
/// "commit: <sha>" line, falls back to a bare 40-char hex sha anywhere in
/// the text, or null if neither is present.
///
/// Mirrors UpdateChecker.kt's extractCommitSha exactly, including its
/// documented fallback rationale: a real release-body wording change once
/// dropped the labeled "commit:" line while still mentioning the sha in
/// prose (e.g. "Rebuilt from `<sha>`"), which silently made the
/// labeled-only version of this function think no commit sha was ever
/// available (isUpdateAvailable degrades to "false" when commit_sha is
/// null) -- the whole checker looked broken with no error anywhere. A bare
/// 40-hex-char sha is unambiguous enough to match unlabeled (unlike a short
/// sha, too easily confused with an unrelated hex-looking token), so this
/// is a safe last resort.
pub fn extractCommitSha(body: []const u8) ?[]const u8 {
    if (findLabeledCommitSha(body)) |sha| return sha;
    return findBareFullSha(body);
}

/// Parses a GitHub Releases API JSON response body. Returns null on any
/// malformed input (invalid JSON, missing/blank tag_name, unexpected
/// types) rather than erroring -- this is a best-effort background check,
/// never something that should propagate a parse error up to the caller.
pub fn parseRelease(allocator: std.mem.Allocator, json_body: []const u8) ?ReleaseInfo {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_body, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;

    const tag_val = parsed.value.object.get("tag_name") orelse return null;
    if (tag_val != .string or tag_val.string.len == 0) return null;

    var commit_sha: ?[]const u8 = null;
    if (parsed.value.object.get("body")) |body_val| {
        if (body_val == .string) {
            if (extractCommitSha(body_val.string)) |sha| {
                commit_sha = allocator.dupe(u8, sha) catch null;
            }
        }
    }

    var html_url: ?[]const u8 = null;
    if (parsed.value.object.get("html_url")) |url_val| {
        if (url_val == .string and url_val.string.len > 0) {
            html_url = allocator.dupe(u8, url_val.string) catch null;
        }
    }

    return ReleaseInfo{ .commit_sha = commit_sha, .html_url = html_url };
}

/// Pure comparison: is `fetched` a genuinely different build than the one
/// currently running (`current_commit_sha`, from `build_options.git_commit_sha`)?
///
/// Mirrors UpdateChecker.kt's isUpdateAvailable exactly:
/// - false if `fetched` is null, or has no commit sha (can't compare).
/// - true if `current_commit_sha` is blank OR the build-time-baked-in
///   "unknown" sentinel (see build.zig's gitCommitSha()) -- can't prove
///   we're current, so surface the notice (same semantics as the Kotlin
///   side's blank-current-sha case).
/// - otherwise true iff neither sha is a prefix of the other (handles
///   short-sha vs full-sha comparisons).
pub fn isUpdateAvailable(current_commit_sha: []const u8, fetched: ?ReleaseInfo) bool {
    const remote_sha = if (fetched) |f| (f.commit_sha orelse return false) else return false;
    if (current_commit_sha.len == 0 or std.mem.eql(u8, current_commit_sha, "unknown")) return true;
    if (std.mem.startsWith(u8, remote_sha, current_commit_sha)) return false;
    if (std.mem.startsWith(u8, current_commit_sha, remote_sha)) return false;
    return true;
}

// ============================================================================
// HTTP fetch (mirrors src/native_scraper.zig's doFetchOnce/httpGetOnce exactly)
// ============================================================================

pub const HttpResult = struct {
    status: u16,
    body: []u8,
};

const FetchTaskResult = union(enum) {
    ok: HttpResult,
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
        .extra_headers = &.{.{ .name = "Accept", .value = "application/vnd.github+json" }},
    }) catch |err| return .{ .err = err };

    const body = allocator.dupe(u8, aw.writer.buffer[0..aw.writer.end]) catch |err| return .{ .err = err };
    return .{ .ok = .{ .status = @intFromEnum(result.status), .body = body } };
}

fn sleepIgnoringCancel(io: std.Io, nanoseconds: i96) void {
    io.sleep(.{ .nanoseconds = nanoseconds }, .awake) catch {};
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

/// Performs one GET with a real wall-clock timeout, racing the fetch
/// against a timer via `Io.Select` and canceling whichever loses -- the
/// same idiom as src/native_scraper.zig's httpGetOnce/doFetchOnce. Unlike
/// that file's fuller retry-with-backoff version (built for a scraper that
/// must eventually succeed), this is a one-shot: an opt-in startup check
/// that should silently give up on any failure rather than retry.
fn httpGetOnce(io: std.Io, allocator: std.mem.Allocator, url: []const u8, timeout_ns: i96) !HttpResult {
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

/// Fetches and parses the "latest" rolling release. Returns null on any
/// network/HTTP-status/parse failure -- never throws, since this is a
/// best-effort background check that must not crash or block startup.
/// Caller owns the returned `ReleaseInfo` (see `ReleaseInfo.deinit`).
pub fn fetchLatestRelease(io: std.Io, allocator: std.mem.Allocator) ?ReleaseInfo {
    const resp = httpGetOnce(io, allocator, RELEASES_API_URL, 10 * std.time.ns_per_s) catch return null;
    defer allocator.free(resp.body);
    if (resp.status < 200 or resp.status >= 300) return null;
    return parseRelease(allocator, resp.body);
}

// ============================================================================
// Tests (pure functions only -- no network access in `zig build test`)
// ============================================================================

test "extractCommitSha: labeled 'commit: <sha>' line" {
    const body = "Rebuilt on every push.\n\ncommit: df26515a16d500f10c13374b13dfb267cc4a5041\n";
    const sha = extractCommitSha(body).?;
    try std.testing.expectEqualStrings("df26515a16d500f10c13374b13dfb267cc4a5041", sha);
}

test "extractCommitSha: labeled line is case-insensitive and tolerates surrounding whitespace" {
    const body = "COMMIT:   1234567\n";
    const sha = extractCommitSha(body).?;
    try std.testing.expectEqualStrings("1234567", sha);
}

test "extractCommitSha: falls back to a bare 40-hex-char sha when no labeled line exists" {
    const body = "Rebuilt from `df26515a16d500f10c13374b13dfb267cc4a5041` today.";
    const sha = extractCommitSha(body).?;
    try std.testing.expectEqualStrings("df26515a16d500f10c13374b13dfb267cc4a5041", sha);
}

test "extractCommitSha: bare fallback ignores a run longer than 40 word chars" {
    // Not a real sha -- a 41-char alphanumeric token should not match as if
    // it were a bare 40-hex-char sha (word-boundary check).
    const body = "token gdf26515a16d500f10c13374b13dfb267cc4a504 done";
    try std.testing.expect(extractCommitSha(body) == null);
}

test "extractCommitSha: no sha anywhere returns null" {
    try std.testing.expect(extractCommitSha("Just a description, no sha here.") == null);
}

test "parseRelease: full real-shaped response" {
    const json =
        \\{"tag_name":"latest","html_url":"https://github.com/4cecoder/metanoia/releases/tag/latest","body":"Rebuilt from `df26515a16d500f10c13374b13dfb267cc4a5041`.\n\ncommit: df26515a16d500f10c13374b13dfb267cc4a5041"}
    ;
    const info = parseRelease(std.testing.allocator, json).?;
    defer info.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("df26515a16d500f10c13374b13dfb267cc4a5041", info.commit_sha.?);
    try std.testing.expectEqualStrings("https://github.com/4cecoder/metanoia/releases/tag/latest", info.html_url.?);
}

test "parseRelease: missing tag_name returns null" {
    try std.testing.expect(parseRelease(std.testing.allocator, "{\"body\":\"commit: 1234567\"}") == null);
}

test "parseRelease: malformed JSON returns null" {
    try std.testing.expect(parseRelease(std.testing.allocator, "not json") == null);
}

test "isUpdateAvailable: identical full shas -> false" {
    const sha = "df26515a16d500f10c13374b13dfb267cc4a5041";
    const info = ReleaseInfo{ .commit_sha = sha, .html_url = null };
    try std.testing.expect(!isUpdateAvailable(sha, info));
}

test "isUpdateAvailable: short current sha is a prefix of the full remote sha -> false" {
    const info = ReleaseInfo{ .commit_sha = "df26515a16d500f10c13374b13dfb267cc4a5041", .html_url = null };
    try std.testing.expect(!isUpdateAvailable("df26515", info));
}

test "isUpdateAvailable: genuinely different shas -> true" {
    const info = ReleaseInfo{ .commit_sha = "1111111111111111111111111111111111111111", .html_url = null };
    try std.testing.expect(isUpdateAvailable("2222222222222222222222222222222222222222", info));
}

test "isUpdateAvailable: blank current sha -> true (can't prove we're current)" {
    const info = ReleaseInfo{ .commit_sha = "df26515a16d500f10c13374b13dfb267cc4a5041", .html_url = null };
    try std.testing.expect(isUpdateAvailable("", info));
}

test "isUpdateAvailable: build-time 'unknown' sentinel -> true" {
    const info = ReleaseInfo{ .commit_sha = "df26515a16d500f10c13374b13dfb267cc4a5041", .html_url = null };
    try std.testing.expect(isUpdateAvailable("unknown", info));
}

test "isUpdateAvailable: null fetch result -> false" {
    try std.testing.expect(!isUpdateAvailable("df26515", null));
}

test "isUpdateAvailable: remote has no commit sha -> false (can't compare)" {
    const info = ReleaseInfo{ .commit_sha = null, .html_url = null };
    try std.testing.expect(!isUpdateAvailable("df26515", info));
}
