#!/bin/bash
set -euo pipefail

APP_NAME="Metanoia"
BINARY="metanoia"
SCRAPER_BINARY="metanoia-scraper"
MODELS_BINARY="metanoia-models"
TTS_BINARY="metanoia-tts"
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
if [ ! -x "$ZIG_OUT/bin/$MODELS_BINARY" ]; then
  echo "❌ missing $ZIG_OUT/bin/$MODELS_BINARY (build with 'zig build app')" >&2
  exit 1
fi
cp "$ZIG_OUT/bin/$MODELS_BINARY" "$MACOS/"
# Native builds add the long-lived TTS worker. Use the build graph's explicit
# flag rather than merely checking zig-out/bin: switching build variants in a
# reused zig-out directory must not copy a stale native worker into a stable
# bundle.
if [ "${METANOIA_NATIVE_AI:-false}" = "true" ]; then
  if [ ! -x "$ZIG_OUT/bin/$TTS_BINARY" ]; then
    echo "❌ missing $ZIG_OUT/bin/$TTS_BINARY (native build did not install worker)" >&2
    exit 1
  fi
  cp "$ZIG_OUT/bin/$TTS_BINARY" "$MACOS/"
else
  # Remove a worker left by a previous native build when the same zig-out
  # directory is reused for a stable/remote-only bundle.
  if [ -e "$MACOS/$TTS_BINARY" ]; then
    unlink "$MACOS/$TTS_BINARY"
  fi
fi
cp "assets/$APP_NAME.icns" "$RESOURCES/"
cp "assets/Info.plist" "$CONTENTS/"

# Bundle runtime data and assets so the app is self-contained
cp -r data "$RESOURCES/"
cp -r assets "$RESOURCES/"
cp -r static "$RESOURCES/"
mkdir -p "$RESOURCES/tools"
cp "tools/bible_books.json" "$RESOURCES/tools/"

echo "✅ $APP_NAME.app created at $APP_DIR"
