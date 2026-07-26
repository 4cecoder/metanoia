#!/bin/bash
# test-android.sh — Run Android unit tests locally before pushing to CI.
# Usage:  cd mobile && bash test-android.sh
# Prereqs: Java 17+, Android SDK at /opt/android-sdk (with platform 35 + build-tools 35)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Ensure local.properties points at the system Android SDK
echo "sdk.dir=/opt/android-sdk" > local.properties

echo "==> Running Android unit tests (testDebugUnitTest)..."
./gradlew testDebugUnitTest --no-daemon "$@"

echo ""
echo "✅ All Android unit tests passed!"
