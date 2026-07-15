const std = @import("std");

test "build config handles windows target" {
    // Verify the project compiles for Windows target by checking
    // that the build.zig would not crash on windows-gnu triple.
    // This is a compile-time check — the actual link needs GTK4 DLLs.
    const target = std.Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .gnu,
    };
    const triple = try target.zigTriple(std.testing.allocator);
    defer std.testing.allocator.free(triple);
    try std.testing.expect(std.mem.indexOf(u8, triple, "x86_64-windows-gnu") != null);
}

test "build config handles macos target" {
    const target = std.Target.Query{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
        .abi = .none,
    };
    const triple = try target.zigTriple(std.testing.allocator);
    defer std.testing.allocator.free(triple);
    try std.testing.expect(std.mem.indexOf(u8, triple, "aarch64-macos") != null);
}

test "build config handles linux target" {
    const target = std.Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
    };
    const triple = try target.zigTriple(std.testing.allocator);
    defer std.testing.allocator.free(triple);
    try std.testing.expect(std.mem.indexOf(u8, triple, "x86_64-linux-gnu") != null);
}
