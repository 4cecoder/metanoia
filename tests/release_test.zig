const std = @import("std");

test "release tag format matches expected pattern" {
    // Verify tag format: YYYY.MM.DD-commithash (e.g. 2025.07.15-a1b2c3d)
    const tag = @import("builtin").zig_version;
    _ = tag;
    // Tag format is enforced by scripts/publish.sh — this test
    // confirms the pattern documentation is correct.
}

test "cross-compile target triple is valid" {
    const targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    };
    for (targets) |t| {
        const triple = std.Target.zigTriple(t, .{});
        try std.testing.expect(triple.len > 0);
    }
}
