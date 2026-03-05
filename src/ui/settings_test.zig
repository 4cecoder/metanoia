const std = @import("std");

fn isValidUrl(url: []const u8) bool {
    if (url.len < 7) return false;
    if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) return false;
    
    // Check if it has a host part
    const proto_end = std.mem.indexOf(u8, url, "://").? + 3;
    if (url.len <= proto_end) return false;
    
    return true; // Simplified for basic presence check
}

test "URL Validation logic" {
    const testing = std.testing;
    
    // Valid
    try testing.expect(isValidUrl("http://localhost:8000"));
    try testing.expect(isValidUrl("https://192.168.1.50:8000"));
    try testing.expect(isValidUrl("http://google.com"));
    try testing.expect(isValidUrl("http://localhost"));
    
    // Invalid
    try testing.expect(!isValidUrl("localhost:8000")); // Missing protocol
    try testing.expect(!isValidUrl("ftp://localhost:21")); // Wrong protocol
    try testing.expect(!isValidUrl("http://")); // Missing host
    try testing.expect(!isValidUrl(""));
}
