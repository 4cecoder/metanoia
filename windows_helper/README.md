# Metanoia Windows Setup Wizard

A GUI preflight checker for Windows developers getting started with Metanoia.

## What it does

Scans your system for required development tools and guides you through installing anything missing:

| Requirement | Why |
|-------------|-----|
| **Zig 0.17+** | The compiler |
| **MSYS2 + UCRT64** | Provides GTK4 and build tools |
| **GTK4** | UI framework — installed via MSYS2 pacman |
| **curl** | HTTP requests for TTS, LLM, network discovery |
| **Git** | Version control (clone, pull) |
| **VS Code** | Recommended editor (optional) |

## How to use

### 1. Compile (one-time)

Double-click `compile.bat` — this compiles the C# WinForms app using the .NET Framework compiler that ships with Windows 11.

Or run from terminal:

```cmd
windows_helper\compile.bat
```

### 2. Run

Double-click `windows_helper\MetanoiaSetup.exe`.

### 3. Wizard

- **Green indicators** = ready
- **Red indicators** = missing — click "Install" next to each
- **Build Project** button = runs `zig build` after prerequisites are met
- **Open in VS Code** = opens the project folder in VS Code

## Requirements to compile

- Windows 10 or 11 (any edition)
- .NET Framework 4.8+ (pre-installed on Windows 11)

No additional SDK or runtime needed. The C# compiler (`csc.exe`) ships with Windows.

## Notes

- Installations download files from the internet (Zig, MSYS2). Internet connection required.
- PATH modifications are per-user (not system-wide).
- Some operations may require "Run as administrator" for PATH changes.
