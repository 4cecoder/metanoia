const std = @import("std");
const network_discovery = @import("services/network_discovery.zig");

test "NetworkDiscovery integration: chunked scanning strategy" {
    const config = network_discovery.DiscoveryConfig{
        .chunk_size = 10,
        .subnets = &.{ "192.168.1", "192.168.0" },
    };

    var discovery = network_discovery.NetworkDiscovery.init(std.testing.allocator, undefined, config);

    const addresses = try discovery.generateIPAddresses(std.testing.allocator);
    defer {
        for (addresses) |addr| std.testing.allocator.free(addr);
        std.testing.allocator.free(addresses);
    }

    const expected_total = 254 * 2;
    try std.testing.expectEqual(@as(usize, expected_total), addresses.len);
}

test "NetworkDiscovery integration: custom port and endpoint" {
    const config = network_discovery.DiscoveryConfig{
        .port = 3000,
        .endpoint = "/health",
        .timeout_ms = 100,
    };

    var discovery = network_discovery.NetworkDiscovery.init(std.testing.allocator, undefined, config);

    try std.testing.expectEqual(@as(u16, 3000), discovery.config.port);
    try std.testing.expectEqualStrings("/health", discovery.config.endpoint);
    try std.testing.expectEqual(@as(u32, 100), discovery.config.timeout_ms);
}

test "NetworkDiscovery integration: memory safety with large subnet list" {
    const subnets = [_][]const u8{ "192.168.0", "192.168.1", "192.168.2", "10.0.0", "172.16.0" };
    const config = network_discovery.DiscoveryConfig{
        .subnets = &subnets,
    };

    var discovery = network_discovery.NetworkDiscovery.init(std.testing.allocator, undefined, config);

    const addresses = try discovery.generateIPAddresses(std.testing.allocator);
    defer {
        for (addresses) |addr| std.testing.allocator.free(addr);
        std.testing.allocator.free(addresses);
    }

    const expected_total = 254 * 5;
    try std.testing.expectEqual(@as(usize, expected_total), addresses.len);

    for (addresses) |addr| {
        try std.testing.expect(addr.len > 0);
    }
}

test "NetworkDiscovery integration: configuration validation" {
    const test_cases = [_]struct {
        config: network_discovery.DiscoveryConfig,
        expected_port: u16,
        expected_timeout: u32,
    }{
        .{ .config = .{}, .expected_port = 8000, .expected_timeout = 200 },
        .{ .config = .{ .port = 80 }, .expected_port = 80, .expected_timeout = 200 },
        .{ .config = .{ .timeout_ms = 1000 }, .expected_port = 8000, .expected_timeout = 1000 },
        .{ .config = .{ .port = 443, .timeout_ms = 500 }, .expected_port = 443, .expected_timeout = 500 },
    };

    for (test_cases) |tc| {
        var discovery = network_discovery.NetworkDiscovery.init(std.testing.allocator, undefined, tc.config);
        try std.testing.expectEqual(tc.expected_port, discovery.config.port);
        try std.testing.expectEqual(tc.expected_timeout, discovery.config.timeout_ms);
    }
}
