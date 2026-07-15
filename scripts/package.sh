#!/usr/bin/env bash
set -euo pipefail

# Package Metanoia for Windows distribution
# Run after: zig build (produces zig-out/bin/metanoia.exe)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}❯${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist/Metanoia"
VERSION=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "dev")

info "Packaging Metanoia ($VERSION)..."

# ── 1. Check build output ──────────────────────────────────────
if [ ! -f "$ROOT/zig-out/bin/metanoia.exe" ]; then
  warn "metanoia.exe not found. Run 'zig build' first."
  exit 1
fi

rm -rf "$DIST"
mkdir -p "$DIST"

# ── 2. Copy exe + all DLLs ─────────────────────────────────────
info "Copying binaries..."
cp "$ROOT/zig-out/bin/metanoia.exe" "$DIST/"
if ls "$ROOT/zig-out/bin/"*.dll >/dev/null 2>&1; then
  cp "$ROOT/zig-out/bin/"*.dll "$DIST/"
fi
info "  $(ls -1 "$DIST" | wc -l) files"

# ── 3. Copy assets ─────────────────────────────────────────────
info "Copying assets..."
cp "$ROOT/assets/metanoia.ico" "$DIST/" 2>/dev/null || true
cp "$ROOT/assets/themes/tokyo-night.css" "$DIST/" 2>/dev/null || true
cp "$ROOT/data/bible.db" "$DIST/" 2>/dev/null || true

# ── 4. Build NSIS installer ────────────────────────────────────
if command -v makensis &>/dev/null; then
  info "Building NSIS installer..."
  cd "$ROOT"
  makensis -NOCD \
    -DPRODUCT_VERSION="$VERSION" \
    scripts/installer.nsi 2>&1 | tail -3
  mv "Metanoia-Setup-${VERSION}.exe" "$ROOT/dist/"
  info "  Installer: dist/Metanoia-Setup-${VERSION}.exe"
else
  warn "makensis not found — skipping installer"
  info "  Portable dist: $DIST/ (just zip and ship)"
  info "  Install NSIS: sudo apt install nsis  (Linux)"
  info "  Or download: https://nsis.sourceforge.io"
fi

info "Done: $(du -sh "$ROOT/dist" | cut -f1)"
