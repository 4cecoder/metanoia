# Windows 11 Development Setup

Minimal steps for a Windows developer to build and run this project.

## Prerequisites

- Windows 11 (or 10)
- [Zig (0.17 or later)](https://ziglang.org/download/) — install and add to PATH

## Step 1: Install MSYS2 + GTK4

1. Download the [MSYS2 installer](https://www.msys2.org/) and run it.
2. Open the **UCRT64** terminal (not MSYS2, not MINGW64).
3. Run:
   ```pwsh
   pacman -Syu          # update package DB
   pacman -S --needed mingw-w64-ucrt-x86_64-gtk4 mingw-w64-ucrt-x86_64-pkg-config
   ```
4. Add to your **system** `PATH`:
   ```
   C:\msys64\ucrt64\bin
   ```
   (Verify: `pkg-config --modversion gtk4` should print a version.)

## Step 2: Build

Open a **regular** PowerShell or Command Prompt (not MSYS2) and run:

```pwsh
zig build
```

Zig will find GTK4 via the system PATH automatically. If Zig complains about missing libraries, try building inside the UCRT64 shell:

```bash
zig build -Dtarget=x86_64-windows-gnu
```

## Step 3: Run

```pwsh
zig build run
```

## Notes

- **No manual symlinks or `.dll.a` → `.a` renaming needed** with modern Zig + UCRT64 packages.
- **No extra VC++ redistributable required** — MSYS2/MinGW provides its own CRT.
- **Bundling for distribution:** Copy the `.exe` from `zig-out/bin/` plus all DLLs from `C:\msys64\ucrt64\bin/` into a folder. Use [NSIS](https://nsis.sourceforge.io/) or [WiX](https://wixtoolset.org/) to create an installer.
- **Subsystem flag:** To suppress the terminal window on launch, add `exe.subsystem = .Windows;` in `build.zig` (Windows-only builds).
- **First build may be slow** — GTK4 has many headers. Subsequent builds are cached.
