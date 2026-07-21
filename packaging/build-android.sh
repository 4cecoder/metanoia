#!/bin/bash
# packaging/build-android.sh
#
# Thin wrapper around the Gradle build for the Android client.
#
# IMPORTANT: mobile/app/build.gradle.kts has NO signingConfigs block, so
# `assembleRelease` cannot produce an installable APK today (Android refuses
# to install an unsigned release APK). Rather than invent a throwaway
# keystore or touch build.gradle.kts, this script builds `assembleDebug`
# instead — Gradle auto-signs debug builds with the default Android debug
# keystore. The resulting APK is installable (sideload / `adb install`) but
# is NOT suitable for the Play Store and should be labeled as a debug build
# in release notes. See docs/PACKAGING.md for what a real signed release
# needs (keystore + Gradle signingConfigs.release + CI secrets).
#
# Verified locally: `cd mobile && ./gradlew assembleDebug` produces
# mobile/app/build/outputs/apk/debug/app-debug.apk (~100MB, includes bundled
# ONNX/MediaPipe runtime deps).

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $1"; }
fail() { echo -e "${RED}xx${NC} $1"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOBILE_DIR="$ROOT/mobile"
OUT_DIR="$ROOT/dist"
APK_OUT="$OUT_DIR/metanoia-android-debug.apk"

[ -d "$MOBILE_DIR" ] || fail "mobile/ directory not found"
command -v java >/dev/null 2>&1 || fail "java not found on PATH (need a JDK for Gradle)"

cd "$MOBILE_DIR"

if [ -n "${ANDROID_HOME:-}" ] && [ ! -f local.properties ]; then
  echo "sdk.dir=$ANDROID_HOME" > local.properties
fi

info "Running Gradle assembleDebug (debug-signed, sideload-only build)..."
./gradlew assembleDebug --no-daemon

APK_SRC="$MOBILE_DIR/app/build/outputs/apk/debug/app-debug.apk"
[ -f "$APK_SRC" ] || fail "expected APK at $APK_SRC after build"

mkdir -p "$OUT_DIR"
cp "$APK_SRC" "$APK_OUT"

SIZE="$(du -sh "$APK_OUT" | cut -f1)"
info "Done: $APK_OUT ($SIZE) — DEBUG-SIGNED, sideload only, not a Play Store release"
