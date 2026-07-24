#!/bin/bash
set -e

echo "=== Metanoia AppImage Debugging ==="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "Host: $(hostname)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"

echo "=== Downloading AppImage ==="
curl -fsSL "https://github.com/4cecoder/metanoia/releases/download/latest/Metanoia-x86_64.AppImage" -o metanoia.appimage
chmod +x metanoia.appimage
echo "AppImage size: $(du -h metanoia.appimage | cut -f1)"

echo "=== Binary analysis ==="
file metanoia.appimage
echo ""

echo "=== Library dependencies ==="
ldd metanoia.appimage 2>/dev/null | head -30 || echo "ldd not found"
echo ""

echo "=== Start virtual X server ==="
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!
sleep 1
export DISPLAY=:99
echo "Virtual X server started (PID: $XVFB_PID)"
echo ""

echo "=== Extract and check structure ==="
mkdir -p extracted && cd extracted
../metanoia.appimage --appimage-extract
echo "Contents of usr/lib/gtk-4.0:"
ls -la squashfs-root/usr/lib/gtk-4.0/ 2>/dev/null | head -10 || echo "No gtk-4.0 directory"
echo ""
echo "=== Check for libfribidi ==="
find squashfs-root -name "libfribidi*" | head -5
echo ""
echo "=== Check for GStreamer media backend ==="
find squashfs-root -name "*media-gstreamer*" -o -name "*gstreamer*.so" | head -10
echo ""
find squashfs-root -name "*.so" | head -10
echo ""

echo "=== HEADLESS test (5s timeout) ==="
timeout 5 bash -c "cd squashfs-root; ./AppRun" 2>&1 || echo "Exit code: $?"
echo ""

echo "=== Run with strace (first 50 lines) ==="
timeout 5 bash -c "cd squashfs-root; strace -o /tmp/strace.log ./AppRun" 2>&1 || echo "Exit code: $?"
head -50 /tmp/strace.log 2>/dev/null || echo "No strace output"
echo ""

echo "=== Cleanup ==="
kill $XVFB_PID 2>/dev/null || true
cd /tmp && rm -rf /metanoia-debug/extracted
echo "=== Debug output saved to: /tmp/strace.log ==="