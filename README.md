# Metanoia

A Bible study software prototype written in Zig and GTK4, inspired by Logos Bible Software and themed with Tokyo Night.

## Features
- **Tokyo Night Theme:** Deep, modern aesthetic for focused study.
- **Interlinear Support:** Greek-English interlinear view for John 3:16.
- **Multi-Version Support:** NKJV, Greek (NA28 style), and Hebrew (BHS style).
- **Navigation & Search:** Quick access to passages and library.
- **Highlighting:** Integrated text highlighting support.
- **Tabs:** Study multiple passages or versions simultaneously.

## Requirements
- Zig (tested with 0.16.0-dev)
- GTK4 development libraries

## Repository Hygiene & Workflow
To keep the repository lightweight and clean:
- **Large Files:** Databases (`*.db`), model weights (`*.onnx`, `*.bin`), and audio files (`*.wav`) are **ignored** by Git.
- **Auto-Reloading TTS Server:** Use `uv run python tools/tts_server.py` to start the TTS server. It will automatically poll for updates from the `master` branch and reload itself when changes are detected.
- **Mobile Development:** See `mobile/README.md` for instructions on placing model assets and hardware optimization for the Pixel 9 Pro.

## Helpful Hints for Gemini CLI Users
This project is optimized for AI-assisted development:
- **Reproduction Scripts:** Use the `tools/` directory for Python-based research and verification.
- **Database Schema:** Most application data is stored in `data/bible.db` (local only). If the schema changes, update the Zig struct definitions in `src/bible_db.zig`.
- **System Transitions:** Refer to `GEMINI.md` for breaking changes and patterns related to Zig `0.16.0-dev`.

## How to Run
```bash
# Build and run the desktop app
zig build run

# Start the TTS backend (requires Python/MLX)
uv run python tools/tts_server.py
```
