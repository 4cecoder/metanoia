const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Native AI backends (aikit — TTS/LLM/STT) are opt-in, off by default.
    // aikit unconditionally links against qwentts.cpp (libqwen) for its TTS
    // backend, and on macOS also mlx-c and (if the STT capability is
    // reached) whisper.cpp — all real, heavy, locally-built/installed
    // native dependencies (see aikit/README.md) that a fresh checkout,
    // and CI (.github/workflows/test.yml), do NOT have. Every native
    // capability already defaults to "remote"/off at the *runtime config*
    // level (tts_backend/llm_backend default to "remote" — see
    // src/tts_client.zig / src/llm_client.zig), but that's meaningless if
    // the app can't even *compile* without those dependencies present.
    // This flag is the actual off switch: default false means `zig build`
    // / `zig build test` work with nothing beyond the README's normal
    // `brew install zig gtk4 pango cairo glib sqlite3`. Pass
    // `-Dnative-ai=true` (after building aikit's dependencies per
    // aikit/README.md) to link the real thing in.
    const native_ai = b.option(
        bool,
        "native-ai",
        "Link aikit's native TTS/LLM/STT backends (requires qwentts.cpp/mlx-c/whisper-cpp set up locally, see aikit/README.md). Off by default so a fresh checkout builds with nothing beyond gtk4/sqlite3.",
    ) orelse false;

    const native_ai_opts = b.addOptions();
    native_ai_opts.addOption(bool, "native_ai", native_ai);
    const build_options_mod = native_ai_opts.createModule();

    // aikit's own build.zig defaults its "qwen-build-dir" option to
    // "../vendor/qwentts.cpp/build", a `.cwd_relative` path meant to be
    // resolved from *aikit's own* directory (i.e. running `zig build` from
    // within aikit/). Here we're pulling aikit in as a dependency of
    // metanoia's root build, so `zig build` is invoked from the metanoia
    // repo root instead — the same relative default would resolve one
    // directory too high. Override it to the correct path from *this*
    // root: vendor/qwentts.cpp/build (no "..").
    const aikit_mod: ?*std.Build.Module = if (native_ai) blk: {
        const aikit_dep = b.dependency("aikit", .{
            .target = target,
            .optimize = optimize,
            .@"qwen-build-dir" = @as([]const u8, "vendor/qwentts.cpp/build"),
        });
        break :blk aikit_dep.module("aikit");
    } else null;

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    // src/tts_client.zig / src/llm_client.zig (reachable from src/root.zig)
    // import "aikit" and "build_options" for the native backend switch —
    // "aikit" is only added when native_ai is true (see aikit_mod above);
    // both files comptime-gate their own `@import("aikit")` on
    // `build_options.native_ai`, so it's fine for that import to simply not
    // exist otherwise.
    var mod_imports = std.ArrayListUnmanaged(std.Build.Module.Import).empty;
    mod_imports.append(b.allocator, .{ .name = "build_options", .module = build_options_mod }) catch @panic("OOM");
    if (aikit_mod) |am| mod_imports.append(b.allocator, .{ .name = "aikit", .module = am }) catch @panic("OOM");

    const mod = b.addModule("metanoia", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
        .imports = mod_imports.items,
    });

    // Kit module — reusable, decoupled UI/UX component library.
    const kit_mod = b.addModule("kit", .{
        .root_source_file = b.path("src/kit/root.zig"),
        .target = target,
    });

    // `mod` re-exports bible_db.zig (see src/root.zig), whose tests exercise
    // real SQLite calls (in-memory db round trips) — it needs the same
    // sqlite3/libc link as the exe below so `zig build test` can actually
    // run them, not just the exe-linked test target.
    const mod_gtk_lib = if (target.result.os.tag == .windows) "gtk-4" else "gtk4";
    mod.linkSystemLibrary(mod_gtk_lib, .{});
    mod.linkSystemLibrary("sqlite3", .{});
    mod.link_libc = true;

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    // src/main.zig also imports src/tts_client.zig directly (relative
    // import, separate from the "metanoia" module above), so it needs its
    // own "aikit"/"build_options" imports too — same conditional-inclusion
    // reasoning as mod_imports above.
    var exe_imports = std.ArrayListUnmanaged(std.Build.Module.Import).empty;
    exe_imports.append(b.allocator, .{ .name = "metanoia", .module = mod }) catch @panic("OOM");
    exe_imports.append(b.allocator, .{ .name = "kit", .module = kit_mod }) catch @panic("OOM");
    exe_imports.append(b.allocator, .{ .name = "build_options", .module = build_options_mod }) catch @panic("OOM");
    if (aikit_mod) |am| exe_imports.append(b.allocator, .{ .name = "aikit", .module = am }) catch @panic("OOM");

    const exe = b.addExecutable(.{
        .name = "metanoia",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = exe_imports.items,
        }),
    });
    // GTK4 library name differs between platforms:
    // - macOS Homebrew: gtk4.pc  → linkSystemLibrary("gtk4")
    // - Windows MSYS2:  gtk-4.pc → linkSystemLibrary("gtk-4")
    // - Linux apt:      gtk4.pc  → linkSystemLibrary("gtk4")
    const gtk_lib = if (target.result.os.tag == .windows) "gtk-4" else "gtk4";
    exe.root_module.linkSystemLibrary(gtk_lib, .{});
    exe.root_module.linkSystemLibrary("sqlite3", .{});
    exe.root_module.link_libc = true;

    // Windows-specific: hide terminal window, add MSYS2 search paths
    if (target.result.os.tag == .windows) {
        exe.subsystem = .Windows;
        // MSYS2 does NOT always live at "C:\msys64". The msys2/setup-msys2
        // GitHub Action's default config (release: true, no `location`
        // override — what this repo's CI workflows use) does a *fresh*
        // install under "${RUNNER_TEMP}\msys64" (e.g. "D:\a\_temp\msys64"
        // on GitHub-hosted Windows runners), not the conventional
        // "C:\msys64" a manual/local install or `release: false` (reuse the
        // runner image's preinstalled MSYS2) would use. Confirmed from the
        // actual failing run (29959022548 / job 89055266406): its "Setup
        // MSYS2" step invoked "D:\a\_temp\setup-msys2\msys2.cmd", i.e. the
        // real install root that run, was NOT "C:\msys64" — so these
        // hardcoded paths never pointed at real files, regardless of what
        // ci/fix-msys2-libs.sh renamed on disk.
        //
        // CI passes the setup-msys2 action's own `msys2-location` output
        // through as the MSYS2_ROOT env var (see .github/workflows/
        // release-latest.yml and release.yml's build-windows jobs) so we
        // search the *actual* install location. "C:\msys64" is kept as a
        // fallback for local dev machines with a real system-wide MSYS2
        // install at that conventional path (and as a last-ditch guess if
        // MSYS2_ROOT isn't set for some reason) — the previous
        // ".\cache\msys64\ucrt64\lib" entry is dropped: git blame traces it
        // to an earlier local-dev workflow (commit a5086d0, "MSYS2 installs
        // to .cache/msys64 — nothing outside project folder") that doesn't
        // reflect how CI actually installs MSYS2 today; it never resolved
        // in CI (Zig only ever warned "unable to open library directory"
        // for it) and isn't referenced anywhere else in the repo.
        const msys2_root = b.graph.environ_map.get("MSYS2_ROOT") orelse "C:\\msys64";
        const msys_libs = [_][]const u8{
            b.fmt("{s}\\ucrt64\\lib", .{msys2_root}),
            b.fmt("{s}\\mingw64\\lib", .{msys2_root}),
            "C:\\msys64\\ucrt64\\lib",
            "C:\\msys64\\mingw64\\lib",
        };
        for (msys_libs) |p| exe.root_module.addLibraryPath(.{ .cwd_relative = p });

        // On macOS/Linux, linkSystemLibrary("gtk4") resolves via pkg-config,
        // which follows gtk4.pc's own `Requires: glib-2.0 gobject-2.0 gio-2.0`
        // chain automatically. On Windows, the MSYS2 package's pkg-config
        // name is "gtk4" (no hyphen) while this file links it as "gtk-4"
        // (matching the actual import-lib filename, not the pkg-config
        // name — see the comment above linking gtk_lib), so pkg-config
        // lookup fails by name and Zig falls back to its naive
        // 'paths_first' file-search strategy, which just finds gtk-4's own
        // library file and never follows any dependency chain. Confirmed
        // from a real CI run (29974557481): the exe compiled and gtk-4/
        // sqlite3 both linked fine, but 14 core GLib/GObject/GIO symbols
        // (g_signal_connect_data, g_thread_new, g_object_unref,
        // g_application_run, g_menu_new, etc.) were undefined at link time.
        // Link them explicitly here since Windows can't discover them
        // transitively the way macOS/Linux do.
        exe.root_module.linkSystemLibrary("gio-2.0", .{});
        exe.root_module.linkSystemLibrary("gobject-2.0", .{});
        exe.root_module.linkSystemLibrary("glib-2.0", .{});

        // With that in place, the same naive-linking gap reappeared one
        // layer down: MSYS2's static archives for glib/gobject/gio each
        // pull in their OWN C-level dependencies, which pkg-config's static
        // expansion normally supplies but our explicit -l list doesn't.
        // Confirmed from a real CI run (29974956210) with the exact
        // complete set of ~104 undefined symbols this time (not a guess —
        // every library below maps to specific symbols actually reported):
        //   ffi_call, ffi_prep_cif, ffi_type_*        -> libffi (GObject's
        //     closure/signal marshaling, gclosure.c)
        //   g_module_*                                 -> gmodule-2.0
        //   inflate, inflateEnd, inflateInit_, etc.     -> zlib
        //   pcre2_*_8                                   -> pcre2-8 (GRegex)
        //   libiconv, libiconv_open                      -> iconv
        //   accept/bind/socket/WSA*/htonl/inet_*/etc.    -> ws2_32 (Winsock,
        //     GIO's GSocket backend on Windows)
        //   CoCreateInstance/CoInitializeEx/CoTaskMemAlloc/etc. -> ole32
        //   SHLoadIndirectString, StrRetToStrW           -> shlwapi
        //   GetAdaptersAddresses, GetIpForwardTable2,
        //     NotifyRouteChange2, CancelMibChangeNotify2,
        //     if_nametoindex                              -> iphlpapi (GIO's
        //     network-monitor backend)
        //   DnsFree, DnsQuery_UTF8                        -> dnsapi (GIO's
        //     resolver backend)
        exe.root_module.linkSystemLibrary("gmodule-2.0", .{});
        exe.root_module.linkSystemLibrary("ffi", .{});
        exe.root_module.linkSystemLibrary("z", .{});
        exe.root_module.linkSystemLibrary("pcre2-8", .{});
        exe.root_module.linkSystemLibrary("iconv", .{});
        exe.root_module.linkSystemLibrary("ws2_32", .{});
        exe.root_module.linkSystemLibrary("ole32", .{});
        exe.root_module.linkSystemLibrary("shlwapi", .{});
        exe.root_module.linkSystemLibrary("iphlpapi", .{});
        exe.root_module.linkSystemLibrary("dnsapi", .{});
    }

    // macOS .app bundle (only on macOS)
    if (target.result.os.tag == .macos) {
        const app_step = b.step("app", "Create Metanoia.app bundle");
        const create_app = b.addSystemCommand(&.{
            "/bin/bash", "scripts/create_app_bundle.sh",
        });
        create_app.step.dependOn(b.getInstallStep());
        app_step.dependOn(&create_app.step);
    }

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());



    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // Kit module tests.
    const kit_tests = b.addTest(.{
        .root_module = kit_mod,
    });

    // Build config tests (cross-target validation).
    const build_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/build_test.zig"),
        .target = target,
    });
    const build_test = b.addTest(.{
        .root_module = build_test_mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Run kit tests.
    const run_kit_tests = b.addRunArtifact(kit_tests);

    // Run build config tests.
    const run_build_tests = b.addRunArtifact(build_test);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_kit_tests.step);
    test_step.dependOn(&run_build_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Real end-to-end native-TTS/native-LLM tests — only meaningful (and
    // only buildable at all, since they need "aikit") when native_ai is
    // true. When it's not, `zig build test-native-tts`/`test-native-llm`
    // simply don't exist as steps ("no step named ..." is a clear enough
    // signal — pass -Dnative-ai=true to get them). Separate from the
    // default `test` step even when native_ai is true: they need real
    // multi-hundred-MB model weights under vendor/ (see
    // src/native_tts_test.zig / src/native_llm_test.zig for exact paths),
    // which most checkouts — even native-ai-enabled ones — won't have set
    // up; they self-skip via error.SkipZigTest when absent, but keeping
    // them out of the default `test` step avoids paying their real
    // model-load-and-generate cost on every routine `zig build test` for
    // contributors who do have the weights.
    if (native_ai) {
        var native_test_imports = std.ArrayListUnmanaged(std.Build.Module.Import).empty;
        native_test_imports.append(b.allocator, .{ .name = "aikit", .module = aikit_mod.? }) catch @panic("OOM");
        native_test_imports.append(b.allocator, .{ .name = "build_options", .module = build_options_mod }) catch @panic("OOM");

        const native_tts_test_mod = b.createModule(.{
            .root_source_file = b.path("src/native_tts_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = native_test_imports.items,
        });
        const native_tts_test = b.addTest(.{ .root_module = native_tts_test_mod });
        native_tts_test.root_module.linkSystemLibrary(gtk_lib, .{});
        native_tts_test.root_module.linkSystemLibrary("sqlite3", .{});
        native_tts_test.root_module.link_libc = true;
        const run_native_tts_test = b.addRunArtifact(native_tts_test);
        const native_tts_test_step = b.step("test-native-tts", "Run the real native-TTS end-to-end test (needs local GGUF weights)");
        native_tts_test_step.dependOn(&run_native_tts_test.step);

        const native_llm_test_mod = b.createModule(.{
            .root_source_file = b.path("src/native_llm_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = native_test_imports.items,
        });
        const native_llm_test = b.addTest(.{ .root_module = native_llm_test_mod });
        native_llm_test.root_module.link_libc = true;
        const run_native_llm_test = b.addRunArtifact(native_llm_test);
        const native_llm_test_step = b.step("test-native-llm", "Run the real native-LLM end-to-end test (needs local MLX checkpoint)");
        native_llm_test_step.dependOn(&run_native_llm_test.step);
    }

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
