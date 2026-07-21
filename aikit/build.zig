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
    if (target.result.os.tag == .macos) {
        linkMlx(mod);
        linkWhisper(mod);
    }

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

        // Phase 1: the real per-layer Qwen2 forward pass (src/models/qwen2_mlx.zig),
        // exercised end to end against a real checkpoint dir (tokenizer.json +
        // model.safetensors). See examples/llm_forward_pass.zig.
        const forward_model_dir = b.option(
            []const u8,
            "llm-model-dir",
            "Directory containing tokenizer.json + model.safetensors, for examples/llm_forward_pass.zig",
        ) orelse "";
        const forward_options = b.addOptions();
        forward_options.addOption([]const u8, "model_dir", forward_model_dir);

        const llm_forward_exe = b.addExecutable(.{
            .name = "llm_forward_pass",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/llm_forward_pass.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "aikit", .module = mod },
                },
            }),
        });
        llm_forward_exe.root_module.addOptions("build_options", forward_options);
        linkMlx(llm_forward_exe.root_module);
        const run_llm_forward = b.addRunArtifact(llm_forward_exe);
        run_llm_forward.step.dependOn(b.getInstallStep());
        const run_llm_forward_step = b.step("run-llm-forward-pass", "Build and run examples/llm_forward_pass.zig");
        run_llm_forward_step.dependOn(&run_llm_forward.step);
        b.installArtifact(llm_forward_exe);

        // Phase 2: KV-cache-based multi-token autoregressive generation
        // (Model.generate), exercised end to end against a real checkpoint
        // dir and checked against the same Python mlx_lm reference oracle
        // as the forward-pass example. Reuses the same "llm-model-dir"
        // option as run-llm-forward-pass above.
        const generate_options = b.addOptions();
        generate_options.addOption([]const u8, "model_dir", forward_model_dir);

        const llm_generate_exe = b.addExecutable(.{
            .name = "llm_generate",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/llm_generate.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "aikit", .module = mod },
                },
            }),
        });
        llm_generate_exe.root_module.addOptions("build_options", generate_options);
        linkMlx(llm_generate_exe.root_module);
        const run_llm_generate = b.addRunArtifact(llm_generate_exe);
        run_llm_generate.step.dependOn(b.getInstallStep());
        const run_llm_generate_step = b.step("run-llm-generate", "Build and run examples/llm_generate.zig (KV-cache multi-token generation)");
        run_llm_generate_step.dependOn(&run_llm_generate.step);
        b.installArtifact(llm_generate_exe);

        // STT Phase 0/1: whisper.cpp-backed real transcription (see
        // backend/whisper.zig / models/whisper_stt.zig doc comments), run
        // end to end against a real ggml-*.bin checkpoint and a real WAV
        // file. Not part of any "generation" phasing like the LLM's —
        // this is the whole capability in one pass, since whisper.cpp
        // already implements the full model (no per-layer port needed,
        // unlike the LLM's clean-room MLX build).
        const stt_model_path = b.option(
            []const u8,
            "stt-model",
            "Path to a ggml-*.bin Whisper checkpoint for examples/stt_transcribe.zig",
        ) orelse "../vendor/whisper.cpp/models/ggml-tiny.en.bin";
        const stt_audio_path = b.option(
            []const u8,
            "stt-audio",
            "Path to a WAV file to transcribe, for examples/stt_transcribe.zig",
        ) orelse "../data/tommy.wav";
        const stt_options = b.addOptions();
        stt_options.addOption([]const u8, "model_path", stt_model_path);
        stt_options.addOption([]const u8, "audio_path", stt_audio_path);

        const stt_exe = b.addExecutable(.{
            .name = "stt_transcribe",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/stt_transcribe.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "aikit", .module = mod },
                },
            }),
        });
        stt_exe.root_module.addOptions("build_options", stt_options);
        linkWhisper(stt_exe.root_module);
        const run_stt = b.addRunArtifact(stt_exe);
        run_stt.step.dependOn(b.getInstallStep());
        const run_stt_step = b.step("run-stt-transcribe", "Build and run examples/stt_transcribe.zig (real whisper.cpp transcription)");
        run_stt_step.dependOn(&run_stt.step);
        b.installArtifact(stt_exe);
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

/// Links src/backend/whisper.zig's dependency — macOS only for now (see
/// that file's comptime guard; whisper.cpp itself is cross-platform, but
/// this binding hasn't been pointed at a non-Homebrew build layout yet —
/// see backend/whisper.zig's doc comment for the honest scope note).
/// `whisper-cpp` is expected via Homebrew (`brew install whisper-cpp`;
/// confirmed present in this environment: 1.9.1, headers/dylibs under
/// /opt/homebrew/opt/whisper-cpp). Same direct-Homebrew-path pattern as
/// `linkMlx` above (mlx-c is also Homebrew-installed, unlike qwentts.cpp's
/// own hand-built `vendor/` tree).
///
/// Explicitly links (and rpaths) the separate `ggml` Homebrew formula
/// too, not just `whisper-cpp` — found the hard way: linking only
/// `-lwhisper` builds and runs, but crashes
/// (`GGML_ASSERT(device) failed` inside `make_buft_list`, "devices = 0,
/// backends = 0") the moment `whisper_init_from_file_with_params` runs.
/// ggml's `ggml_backend_load_all()` (which `models/whisper_stt.zig` calls
/// before init — see that file) dynamically `dlopen`s its actual
/// CPU/Metal backend implementations from `/opt/homebrew/Cellar/ggml/*/libexec/*.so`
/// (confirmed by directly inspecting that directory — Homebrew's ggml
/// ships backends as separate plugin objects, not statically linked into
/// libggml itself), and that discovery only succeeds when `ggml`'s own
/// lib dir is in this binary's rpath, not just whisper-cpp's — reproduced
/// and fixed via a standalone `zig build-exe` test with explicit
/// `-L/-rpath /opt/homebrew/opt/ggml/lib` before landing this fix here.
fn linkWhisper(mod: *std.Build.Module) void {
    mod.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/whisper-cpp/include" });
    mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/whisper-cpp/lib" });
    mod.addRPath(.{ .cwd_relative = "/opt/homebrew/opt/whisper-cpp/lib" });
    mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/ggml/lib" });
    mod.addRPath(.{ .cwd_relative = "/opt/homebrew/opt/ggml/lib" });
    // linkSystemLibrary("whisper", .{}) already pulls in -lggml/-lggml-base
    // transitively (Zig auto-discovers whisper.pc's pkg-config Libs line,
    // which lists them) — declaring them again here would duplicate-link
    // the same dylib and dyld aborts on that at process start. Only the
    // extra library path/rpath above (for ggml_backend_load_all's plugin
    // discovery, see this function's doc comment) were actually missing.
    mod.linkSystemLibrary("whisper", .{});
    mod.link_libc = true;
}
