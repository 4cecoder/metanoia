#!/bin/bash
set -euo pipefail

APP_NAME="Metanoia"
BINARY="metanoia"
SCRAPER_BINARY="metanoia-scraper"
ZIG_OUT="zig-out"
APP_DIR="$ZIG_OUT/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

cp "$ZIG_OUT/bin/$BINARY" "$MACOS/"
if [ ! -x "$ZIG_OUT/bin/$SCRAPER_BINARY" ]; then
  echo "❌ missing $ZIG_OUT/bin/$SCRAPER_BINARY (build with 'zig build app')" >&2
  exit 1
fi
cp "$ZIG_OUT/bin/$SCRAPER_BINARY" "$MACOS/"
cp "assets/$APP_NAME.icns" "$RESOURCES/"
cp "assets/Info.plist" "$CONTENTS/"

# Bundle runtime data and assets so the app is self-contained
cp -r data "$RESOURCES/"
cp -r assets "$RESOURCES/"
cp -r static "$RESOURCES/"
mkdir -p "$RESOURCES/tools"
cp "tools/bible_books.json" "$RESOURCES/tools/"

echo "✅ $APP_NAME.app created at $APP_DIR"
