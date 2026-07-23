#!/bin/bash
# packaging/build-macos-dmg.sh
#
# Assembles a polished, standard drag-to-Applications macOS installer DMG
# from the already-built, already-signed zig-out/Metanoia.app (produced by
# packaging/build-macos.sh — this script does NOT duplicate that script's
# build/vtool/codesign steps; if the .app isn't present yet it simply
# delegates to build-macos.sh so there is exactly one place that owns the
# build → vtool-minos-patch → codesign ordering).
#
# Output: dist/Metanoia-<arch>.dmg
#
# Requirements: create-dmg (`brew install create-dmg`), hdiutil (ships with
# macOS). assets/Metanoia.icns (volume icon) and assets/dmg-background.png
# (Finder window background, Tokyo Night themed) must exist — both are
# tracked in git like the other packaging assets.
#
# Design of assets/dmg-background.png: solid Tokyo Night dark-navy
# (#1a1b26 → #20222f subtle vertical gradient) background with the
# "METANOIA" wordmark in the brand accent blue (#7aa2f7, same palette as
# assets/values equivalents / mobile/app/.../ic_launcher_background.xml)
# plus a small accent-blue arrow between where the app icon and the
# Applications symlink sit — the universal, tasteful convention used by
# most polished Mac app DMGs (see e.g. any create-dmg gallery example).
# Deliberately simple: no photography, no per-pixel gradients beyond the
# one subtle vertical fade, no drop shadows — "tasteful and simple beats
# gaudy" per the design brief. Generated with ImageMagick (`magick`), not
# hand-drawn or AI-generated — see the (kept, for future re-generation)
# commented recipe below the preconditions section if the background ever
# needs to be regenerated/tweaked.
#
# ImageMagick recipe used to generate assets/dmg-background.png:
#   FONT="/System/Library/Fonts/Helvetica.ttc"
#   magick -size 660x400 \
#     gradient:"#1a1b26"-"#20222f" \
#     -fill "#7aa2f7" -font "$FONT" -pointsize 22 -gravity North -kerning 3 \
#       -annotate +0+38 "METANOIA" \
#     -fill "#6b7094" -font "$FONT" -pointsize 12 -gravity North \
#       -annotate +0+68 "Drag to Applications to install" \
#     -strokewidth 6 -stroke "#7aa2f7" -fill none \
#     -draw "stroke-linecap round line 306,170 354,170" \
#     -draw "stroke-linecap round line 338,155 354,170" \
#     -draw "stroke-linecap round line 338,185 354,170" \
#     assets/dmg-background.png
#
# Known limitation (not independently verifiable on this machine): the
# background PNG is generated at exactly the DMG window's pixel size
# (660x400), the same convention virtually every create-dmg tutorial uses.
# On a Retina display this will render slightly softer than a native @2x
# asset would — Finder's folder-background mechanism does not reliably
# pick up a "@2x" HiDPI pair the way app icons do, so doubling the
# resolution here would make the image display literally twice the window
# size instead of crisper. This was reasoned through, not fixed, since a
# @2x pairing convention for Finder background PNGs isn't dependably
# supported here to confirm — flagging rather than claiming it's crisp on
# all displays.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}!!${NC} $1"; }
fail() { echo -e "${RED}xx${NC} $1"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Metanoia"
ARCH="$(uname -m)"                     # arm64 or x86_64
OUT_DIR="$ROOT/dist"
APP_DIR="$ROOT/zig-out/${APP_NAME}.app"
DMG="$OUT_DIR/Metanoia-${ARCH}.dmg"
BACKGROUND="$ROOT/assets/dmg-background.png"
VOLICON="$ROOT/assets/${APP_NAME}.icns"

# ── 0. Preconditions ────────────────────────────────────────────
command -v create-dmg >/dev/null 2>&1 || fail "create-dmg not found — install with: brew install create-dmg"
command -v hdiutil >/dev/null 2>&1 || fail "hdiutil not found (should ship with macOS)"
[ -f "$BACKGROUND" ] || fail "$BACKGROUND missing"
[ -f "$VOLICON" ] || fail "$VOLICON missing"

if [ ! -d "$APP_DIR" ]; then
  warn "$APP_DIR not found — building via packaging/build-macos.sh first (same build/vtool/codesign pipeline, not duplicated here)..."
  bash "$ROOT/packaging/build-macos.sh"
fi
[ -d "$APP_DIR" ] || fail "expected $APP_DIR to exist after packaging/build-macos.sh"

# ── 1. Stage a clean source folder ──────────────────────────────
# create-dmg copies the *contents* of this folder into the DMG and adds the
# Applications symlink itself (via --app-drop-link below) — so the staging
# folder holds only Metanoia.app, nothing else.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/metanoia-dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_DIR" "$STAGE/"

# ── 2. Assemble the DMG ──────────────────────────────────────────
mkdir -p "$OUT_DIR"
rm -f "$DMG"

info "Building $(basename "$DMG") with create-dmg..."
create-dmg \
  --volname "$APP_NAME" \
  --volicon "$VOLICON" \
  --background "$BACKGROUND" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --text-size 13 \
  --icon "${APP_NAME}.app" 180 170 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 480 170 \
  --no-internet-enable \
  --overwrite \
  "$DMG" \
  "$STAGE/"

[ -f "$DMG" ] || fail "create-dmg reported success but $DMG is missing"

SIZE="$(du -sh "$DMG" | cut -f1)"
info "Done: $DMG ($SIZE)"
