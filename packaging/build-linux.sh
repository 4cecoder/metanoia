#!/bin/bash
# packaging/build-linux.sh
#
# Builds Metanoia in ReleaseFast mode and packages it as a prefix install
# under /opt/metanoia, because — unlike macOS — src/main.zig has NO
# runtime bundle-root resolution for Linux: sqlite3_open("data/bible.db",...)
# is a bare relative path resolved against the process's *current working
# directory*. There is no XDG data-dir lookup. So the app only works if it
# is launched with cwd == the directory containing ./data. We do not patch
# Zig source to fix this (out of scope for today) — instead we ship a thin
# launcher wrapper that `cd`s into the install prefix before exec'ing the
# real binary. See docs/PACKAGING.md.
#
# Produces two artifacts in dist/:
#   - Metanoia-linux-<arch>.tar.gz   (universal tarball + install.sh)
#   - metanoia_<version>_<arch>.deb  (Debian/Ubuntu package)
#
# This script has NOT been run end-to-end on a real Linux box (this repo
# was packaged from macOS, which cannot build/link a Linux GTK4 binary).
# It has been checked with `bash -n` and reasoned through carefully; the
# GitHub Actions job (.github/workflows/release-unix.yml) running on
# ubuntu-latest is the first real end-to-end run of this script.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}!!${NC} $1"; }
fail() { echo -e "${RED}xx${NC} $1"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="metanoia"
PREFIX="/opt/metanoia"
RAW_ARCH="$(uname -m)"
case "$RAW_ARCH" in
  x86_64) DEB_ARCH="amd64" ;;
  aarch64|arm64) DEB_ARCH="arm64" ;;
  *) DEB_ARCH="$RAW_ARCH" ;;
esac
TAG="${GITHUB_REF_NAME:-dev}"
VERSION="${TAG#v}"
[ -n "$VERSION" ] || VERSION="0.0.0-dev"
# Debian version fields must start with a digit.
case "$VERSION" in
  [0-9]*) : ;;
  *) VERSION="0.0.0-${VERSION}" ;;
esac

OUT_DIR="$ROOT/dist"
STAGE="$OUT_DIR/stage-linux-${RAW_ARCH}"
PKGROOT="$STAGE/pkgroot"
TARBALL="$OUT_DIR/Metanoia-linux-${RAW_ARCH}.tar.gz"
DEBFILE="$OUT_DIR/metanoia_${VERSION}_${DEB_ARCH}.deb"

# ── 0. Preconditions ────────────────────────────────────────────
command -v zig >/dev/null 2>&1 || fail "zig not found on PATH"
[ -f "$ROOT/data/bible.db" ] || fail "data/bible.db is missing (expected to be checked out from git — see .gitignore's data/*.db exception)."

info "Building Metanoia (ReleaseFast, $RAW_ARCH) with $(zig version)..."
zig build -Doptimize=ReleaseFast

BIN_SRC="$ROOT/zig-out/bin/${APP_NAME}"
[ -f "$BIN_SRC" ] || fail "expected binary at $BIN_SRC"

# ── 1. Assemble the /opt/metanoia + launcher + .desktop layout ──
rm -rf "$STAGE"
mkdir -p \
  "$PKGROOT${PREFIX}/bin" \
  "$PKGROOT/usr/bin" \
  "$PKGROOT/usr/share/applications" \
  "$PKGROOT/usr/share/icons/hicolor/scalable/apps"

cp "$BIN_SRC" "$PKGROOT${PREFIX}/bin/${APP_NAME}"
cp -r "$ROOT/data" "$PKGROOT${PREFIX}/data"
cp -r "$ROOT/assets" "$PKGROOT${PREFIX}/assets"
[ -d "$ROOT/static" ] && cp -r "$ROOT/static" "$PKGROOT${PREFIX}/static"

# Launcher: the app needs cwd == $PREFIX for its relative "data/bible.db" open.
cat > "$PKGROOT/usr/bin/${APP_NAME}" <<EOF
#!/bin/sh
cd "${PREFIX}" && exec "${PREFIX}/bin/${APP_NAME}" "\$@"
EOF
chmod +x "$PKGROOT/usr/bin/${APP_NAME}"
chmod +x "$PKGROOT${PREFIX}/bin/${APP_NAME}"

if [ -f "$ROOT/assets/icon.svg" ]; then
  cp "$ROOT/assets/icon.svg" "$PKGROOT/usr/share/icons/hicolor/scalable/apps/metanoia.svg"
fi

cat > "$PKGROOT/usr/share/applications/metanoia.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Metanoia
Comment=Bible study app
Exec=${APP_NAME}
Icon=metanoia
Terminal=false
Categories=Education;Spirituality;
EOF

# ── 2. Universal tarball (any distro, no package manager needed) ─
mkdir -p "$OUT_DIR"
rm -f "$TARBALL"

cat > "$PKGROOT/install.sh" <<'EOF'
#!/bin/bash
# Installs Metanoia into /opt/metanoia + /usr/bin + /usr/share (needs root).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ "$(id -u)" != "0" ]; then
  echo "Run with sudo: sudo ./install.sh" >&2
  exit 1
fi
cp -r "$HERE/opt/metanoia" /opt/
cp "$HERE/usr/bin/metanoia" /usr/bin/metanoia
mkdir -p /usr/share/applications /usr/share/icons/hicolor/scalable/apps
cp "$HERE/usr/share/applications/metanoia.desktop" /usr/share/applications/
[ -f "$HERE/usr/share/icons/hicolor/scalable/apps/metanoia.svg" ] && \
  cp "$HERE/usr/share/icons/hicolor/scalable/apps/metanoia.svg" /usr/share/icons/hicolor/scalable/apps/
echo "Installed. Run: metanoia"
EOF
chmod +x "$PKGROOT/install.sh"

info "Archiving universal tarball to $(basename "$TARBALL")..."
tar -C "$PKGROOT" -czf "$TARBALL" opt usr install.sh

# ── 3. .deb package (Debian/Ubuntu) ───────────────────────────────
if command -v dpkg-deb >/dev/null 2>&1; then
  DEBROOT="$STAGE/debroot"
  rm -rf "$DEBROOT"
  cp -r "$PKGROOT" "$DEBROOT"
  rm -f "$DEBROOT/install.sh"
  mkdir -p "$DEBROOT/DEBIAN"

  # Rough installed-size estimate in KB for the control file.
  INSTALLED_SIZE_KB="$(du -sk "$DEBROOT" | cut -f1)"

  cat > "$DEBROOT/DEBIAN/control" <<EOF
Package: metanoia
Version: ${VERSION}
Section: education
Priority: optional
Architecture: ${DEB_ARCH}
Installed-Size: ${INSTALLED_SIZE_KB}
Depends: libgtk-4-1, libsqlite3-0
Maintainer: ByteCats <devin@bytecats.codes>
Description: Bible study app (GTK4)
 Metanoia is a Zig + GTK4 Bible study application, Tokyo Night themed.
EOF

  info "Building .deb package to $(basename "$DEBFILE")..."
  rm -f "$DEBFILE"
  dpkg-deb --build --root-owner-group "$DEBROOT" "$DEBFILE"
else
  warn "dpkg-deb not found — skipping .deb build (tarball still produced)"
fi

rm -rf "$STAGE"

info "Done. Artifacts in $OUT_DIR:"
ls -la "$OUT_DIR" | grep -E "linux|\.deb" || true
