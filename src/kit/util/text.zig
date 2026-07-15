//! Text utilities for Pango markup and string escaping.

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

pub fn span(allocator: std.mem.Allocator, text: []const u8, attrs: []const u8) ![:0]u8 {
    const escaped = try escape(allocator, text);
    defer allocator.free(escaped);

    var result = std.ArrayListUnmanaged(u8).empty;
    defer result.deinit(allocator);

    try result.appendSlice(allocator, "<span ");
    try result.appendSlice(allocator, attrs);
    try result.append(allocator, '>');
    try result.appendSlice(allocator, escaped);
    try result.appendSlice(allocator, "</span>");

    return result.toOwnedSliceSentinel(allocator, 0);
}

pub fn bold(allocator: std.mem.Allocator, text: []const u8) ![:0]u8 {
    return span(allocator, text, "weight='bold'");
}

pub fn colored(allocator: std.mem.Allocator, text: []const u8, color: []const u8) ![:0]u8 {
    var attrs = std.ArrayListUnmanaged(u8).empty;
    defer attrs.deinit(allocator);

    try attrs.appendSlice(allocator, "color='");
    try attrs.appendSlice(allocator, color);
    try attrs.append(allocator, '\'');

    return span(allocator, text, attrs.items);
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

test "span wraps text with attrs" {
    const allocator = std.testing.allocator;
    const result = try span(allocator, "hello", "color='#7aa2f7' weight='bold'");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<span color='#7aa2f7' weight='bold'>hello</span>", result);
}

test "span escapes special chars in text" {
    const allocator = std.testing.allocator;
    const result = try span(allocator, "a < b", "color='red'");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<span color='red'>a &lt; b</span>", result);
}

test "bold wraps text in bold span" {
    const allocator = std.testing.allocator;
    const result = try bold(allocator, "Hello");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<span weight='bold'>Hello</span>", result);
}

test "bold escapes text" {
    const allocator = std.testing.allocator;
    const result = try bold(allocator, "a & b");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<span weight='bold'>a &amp; b</span>", result);
}

test "colored wraps text with color attr" {
    const allocator = std.testing.allocator;
    const result = try colored(allocator, "Hello", "#7aa2f7");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<span color='#7aa2f7'>Hello</span>", result);
}

test "colored escapes text" {
    const allocator = std.testing.allocator;
    const result = try colored(allocator, "a < b", "red");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("<span color='red'>a &lt; b</span>", result);
}
