const std = @import("std");

test "URL validation - valid URLs" {
    const valid_urls = [_][]const u8{
        "http://127.0.0.1:8000",
        "http://192.168.1.100:8000",
        "https://example.com:443",
        "http://localhost:3000",
    };

    for (valid_urls) |url| {
        try std.testing.expect(isValidUrl(url));
    }
}

test "URL validation - invalid URLs" {
    const invalid_urls = [_][]const u8{
        "ftp://example.com",
        "http://",
        "not a url",
        "",
        "http:noport",
    };

    for (invalid_urls) |url| {
        try std.testing.expect(!isValidUrl(url));
    }
}

fn isValidUrl(url: []const u8) bool {
    if (url.len < 7) return false;
    if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) return false;

    var has_colon = false;
    var has_valid_host = false;

    for (url) |c| {
        if (c == ':') has_colon = true;
        if (c == '.' or std.mem.indexOf(u8, url, "localhost") != null) has_valid_host = true;
    }

    return has_colon and has_valid_host;
}
