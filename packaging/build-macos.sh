#!/bin/bash
# packaging/build-macos.sh
#
# Builds Metanoia in ReleaseFast mode, assembles a proper Metanoia.app bundle
# (binary + data/ + assets/ under Contents/Resources, relying on the
# resolveBundleRoot() chdir logic in src/main.zig which detects
# ".app/Contents/MacOS/" in its own executable path), ad-hoc signs it, and
# tars it up as Metanoia-macos-<arch>.tar.gz for GitHub Releases / Homebrew.
#
# Requirements: zig (master nightly, see .github/workflows/release-unix.yml
# for the pinned version fetch), gtk4/pango/cairo/glib/sqlite3 (brew).
#
# data/bible.db and the voice clips actually referenced by data/voices.json
# are tracked in git as explicit exceptions to the data/*.db / *.wav
# .gitignore rules (see .gitignore) — a plain `actions/checkout` is enough,
# no separate data-fetch step needed. This script still fails fast below if
# data/bible.db is somehow missing (e.g. a shallow/sparse checkout), rather
# than silently shipping a Bible app with no Bible.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}!!${NC} $1"; }
fail() { echo -e "${RED}xx${NC} $1"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Metanoia"
ARCH="$(uname -m)"                     # arm64 or x86_64
TAG="${GITHUB_REF_NAME:-dev}"
OUT_DIR="$ROOT/dist"
TARBALL="$OUT_DIR/Metanoia-macos-${ARCH}.tar.gz"

# ── 0. Preconditions ────────────────────────────────────────────
command -v zig >/dev/null 2>&1 || fail "zig not found on PATH"
[ -f "$ROOT/data/bible.db" ] || fail "data/bible.db is missing. It is gitignored and must be provided before packaging (see docs/PACKAGING.md)."
[ -f "$ROOT/assets/Info.plist" ] || fail "assets/Info.plist missing"
[ -f "$ROOT/assets/${APP_NAME}.icns" ] || fail "assets/${APP_NAME}.icns missing"

info "Building Metanoia (ReleaseFast, $ARCH) with $(zig version)..."
zig build app -Doptimize=ReleaseFast

APP_DIR="$ROOT/zig-out/${APP_NAME}.app"
[ -d "$APP_DIR" ] || fail "expected $APP_DIR to exist after 'zig build app'"

# ── 1. Ad-hoc codesign (no paid cert needed) ────────────────────
# This does NOT satisfy Gatekeeper/notarization (users will still see an
# "unidentified developer" prompt on first launch — right-click > Open, or
# `xattr -cr Metanoia.app` after download). It just gives the bundle a
# valid ad-hoc signature so macOS doesn't refuse to run it outright.
if command -v codesign >/dev/null 2>&1; then
  info "Ad-hoc signing $APP_NAME.app..."
  codesign --force --deep --sign - "$APP_DIR" || warn "ad-hoc codesign failed, continuing unsigned"
else
  warn "codesign not found, shipping fully unsigned"
fi

# ── 2. Tar it up ─────────────────────────────────────────────────
mkdir -p "$OUT_DIR"
rm -f "$TARBALL"
info "Archiving to $(basename "$TARBALL")..."
tar -C "$ROOT/zig-out" -czf "$TARBALL" "${APP_NAME}.app"

SIZE="$(du -sh "$TARBALL" | cut -f1)"
info "Done: $TARBALL ($SIZE) — tag=$TAG"
