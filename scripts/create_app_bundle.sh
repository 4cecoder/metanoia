#!/bin/bash
set -euo pipefail

APP_NAME="Metanoia"
BINARY="metanoia"
ZIG_OUT="zig-out"
APP_DIR="$ZIG_OUT/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

cp "$ZIG_OUT/bin/$BINARY" "$MACOS/"
cp "assets/$APP_NAME.icns" "$RESOURCES/"
cp "assets/Info.plist" "$CONTENTS/"

# Bundle runtime data and assets so the app is self-contained
cp -r data "$RESOURCES/"
cp -r assets "$RESOURCES/"
cp -r static "$RESOURCES/"

echo "✅ $APP_NAME.app created at $APP_DIR"
