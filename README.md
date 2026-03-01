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

## How to Run
```bash
zig build run
```

## Structure
- `src/main.zig`: Core application logic and GTK integration.
- `assets/themes/tokyo-night.css`: Tokyo Night theme definitions.
- `data/`: Placeholder for Bible text data.
