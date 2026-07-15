#!/bin/bash
set -euo pipefail

echo "═══ C# Setup Wizard Validation ═══"

# Mono's C# compiler
MCS=$(which mcs 2>/dev/null || which csc 2>/dev/null || true)
if [ -z "$MCS" ]; then
    echo "No C# compiler found. Install mono-complete."
    exit 1
fi
echo "Compiler: $MCS"

echo ""
echo "--- Compiling SetupWizard.cs ---"
$MCS -target:winexe \
  -reference:System.IO.Compression.dll \
  -reference:System.IO.Compression.FileSystem.dll \
  -out:/tmp/MetanoiaSetup.exe \
  windows_helper/SetupWizard.cs 2>&1

echo ""
echo "--- Checking output ---"
if [ -f /tmp/MetanoiaSetup.exe ]; then
    SZ=$(stat -f%z /tmp/MetanoiaSetup.exe 2>/dev/null || stat -c%s /tmp/MetanoiaSetup.exe 2>/dev/null)
    echo "SUCCESS: MetanoiaSetup.exe ($SZ bytes)"
    file /tmp/MetanoiaSetup.exe
else
    echo "FAILED: no output produced"
    exit 1
fi

echo ""
echo "═══ Wizard validation complete ═══"
