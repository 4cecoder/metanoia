#!/bin/bash
# packaging/build-appimage.sh
#
# Builds a single portable Metanoia-x86_64.AppImage — no installation, no
# package manager, runs on virtually any x86_64 Linux distro with a
# reasonably modern kernel/glibc.
#
# Tooling: linuxdeploy + linuxdeploy-plugin-gtk, the standard, documented
# combo for packaging GTK3/GTK4 apps as AppImages (see
# https://github.com/linuxdeploy/linuxdeploy and
# https://github.com/linuxdeploy/linuxdeploy-plugin-gtk). Both are
# downloaded here as *pinned* artifacts, matching this repo's existing
# "pin a specific release, curl it, chmod +x" house style (see the
# Zig-nightly-fetch steps in .github/workflows/release-latest.yml) rather
# than trusting an unpinned "latest"/"continuous" URL that could change
# under us:
#
#   - linuxdeploy itself and linuxdeploy-plugin-appimage DO publish dated,
#     immutable GitHub releases (in addition to a rolling "continuous" tag
#     that overwrites its own assets on every upstream commit — deliberately
#     NOT used here). We pin tag 1-alpha-20251107-1 (linuxdeploy's most
#     recent dated release as of this writing) and 1-alpha-20250213-1
#     (linuxdeploy-plugin-appimage's), verifying sha256 of both downloads.
#   - linuxdeploy-plugin-gtk is distributed as a single shell script with NO
#     versioned releases at all (checked: `gh api
#     repos/linuxdeploy/linuxdeploy-plugin-gtk/releases` returns empty) — so
#     instead we pin it to a specific commit SHA of linuxdeploy/
#     linuxdeploy-plugin-gtk's master branch and verify its sha256, which is
#     the closest equivalent of "pin a specific release" available for a
#     script-only, tag-less upstream.
#
# All three sha256 sums below were computed locally against the exact files
# fetched from these exact URLs (see this script's own comments for
# reproducibility) — bump both the URL/SHA together if you ever re-pin.
#
# GTK4/SQLite3 .so dependency handling: linuxdeploy's core behavior (not
# specific to any plugin) is to `ldd`-trace whatever executable you pass it
# via `-e` and copy that shared-library dependency closure into
# AppDir/usr/lib automatically — this happens for GTK4 and SQLite3 exactly
# the same as it would for any other linked library, no extra flags needed.
# What plain linuxdeploy does NOT handle on its own is the *GTK ecosystem*
# beyond raw .so files: GLib GSettings schemas, GDK-Pixbuf loaders (needed to
# actually render PNG/SVG icons inside the running app), and GTK4 theme
# engine bits. That's exactly what linuxdeploy-plugin-gtk adds — it is
# specifically documented for this and is the standard, community-recommended
# plugin for GTK3/4 AppImages (auto-detects GTK version 2/3/4 from the
# bundled binary's linkage; here it will auto-detect 4).
#
# The Ubuntu runner's own system GTK4/SQLite3 (installed via apt for the zig
# build step, same as packaging/build-linux.sh) are NOT what end users run
# against — once linuxdeploy + the gtk plugin finish, the AppImage carries
# its own copies of these libraries in AppDir/usr/lib, which is the whole
# point of an AppImage (self-contained, works on distros that don't have
# libgtk-4 installed system-wide at all, e.g. older Ubuntu LTS, Fedora,
# Arch, Gentoo).
#
# The cwd problem: same root cause as packaging/build-linux.sh (see
# docs/PACKAGING.md's "macOS vs Linux asymmetry" section) —
# sqlite3_open("data/bible.db", ...) is a bare relative path in
# src/main.zig with no XDG-style resolution logic for Linux, so the process
# must be launched with cwd == the directory holding ./data. AppImages have
# no equivalent of build-linux.sh's /usr/bin wrapper script, but
# linuxdeploy's default-generated AppRun sources every *.sh file under
# AppDir/apprun-hooks/ (this is the same mechanism
# linuxdeploy-plugin-gtk itself uses to inject GTK env vars — see its
# "Installing AppRun hook" step) *before* exec'ing the real binary, in the
# same shell, so a hook that just `cd`s affects the final exec's cwd. We
# install our own trivial hook for exactly that (see step 3 below) instead
# of writing a custom AppRun from scratch, so we don't have to reimplement
# (or accidentally break) everything linuxdeploy-plugin-gtk's own hook does.
#
# This script has NOT been run end-to-end (this machine is macOS — no ELF
# linuxdeploy/AppImage tooling runs here at all, and there is no
# ubuntu/x86_64 Linux to actually produce+launch an AppImage on). It has
# been checked with `bash -n` and reasoned through carefully against
# linuxdeploy/linuxdeploy-plugin-gtk's actual documented behavior; the
# GitHub Actions job (.github/workflows/release-latest.yml's
# build-appimage) running on ubuntu-latest is the first real end-to-end run.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}!!${NC} $1"; }
fail() { echo -e "${RED}xx${NC} $1"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="metanoia"
OUT_DIR="$ROOT/dist"
APPIMAGE_OUT="$OUT_DIR/Metanoia-x86_64.AppImage"
TOOLS_DIR="$OUT_DIR/appimage-tools"
STAGE="$OUT_DIR/stage-appimage"
APPDIR="$STAGE/AppDir"

# Pinned tool versions (see header comment for why each is pinned the way
# it is). Bump the URL and sha256 together if you re-pin.
LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage"
LINUXDEPLOY_SHA256="c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d"

LINUXDEPLOY_PLUGIN_APPIMAGE_URL="https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/1-alpha-20250213-1/linuxdeploy-plugin-appimage-x86_64.AppImage"
LINUXDEPLOY_PLUGIN_APPIMAGE_SHA256="992d502a248e14ab185448ddf6f6e7d25558cb84d4623c354c3af350c25fccb3"

# No versioned releases exist for this one (script-only distribution) —
# pinned to a specific commit of the master branch instead.
LINUXDEPLOY_PLUGIN_GTK_COMMIT="7a3fbc31a9e5075073ff8790f26effbac5f84453"
LINUXDEPLOY_PLUGIN_GTK_URL="https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/${LINUXDEPLOY_PLUGIN_GTK_COMMIT}/linuxdeploy-plugin-gtk.sh"
LINUXDEPLOY_PLUGIN_GTK_SHA256="b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171"

verify_sha256() {
  local file="$1" expected="$2"
  local actual
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  [ "$actual" = "$expected" ] || fail "sha256 mismatch for $file: expected $expected, got $actual"
}

fetch_pinned() {
  local url="$1" out="$2" sha="$3"
  if [ -f "$out" ]; then
    verify_sha256 "$out" "$sha" 2>/dev/null && return 0
    warn "cached $out failed checksum, re-downloading"
  fi
  info "Downloading $(basename "$out")..."
  curl -fsSL "$url" -o "$out"
  verify_sha256 "$out" "$sha"
}

# ── 0. Preconditions ────────────────────────────────────────────
command -v zig >/dev/null 2>&1 || fail "zig not found on PATH"
[ -f "$ROOT/data/bible.db" ] || fail "data/bible.db is missing (expected to be checked out from git — see .gitignore's data/*.db exception)."
[ -f "$ROOT/assets/metanoia.png" ] || fail "assets/metanoia.png missing (AppImage/.desktop icon — see docs/PACKAGING.md)."

# ── 1. Build (reuse packaging/build-linux.sh's own build output if already
#      produced by an earlier step in the same CI run; otherwise build). ──
BIN_SRC="$ROOT/zig-out/bin/${APP_NAME}"
if [ -f "$BIN_SRC" ]; then
  info "Reusing existing $BIN_SRC"
else
  info "Building Metanoia (ReleaseFast) with $(zig version)..."
  zig build -Doptimize=ReleaseFast
fi
[ -f "$BIN_SRC" ] || fail "expected binary at $BIN_SRC"

# ── 2. Fetch pinned tooling ──────────────────────────────────────
mkdir -p "$TOOLS_DIR"
fetch_pinned "$LINUXDEPLOY_URL" "$TOOLS_DIR/linuxdeploy-x86_64.AppImage" "$LINUXDEPLOY_SHA256"
fetch_pinned "$LINUXDEPLOY_PLUGIN_APPIMAGE_URL" "$TOOLS_DIR/linuxdeploy-plugin-appimage-x86_64.AppImage" "$LINUXDEPLOY_PLUGIN_APPIMAGE_SHA256"
fetch_pinned "$LINUXDEPLOY_PLUGIN_GTK_URL" "$TOOLS_DIR/linuxdeploy-plugin-gtk.sh" "$LINUXDEPLOY_PLUGIN_GTK_SHA256"
chmod +x "$TOOLS_DIR"/linuxdeploy-x86_64.AppImage "$TOOLS_DIR"/linuxdeploy-plugin-appimage-x86_64.AppImage "$TOOLS_DIR"/linuxdeploy-plugin-gtk.sh

# GitHub Actions runners generally lack a working FUSE setup for
# AppImage's default FUSE-mount launch path ("dlopen(): error loading
# libfuse.so.2" is the common symptom). APPIMAGE_EXTRACT_AND_RUN makes the
# AppImage runtime self-extract to a temp dir and exec from there instead
# of mounting via FUSE — the standard CI workaround.
export APPIMAGE_EXTRACT_AND_RUN=1

# ── 3. Assemble AppDir ────────────────────────────────────────────
rm -rf "$STAGE"
mkdir -p \
  "$APPDIR/usr/bin" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
  "$APPDIR/usr/share/icons/hicolor/scalable/apps" \
  "$APPDIR/usr/share/metanoia" \
  "$APPDIR/apprun-hooks"

cp "$BIN_SRC" "$APPDIR/usr/bin/${APP_NAME}"
chmod +x "$APPDIR/usr/bin/${APP_NAME}"

# data/ and assets/ live under usr/share/metanoia/ (arbitrary but
# conventional location for an app's own read-only payload inside an
# AppDir), NOT usr/bin/ alongside the binary — keeps the executable
# directory clean and matches how build-linux.sh separates
# /opt/metanoia/{bin,data,assets}.
cp -r "$ROOT/data" "$APPDIR/usr/share/metanoia/data"
cp -r "$ROOT/assets" "$APPDIR/usr/share/metanoia/assets"
[ -d "$ROOT/static" ] && cp -r "$ROOT/static" "$APPDIR/usr/share/metanoia/static"

# Same .desktop content as packaging/build-linux.sh's (no standalone
# .desktop file exists elsewhere in the repo to reuse verbatim — this repo
# only has it as a heredoc inside that script — so this is a deliberate
# adaptation of the exact same fields, not a divergent one).
cat > "$APPDIR/usr/share/applications/metanoia.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Metanoia
Comment=Bible study app
Exec=${APP_NAME}
Icon=metanoia
Terminal=false
Categories=Education;Spirituality;
EOF
cp "$APPDIR/usr/share/applications/metanoia.desktop" "$APPDIR/metanoia.desktop"

# Icon: assets/metanoia.png (256x256, extracted from assets/metanoia.ico's
# largest embedded frame — see docs/PACKAGING.md; this repo previously had
# no PNG icon, only the Windows .ico and a scalable .svg). AppImage/Linux
# desktop-icon convention wants a PNG (some file managers don't render an
# AppImage's own thumbnail from an SVG), so this PNG is specifically for
# AppImage packaging; the existing .svg is still what build-linux.sh's
# tarball/.deb ships under hicolor/scalable/apps/, unchanged.
cp "$ROOT/assets/metanoia.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/metanoia.png"
cp "$ROOT/assets/metanoia.png" "$APPDIR/metanoia.png"
if [ -f "$ROOT/assets/icon.svg" ]; then
  cp "$ROOT/assets/icon.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/metanoia.svg"
fi

# AppRun hook: cd into the AppDir-relative data/assets directory before the
# real binary runs, working around src/main.zig's lack of Linux XDG-style
# path resolution (see header comment above and
# docs/PACKAGING.md's "macOS vs Linux asymmetry"). linuxdeploy's
# default-generated AppRun sources every apprun-hooks/*.sh file (in the same
# shell, before the final exec) — this is the exact mechanism
# linuxdeploy-plugin-gtk itself uses one step below to inject GTK env vars,
# so this hook composes with it rather than fighting it. Named to sort
# after the gtk plugin's own hook alphabetically, though order does not
# actually matter for a plain `cd`.
cat > "$APPDIR/apprun-hooks/zz-metanoia-cwd.sh" <<'EOF'
#!/usr/bin/env bash
cd "${APPDIR}/usr/share/metanoia" || true
EOF

# ── 4. Run linuxdeploy + gtk plugin + appimage plugin ────────────
info "Running linuxdeploy (+ gtk, appimage plugins)..."
export LINUXDEPLOY_PLUGIN_GTK_SCRIPT="$TOOLS_DIR/linuxdeploy-plugin-gtk.sh"
export PATH="$TOOLS_DIR:$PATH"
# linuxdeploy discovers plugins named `linuxdeploy-plugin-<name>` on PATH,
# or (for scripts) any executable of that name on PATH — hence adding
# TOOLS_DIR to PATH above and naming the gtk script accordingly instead of
# passing it a full path via a flag (linuxdeploy-plugin-gtk has no such
# flag; it's invoked as `linuxdeploy --plugin gtk`).
ln -sf "$TOOLS_DIR/linuxdeploy-plugin-gtk.sh" "$TOOLS_DIR/linuxdeploy-plugin-gtk"

"$TOOLS_DIR/linuxdeploy-x86_64.AppImage" \
  --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/${APP_NAME}" \
  --desktop-file "$APPDIR/metanoia.desktop" \
  --icon-file "$APPDIR/metanoia.png" \
  --plugin gtk \
  --output appimage

# linuxdeploy writes the AppImage to the current directory by default.
PRODUCED="$(find "$ROOT" -maxdepth 1 -name "Metanoia*.AppImage" -newer "$STAGE" 2>/dev/null | head -1)"
if [ -z "$PRODUCED" ]; then
  # Fall back to whatever glob linuxdeploy actually used (it names the
  # output after the .desktop file's basename + arch by default).
  PRODUCED="$(find "$ROOT" -maxdepth 1 -iname "*.AppImage" 2>/dev/null | head -1)"
fi
[ -n "$PRODUCED" ] || fail "linuxdeploy did not produce an .AppImage in $ROOT"

mkdir -p "$OUT_DIR"
rm -f "$APPIMAGE_OUT"
mv "$PRODUCED" "$APPIMAGE_OUT"
chmod +x "$APPIMAGE_OUT"

rm -rf "$STAGE"

SIZE="$(du -sh "$APPIMAGE_OUT" | cut -f1)"
info "Done: $APPIMAGE_OUT ($SIZE)"
