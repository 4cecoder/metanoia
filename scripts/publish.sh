#!/usr/bin/env bash
set -euo pipefail

# Publish latest build to GitHub Releases
# Requires: gh CLI (https://cli.github.com)
# Run after: bash ci/run-windows.sh  (or local zig build + scripts/package.sh)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}❯${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Check prerequisites ────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  warn "gh CLI not found. Install: https://cli.github.com"
  warn "Then: gh auth login"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  warn "Not authenticated. Run: gh auth login"
  exit 1
fi

# ── Determine version ──────────────────────────────────────────
VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo "v0.0.0-$(git rev-parse --short HEAD)")"
TAG="$VERSION"

# ── Build if needed ────────────────────────────────────────────
if [ ! -f "zig-out/bin/metanoia.exe" ]; then
  info "Building..."
  zig build 2>&1
  bash scripts/package.sh
fi

# ── Find the installer or dist folder ───────────────────────────
INSTALLER=$(ls dist/Metanoia-Setup-*.exe 2>/dev/null | head -1)
DIST_ZIP="dist/Metanoia-${VERSION}.zip"

if [ ! -f "$INSTALLER" ]; then
  warn "No NSIS installer found — creating portable zip"
  if [ ! -d "dist/Metanoia" ]; then
    warn "No dist folder. Run: scripts/package.sh"
    exit 1
  fi
  (cd dist && zip -r "../$DIST_ZIP" Metanoia/)
  UPLOAD="$DIST_ZIP"
  NOTES="Portable build (no installer) — unzip and run metanoia.exe"
else
  UPLOAD="$INSTALLER"
  NOTES="NSIS installer — run Metanoia-Setup-*.exe to install"
fi

# ── Create GitHub Release ───────────────────────────────────────
info "Creating GitHub release: $TAG..."
gh release create "$TAG" \
  "$UPLOAD" \
  --title "Metanoia $VERSION" \
  --notes "$NOTES" \
  --generate-notes 2>&1 || {
    # Release exists — update instead
    info "Release exists — uploading asset..."
    gh release upload "$TAG" "$UPLOAD" --clobber 2>&1
  }

info "Published: https://github.com/4cecoder/metanoia/releases/tag/$TAG"
info "Done."
