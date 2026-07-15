const std = @import("std");

pub fn escape(allocator: std.mem.Allocator, text: []const u8) ![:0]u8 {
    var result = std.ArrayListUnmanaged(u8).empty;
    defer result.deinit(allocator);

    for (text) |c| {
        switch (c) {
            '&' => try result.appendSlice(allocator, "&amp;"),
            '<' => try result.appendSlice(allocator, "&lt;"),
            '>' => try result.appendSlice(allocator, "&gt;"),
            '"' => try result.appendSlice(allocator, "&quot;"),
            '\'' => try result.appendSlice(allocator, "&apos;"),
            else => try result.append(allocator, c),
        }
    }

    return result.toOwnedSliceSentinel(allocator, 0);
}

test "escape preserves plain text" {
    const allocator = std.testing.allocator;
    const result = try escape(allocator, "Hello World");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

test "escape converts ampersand" {
    const allocator = std.testing.allocator;
    const result = try escape(allocator, "Historical & Lexical");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Historical &amp; Lexical", result);
}

test "escape converts angle brackets" {
    const allocator = std.testing.allocator;
    const result = try escape(allocator, "a < b && c > d");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("a &lt; b &amp;&amp; c &gt; d", result);
}

test "escape converts quotes" {
    const allocator = std.testing.allocator;
    const result = try escape(allocator, "She said \"hello\" and 'goodbye'");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("She said &quot;hello&quot; and &apos;goodbye&apos;", result);
}

test "escape handles empty string" {
    const allocator = std.testing.allocator;
    const result = try escape(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "escape handles multiple special chars" {
    const allocator = std.testing.allocator;
    const result = try escape(allocator, "&<>&\"'");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("&amp;&lt;&gt;&amp;&quot;&apos;", result);
}

test "escape returns sentinel-terminated" {
    const allocator = std.testing.allocator;
    const result = try escape(allocator, "test");
    defer allocator.free(result);
    try std.testing.expect(result[result.len] == 0);
}
