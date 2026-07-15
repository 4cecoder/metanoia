# Metanoia

Bible study app in **Zig** + **GTK4**. Tokyo Night themed.

## Windows (zero install, zero system changes)

```cmd
git clone https://github.com/4cecoder/metanoia
cd metanoia
windows_helper\compile.bat
MetanoiaSetup.exe
```

Click each red **Install** button → downloads Zig, MSYS2, GTK4 into `.cache\`. Then click **Build Project**. That's it. Nothing leaves the project folder — delete it, everything's gone.

Pre-configured VS Code: `Ctrl+Shift+B` builds, `F5` runs.

## macOS

```bash
brew install zig gtk4 pango cairo glib sqlite3
zig build run
```

## Linux

```bash
# Debian/Ubuntu
sudo apt install zig libgtk-4-dev libsqlite3-dev
zig build run
```

## Project

```
src/          → Zig source (kit/ ui library, main.zig, services/)
docs/         → Architecture docs
.cache/       → Local dev tools (auto-downloaded, never committed)
windows_helper/ → C# setup wizard (compiles with built-in Windows csc.exe)
```

See [docs/index.md](docs/index.md) for full architecture docs.
