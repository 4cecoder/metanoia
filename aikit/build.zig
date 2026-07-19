const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Where qwentts.cpp was built (see README.md "Native backend"):
    //   git clone --recurse-submodules https://github.com/ServeurpersoCom/qwentts.cpp.git
    //   cd qwentts.cpp && mkdir build && cd build
    //   cmake .. -DCMAKE_BUILD_TYPE=Release -DQWEN_SHARED=ON && cmake --build .
    // This produces libqwen.{dylib,so,dll} plus its ggml/Metal .dylib
    // dependencies (libggml*.dylib) all in that same build/ directory.
    // Default assumes qwentts.cpp lives as a sibling of this worktree's
    // aikit/ under vendor/ (i.e. `<worktree>/vendor/qwentts.cpp/build`),
    // resolved relative to wherever `zig build` is invoked from (expected:
    // from within aikit/, so "../vendor/qwentts.cpp/build" reaches it).
    // Override with `-Dqwen-build-dir=<path>` if built elsewhere.
    const qwen_build_dir = b.option(
        []const u8,
        "qwen-build-dir",
        "Path to qwentts.cpp's CMake build directory (contains libqwen.{dylib,so,dll})",
    ) orelse "../vendor/qwentts.cpp/build";

    const mod = b.addModule("aikit", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    linkQwen(mod, qwen_build_dir);
    if (target.result.os.tag == .macos) linkMlx(mod);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run aikit tests");
    test_step.dependOn(&run_tests.step);

    // Runnable example: loads the Qwen3-TTS Base checkpoint, synthesizes a
    // short test line using the "tommy" reference clip (ICL voice cloning)
    // if available, and writes a .wav under examples/output/. See
    // examples/tommy_test.zig.
    const example_exe = b.addExecutable(.{
        .name = "tommy_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/tommy_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aikit", .module = mod },
            },
        }),
    });
    linkQwen(example_exe.root_module, qwen_build_dir);
    if (target.result.os.tag == .macos) linkMlx(example_exe.root_module);

    const run_example = b.addRunArtifact(example_exe);
    run_example.step.dependOn(b.getInstallStep());
    const run_example_step = b.step("run-example", "Build and run examples/tommy_test.zig");
    run_example_step.dependOn(&run_example.step);

    b.installArtifact(example_exe);

    // Research-only spike (see docs/ or the LLM-feasibility report): loads
    // real MLX-format safetensors weights and runs a real dequantize +
    // matmul against them. Not part of the public API — proof-of-feasibility
    // only, macOS/MLX only.
    if (target.result.os.tag == .macos) {
        const spike_model_path = b.option(
            []const u8,
            "llm-spike-model",
            "Path to a .safetensors file for examples/llm_spike.zig",
        ) orelse "";
        const spike_options = b.addOptions();
        spike_options.addOption([]const u8, "model_path", spike_model_path);

        const llm_spike_exe = b.addExecutable(.{
            .name = "llm_spike",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/llm_spike.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "aikit", .module = mod },
                },
            }),
        });
        llm_spike_exe.root_module.addOptions("build_options", spike_options);
        linkMlx(llm_spike_exe.root_module);
        const run_llm_spike = b.addRunArtifact(llm_spike_exe);
        run_llm_spike.step.dependOn(b.getInstallStep());
        const run_llm_spike_step = b.step("run-llm-spike", "Build and run examples/llm_spike.zig");
        run_llm_spike_step.dependOn(&run_llm_spike.step);
        b.installArtifact(llm_spike_exe);
    }
}

/// Same external-dependency pattern metanoia's own build.zig already uses
/// for gtk4/sqlite3 (linkSystemLibrary + link_libc). `dir` is added both
/// as a link-time library search path (so the linker finds
/// libqwen.{dylib,so,dll}) and as a runtime rpath (so the resulting
/// binary finds libqwen.dylib *and* the ggml/Metal .dylibs it depends on
/// at load time — qwentts.cpp's CMake build links those with
/// `@rpath/libggml*.dylib` on macOS, not absolute paths).
fn linkQwen(mod: *std.Build.Module, dir: []const u8) void {
    mod.addLibraryPath(.{ .cwd_relative = dir });
    mod.addRPath(.{ .cwd_relative = dir });
    mod.linkSystemLibrary("qwen", .{});
    mod.link_libc = true;
}

/// Links src/backend/mlx.zig's dependencies — macOS only (see that file's
/// comptime guard). `mlx-c` is expected via Homebrew (`brew install mlx-c`;
/// confirmed present in this environment: 0.6.0_3, headers/libs under
/// /opt/homebrew). Same pattern proven in the user's cosmic project
/// (src/platform/macos/mlx.zig + build.zig's linkSystemFrameworks).
fn linkMlx(mod: *std.Build.Module) void {
    mod.linkFramework("Metal", .{});
    mod.linkFramework("MetalKit", .{});
    mod.linkFramework("Foundation", .{});
    mod.linkFramework("QuartzCore", .{});
    mod.linkFramework("CoreGraphics", .{});
    mod.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    mod.linkSystemLibrary("mlxc", .{});
    mod.link_libc = true;
}
