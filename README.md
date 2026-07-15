# Metanoia

A Bible study software prototype written in **Zig** and **GTK4**, inspired by Logos Bible Software and themed with Tokyo Night.

## Features
- **Tokyo Night Theme:** Deep, modern aesthetic for focused study.
- **Interlinear Support:** Greek-English interlinear view for John 3:16.
- **Multi-Version Support:** NKJV, Greek (NA28 style), and Hebrew (BHS style).
- **Navigation & Search:** Quick access to passages and library.
- **Highlighting:** Integrated text highlighting support.
- **Tabs:** Study multiple passages or versions simultaneously.

## Quick Start

### macOS
```bash
brew install zig gtk4 pango cairo glib sqlite3
zig build run
```

### Windows 11
Open PowerShell **as Administrator** and run:
```pwsh
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
iex (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/4cecoder/metanoia/master/scripts/setup_windows.ps1").Content
```
This installs MSYS2, GTK4, Zig (if missing), and runs `zig build`. See [docs/WINDOWS_SETUP.md](docs/WINDOWS_SETUP.md) for manual steps.

### Linux
```bash
# Debian/Ubuntu
sudo apt install zig gtk4 libgtk-4-dev libsqlite3-dev
zig build run
```

## VS Code (Windows recommended)

1. Install the [Zig extension](vscode:extension/ziglang.vscode-zig)
2. Press `Ctrl+Shift+B` to build
3. Press `F5` to run

Pre-configured `.vscode/tasks.json` and `.vscode/launch.json` included.

## Requirements
- **Zig** 0.17+ ([download](https://ziglang.org/download/))
- **GTK4** development libraries
- **TTS (optional):** Python 3.12+ with `uv` — see `tools/tts_server.py`

## Repository Hygiene & Workflow
To keep the repository lightweight and clean:
- **Large Files:** Databases (`*.db`), model weights (`*.onnx`, `*.bin`), and audio files (`*.wav`) are **ignored** by Git.
- **Auto-Reloading TTS Server:** Use `uv run python tools/tts_server.py` to start the TTS server. It will automatically poll for updates from the `master` branch and reload itself when changes are detected.
  - *Note for Linux/WSL:* If you see CUDA version mismatches, run `uv sync` to align Torch and TorchAudio.
- **Mobile Development:** See `mobile/README.md` for instructions on placing model assets and hardware optimization for the Pixel 9 Pro.

## Helpful Hints for AI-Assisted Development
- **Reproduction Scripts:** Use the `tools/` directory for Python-based research and verification.
- **Database Schema:** Most application data is stored in `data/bible.db` (local only). If the schema changes, update the Zig struct definitions in `src/bible_db.zig`.
- **Architecture Docs:** See `docs/` for kit module API, signal safety, and Zig gotchas.

## Project Structure
```
src/
├── kit/          # Reusable UI/UX component library (GTK4)
│   ├── ffi.zig   # Raw GTK4/GLib FFI bindings
│   ├── widget.zig # Type-safe widget wrappers
│   ├── signal.zig # Compile-time signal type safety
│   └── components/ # StatusBar, Search, Dialog, FlowPicker, etc.
├── main.zig      # Application entry point
├── services/     # TTS engine, LLM client, network discovery
└── models/       # Config, app state
docs/             # Architecture docs (subagent-assigned)
```
