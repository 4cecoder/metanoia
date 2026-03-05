const std = @import("std");

pub const DiscoveryConfig = struct {
    port: u16 = 8000,
    timeout_ms: u32 = 200,
    chunk_size: u8 = 32,
    chunk_wait_ms: u32 = 400,
    subnets: []const []const u8 = &.{ "192.168.1", "192.168.0", "10.0.0" },
    endpoint: []const u8 = "/system_info",
};

pub const DiscoveryResult = struct {
    url: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DiscoveryResult) void {
        self.allocator.free(self.url);
    }
};

pub const ProbeError = error{
    SpawnFailed,
    WaitFailed,
    InvalidIP,
    AllocationFailed,
};

pub const NetworkDiscovery = struct {
    allocator: std.mem.Allocator,
    config: DiscoveryConfig,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: DiscoveryConfig) NetworkDiscovery {
        return .{
            .allocator = allocator,
            .config = config,
            .io = io,
        };
    }

    pub fn probeAddress(self: *NetworkDiscovery, ip: []const u8) ProbeError!bool {
        const url = std.fmt.allocPrint(self.allocator, "http://{s}:{d}", .{ ip, self.config.port }) catch return ProbeError.AllocationFailed;
        defer self.allocator.free(url);

        const check_url = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ url, self.config.endpoint }) catch return ProbeError.AllocationFailed;
        defer self.allocator.free(check_url);

        const timeout_str = std.fmt.allocPrint(self.allocator, "{d}", .{self.config.timeout_ms}) catch return ProbeError.AllocationFailed;
        defer self.allocator.free(timeout_str);

        var child = std.process.spawn(self.io, .{
            .argv = &.{ "curl", "-s", "--connect-timeout", timeout_str, "-f", check_url },
            .stdout = .pipe,
        }) catch return ProbeError.SpawnFailed;

        const term = child.wait(self.io) catch return ProbeError.WaitFailed;
        return term == .exited and term.exited == 0;
    }

    pub fn generateIPAddresses(self: *NetworkDiscovery, allocator: std.mem.Allocator) ![][]const u8 {
        var addresses = std.ArrayList([]const u8).initCapacity(allocator, 100) catch return ProbeError.AllocationFailed;
        errdefer {
            for (addresses.items) |addr| allocator.free(addr);
            addresses.deinit(allocator);
        }

        for (self.config.subnets) |subnet| {
            var i: u8 = 1;
            while (i < 255) : (i += 1) {
                const ip = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ subnet, i });
                try addresses.append(allocator, ip);
            }
        }

        return addresses.toOwnedSlice(allocator);
    }

    pub fn discover(self: *NetworkDiscovery, callback: *const fn (result: ?DiscoveryResult) void) void {
        _ = self;
        _ = callback;
    }

    pub fn discoverSync(self: *NetworkDiscovery) ?DiscoveryResult {
        for (self.config.subnets) |subnet| {
            var i: u8 = 1;
            while (i < 255) : (i += 1) {
                const ip = std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ subnet, i }) catch continue;
                defer self.allocator.free(ip);

                if (self.probeAddress(ip) catch false) {
                    const url = std.fmt.allocPrint(self.allocator, "http://{s}:{d}", .{ ip, self.config.port }) catch return null;
                    return DiscoveryResult{
                        .url = url,
                        .allocator = self.allocator,
                    };
                }
            }
        }
        return null;
    }
};

test "NetworkDiscovery.init" {
    const discovery = NetworkDiscovery.init(std.testing.allocator, undefined, .{});
    try std.testing.expectEqual(@as(u16, 8000), discovery.config.port);
}

test "NetworkDiscovery.generateIPAddresses" {
    var discovery = NetworkDiscovery.init(std.testing.allocator, undefined, .{
        .subnets = &.{"192.168.1"},
    });

    const addresses = try discovery.generateIPAddresses(std.testing.allocator);
    defer {
        for (addresses) |addr| std.testing.allocator.free(addr);
        std.testing.allocator.free(addresses);
    }

    try std.testing.expectEqual(@as(usize, 254), addresses.len);
    try std.testing.expectEqualStrings("192.168.1.1", addresses[0]);
    try std.testing.expectEqualStrings("192.168.1.254", addresses[253]);
}

test "NetworkDiscovery.generateIPAddresses multiple subnets" {
    var discovery = NetworkDiscovery.init(std.testing.allocator, undefined, .{
        .subnets = &.{ "192.168.1", "10.0.0" },
    });

    const addresses = try discovery.generateIPAddresses(std.testing.allocator);
    defer {
        for (addresses) |addr| std.testing.allocator.free(addr);
        std.testing.allocator.free(addresses);
    }

    try std.testing.expectEqual(@as(usize, 508), addresses.len);
    try std.testing.expectEqualStrings("192.168.1.1", addresses[0]);
    try std.testing.expectEqualStrings("10.0.0.254", addresses[507]);
}

test "DiscoveryConfig defaults" {
    const config = DiscoveryConfig{};
    try std.testing.expectEqual(@as(u16, 8000), config.port);
    try std.testing.expectEqual(@as(u32, 200), config.timeout_ms);
    try std.testing.expectEqual(@as(u8, 32), config.chunk_size);
    try std.testing.expectEqual(@as(u32, 400), config.chunk_wait_ms);
    try std.testing.expectEqual(@as(usize, 3), config.subnets.len);
}

test "DiscoveryConfig custom values" {
    const config = DiscoveryConfig{
        .port = 9000,
        .timeout_ms = 500,
        .chunk_size = 16,
        .chunk_wait_ms = 200,
        .subnets = &.{"192.168.100"},
    };
    try std.testing.expectEqual(@as(u16, 9000), config.port);
    try std.testing.expectEqual(@as(u32, 500), config.timeout_ms);
    try std.testing.expectEqual(@as(u8, 16), config.chunk_size);
    try std.testing.expectEqual(@as(u32, 200), config.chunk_wait_ms);
    try std.testing.expectEqual(@as(usize, 1), config.subnets.len);
}

test "DiscoveryResult deinit" {
    const url = try std.testing.allocator.dupe(u8, "http://192.168.1.100:8000");
    var result = DiscoveryResult{
        .url = url,
        .allocator = std.testing.allocator,
    };
    result.deinit();
}

test "NetworkDiscovery URL formatting" {
    var discovery = NetworkDiscovery.init(std.testing.allocator, undefined, .{
        .port = 8080,
    });

    const ip = "192.168.1.100";
    const expected_url = "http://192.168.1.100:8080";

    const url = try std.fmt.allocPrint(std.testing.allocator, "http://{s}:{d}", .{ ip, discovery.config.port });
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings(expected_url, url);
}

test "NetworkDiscovery IP range bounds" {
    var discovery = NetworkDiscovery.init(std.testing.allocator, undefined, .{
        .subnets = &.{"192.168.1"},
    });

    const addresses = try discovery.generateIPAddresses(std.testing.allocator);
    defer {
        for (addresses) |addr| std.testing.allocator.free(addr);
        std.testing.allocator.free(addresses);
    }

    try std.testing.expectEqual(@as(usize, 254), addresses.len);

    const first = addresses[0];
    try std.testing.expect(std.mem.startsWith(u8, first, "192.168.1."));

    const last = addresses[253];
    try std.testing.expect(std.mem.startsWith(u8, last, "192.168.1."));
}

test "NetworkDiscovery with empty subnet list" {
    var discovery = NetworkDiscovery.init(std.testing.allocator, undefined, .{
        .subnets = &.{},
    });

    const addresses = try discovery.generateIPAddresses(std.testing.allocator);
    defer std.testing.allocator.free(addresses);

    try std.testing.expectEqual(@as(usize, 0), addresses.len);
}
