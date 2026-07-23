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

# ── 0.5. Lower the binary's minimum macOS version ───────────────
# `zig build` with no -Dtarget compiles "native", which bakes in the
# EXACT host machine's current OS version as the binary's LC_BUILD_VERSION
# minos (confirmed directly: a build on a machine running macOS 26.2
# produced `minos 26.2`, via `otool -l`). Since GitHub's macos-latest
# runner's exact OS build can be ahead of whatever a given user has
# installed, that made the shipped app fail to launch on real user
# machines with "You can't use this version of the application 'Metanoia'
# with this version of macOS" — the app was silently requiring an OS
# NEWER than what the runner happened to be on that day, not any real
# API dependency.
#
# Fix: `vtool` (Apple's Mach-O load-command editor, part of Xcode Command
# Line Tools, present on every macOS GitHub Actions runner) rewrites the
# binary's LC_BUILD_VERSION minos/sdk fields in place, after linking but
# BEFORE codesigning below (patching after signing would invalidate the
# signature). Passing an explicit -Dtarget to zig instead of doing this
# was tried and rejected: it makes zig treat the build as cross-compiling
# even though it's the same arch+OS, which broke native system-library
# search (Homebrew's gtk4 include paths no longer resolved sqlite3, which
# macOS ships as a system dylib at /usr/lib — confirmed by reproducing the
# exact failure locally) — vtool avoids all of that by never touching how
# the binary is compiled/linked, only its post-link version metadata.
#
# 13.0 (Ventura, 2022) is a conservative, multi-year-back floor — well
# below any realistically current user's OS, while still modern enough
# for Homebrew's own gtk4/glib/etc. bottles (which target similarly
# multi-year-back baselines, not bleeding-edge).
MIN_MACOS="13.0"
if command -v vtool >/dev/null 2>&1; then
  info "Lowering minimum macOS version to $MIN_MACOS (was $(otool -l "$APP_DIR/Contents/MacOS/metanoia" | awk '/minos/{print $2; exit}'))..."
  vtool -set-build-version macos "$MIN_MACOS" "$MIN_MACOS" -replace \
    -output "$APP_DIR/Contents/MacOS/metanoia" \
    "$APP_DIR/Contents/MacOS/metanoia"
else
  fail "vtool not found — cannot set a portable minimum macOS version (shipping without this fix reproduces the exact 'can't use this version' bug on any user machine older than the CI runner's current OS)"
fi

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
