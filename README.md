# Metanoia

Bible study app in **Zig** + **GTK4**. Tokyo Night themed.

## Download (prebuilt, no build required)

Every push to `master` rebuilds the rolling **[Latest release](https://github.com/4cecoder/metanoia/releases/tag/latest)** for every platform below. Debug/ad-hoc signed — not notarized or Play Store distributed.

## Windows

Download `Metanoia-Setup.exe` (installer) or `Metanoia-windows-x86_64.zip` (portable) from the [Latest release](https://github.com/4cecoder/metanoia/releases/tag/latest).

Building from source instead (zero install, zero system changes):

```cmd
git clone https://github.com/4cecoder/metanoia
cd metanoia
windows_helper\compile.bat
MetanoiaSetup.exe
```

Click each red **Install** button → downloads Zig, MSYS2, GTK4 into `.cache\`. Then click **Build Project**. Nothing leaves the project folder — delete it, everything's gone.

Pre-configured VS Code: `Ctrl+Shift+B` builds, `F5` runs.

## macOS

Download `Metanoia-arm64.dmg` from the [Latest release](https://github.com/4cecoder/metanoia/releases/tag/latest) and drag to Applications. (A Homebrew formula exists at `Formula/metanoia.rb` but isn't published to a tap yet.)

Building from source instead:

```bash
brew install gtk4 pango cairo glib sqlite3
# Zig must be a recent master nightly (ziglang.org/download) — Homebrew's
# `zig` formula tracks a stable release and won't satisfy build.zig.zon.
zig build run
```

## Linux

Pick whichever fits your distro — same source, no distro-specific build needed:

| Distro | Recommended |
|---|---|
| Fedora, Arch, openSUSE, and other non-Debian distros | `Metanoia-x86_64.AppImage` — `chmod +x`, run directly |
| Any distro with Flatpak | `flatpak install Metanoia.flatpak` |
| Debian/Ubuntu | `sudo dpkg -i metanoia_*.deb` |
| Anywhere | `Metanoia-linux-x86_64.tar.gz` — untar, run `install.sh` |

All from the [Latest release](https://github.com/4cecoder/metanoia/releases/tag/latest).

Building from source instead:

```bash
# Debian/Ubuntu
sudo apt install libgtk-4-dev libsqlite3-dev
# Fedora
sudo dnf install gtk4-devel sqlite-devel
# Arch
sudo pacman -S gtk4 sqlite
# Zig must be a recent master nightly (ziglang.org/download), not your
# distro's package — build.zig.zon pins an API surface no stable release has.
zig build run
```

## Android

Sideload `metanoia-android-*.apk` from the [Latest release](https://github.com/4cecoder/metanoia/releases/tag/latest), or build from `mobile/` with Android Studio / `./gradlew assembleDebug`.

## Project

```
src/          → Zig source (kit/ ui library, main.zig, services/)
mobile/       → Android client (Kotlin, Jetpack Compose)
packaging/    → Installer/AppImage/Flatpak/DMG build scripts
docs/         → Architecture docs
.cache/       → Local dev tools (auto-downloaded, never committed)
windows_helper/ → C# setup wizard (compiles with built-in Windows csc.exe)
```

See [docs/index.md](docs/index.md) for full architecture docs.
