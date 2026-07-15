# Windows 11 Development Setup

Steps to build and run Metanoia on Windows 11 with Zig + MSYS2.

## Overview

This project uses GTK4, which on Windows requires the [MSYS2](https://www.msys2.org/) environment. The build system (`build.zig`) handles Windows-specific configuration: it sets `subsystem = .Windows` to hide the terminal window, and adds fallback library paths for MSYS2.

## Step 1: Install Zig

1. Download the latest Zig from [ziglang.org/download](https://ziglang.org/download/) (0.17+).
2. Add the `zig` binary to your system `PATH`.

## Step 2: Install MSYS2 + GTK4

1. Download and run the [MSYS2 installer](https://www.msys2.org/).
2. Open the **UCRT64** terminal (search "UCRT64" in Start Menu — do NOT use MSYS2 or MINGW64).
3. Update packages and install GTK4:

```pwsh
pacman -Syu
pacman -S --needed mingw-w64-ucrt-x86_64-gtk4 mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-sqlite3 mingw-w64-ucrt-x86_64-curl
```

4. Add MSYS2's UCRT64 `bin` to your system `PATH` (System Properties → Environment Variables):

```
C:\msys64\ucrt64\bin
```

5. Verify:

```pwsh
pkg-config --modversion gtk4
# Should print: 4.x.x
```

> **Why UCRT64?** MSYS2 now defaults to the UCRT (Universal C Runtime) environment. The older MINGW64 environment may work but UCRT64 is the recommended path forward. Package prefix: `mingw-w64-ucrt-x86_64-*`.

## Step 3: Build

Open a **regular** PowerShell or Command Prompt (not MSYS2) and run:

```pwsh
zig build
```

Zig finds GTK4 via `pkg-config` on the system PATH. If `pkg-config` is not found, the build will fail with "unable to find Dynamic system library 'gtk-4'". Make sure `C:\msys64\ucrt64\bin` is in your PATH and re-check with `where pkg-config`.

### Building in MSYS2 shell (fallback)

If the regular terminal fails, try building inside the UCRT64 shell:

```bash
zig build -Dtarget=x86_64-windows-gnu
```

## Step 4: Run

```pwsh
zig build run
```

## Known Windows issues

### pkg-config not found (Zig crash)

Zig's `linkSystemLibrary("gtk4")` invokes `pkg-config`. If it's not on PATH, Zig can crash (https://github.com/ziglang/zig/issues/14341 — still open).

**Fix:** Ensure `C:\msys64\ucrt64\bin` is on your system PATH. Restart PowerShell after changing PATH. Verify with `where pkg-config`.

### Library file extensions: `.dll.a` vs `.a`

MSYS2 provides import libraries with `.dll.a` extension. Zig's linker (`lld`) may expect `.a`. If you get linker errors like "cannot find -lgtk-4", the build.zig adds fallback library paths:

```
C:\msys64\ucrt64\lib
C:\msys64\mingw64\lib
```

These paths are added automatically when building for Windows (`target.result.os.tag == .windows`).

### Terminal window appears on launch

The `build.zig` sets `exe.subsystem = .Windows` for Windows targets, which suppresses the console window. If you want console output during development, remove that line from `build.zig`.

### Undefined symbols (libffi, ws2_32, etc.)

If you get linker errors about `ffi_prep_cif`, `WSAStartup`, or similar, you may need to link additional Windows system libraries. The GTK4 dependency chain on Windows requires:

- `libffi` — for GObject closures
- `ws2_32` — for GIO networking
- `ole32`, `shell32`, `uuid` — for Windows COM integration
- `libiconv` — for text conversion

These are typically resolved automatically when `linkSystemLibrary("gtk4")` finds the correct pkg-config flags. If pkg-config is missing, you'll need to add them manually:

```zig
if (target.result.os.tag == .windows) {
    exe.root_module.linkSystemLibrary("libffi", .{});
    exe.link_libc = true;
    // -lws2_32 -lole32 -lshell32 -luuid are usually auto-linked
}
```

## Distribution

To distribute the app to users without MSYS2:

1. Run `zig build -Doptimize=ReleaseSafe`
2. Copy `zig-out/bin/metanoia.exe` to a folder
3. Copy all DLLs from `C:\msys64\ucrt64\bin/` that the executable depends on:

```pwsh
# List dependencies:
ldd zig-out/bin/metanoia.exe
# Copy them:
Copy-Item C:\msys64\ucrt64\bin\*.dll .\dist\
```

4. Distribute the folder. Users need no GTK installation — only the DLLs.
5. Optional: use [NSIS](https://nsis.sourceforge.io/) to create an installer.
