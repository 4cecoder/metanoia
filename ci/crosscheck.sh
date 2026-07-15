#!/bin/bash
set -euo pipefail

echo "═══ Metanoia Cross-Compile Check ═══"
echo "Host: $(uname -a)"
echo "Target: x86_64-windows-gnu"

zig version

echo ""
echo "--- Step 1: Native build ---"
zig build 2>&1

echo ""
echo "--- Step 2: Windows cross-compile ---"
zig build -Dtarget=x86_64-windows-gnu 2>&1 || \
  echo "(link failure expected — no Windows GTK4 libs on cross-host)"

echo ""
echo "═══ Cross-compile check complete ═══"
