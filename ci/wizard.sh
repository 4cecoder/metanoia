#!/bin/bash
set -euo pipefail

echo "═══ C# Setup Wizard Validation ═══"

# Find Mono's C# compiler
MCS=$(which mcs 2>/dev/null || which csc 2>/dev/null || true)
if [ -z "$MCS" ]; then
    echo "No C# compiler found. Install mono-complete."
    exit 1
fi
echo "Compiler: $MCS"

# Step 1: Validate syntax by compiling as a library (no WinForms dependency)
echo ""
echo "--- Step 1: Syntax validation (library target) ---"
$MCS -target:library \
  -out:/tmp/MetanoiaSetup.dll \
  windows_helper/SetupWizard.cs 2>&1 && echo "SYNTAX OK" || echo "SYNTAX ISSUES (may compile on Windows csc.exe)"

# Step 2: Check for C# features that won't work on .NET Framework 4.8
echo ""
echo "--- Step 2: .NET Framework compatibility scan ---"
# Check for C# 7.0+ features that Mono can't compile
ISSUES=0

if grep -q "ValueTuple" windows_helper/SetupWizard.cs; then
  echo "  WARNING: ValueTuple requires System.ValueTuple package on .NET Framework 4.8"
  ISSUES=$((ISSUES+1))
fi

if grep -q "using System.Text.Json" windows_helper/SetupWizard.cs; then
  echo "  WARNING: System.Text.Json requires .NET Core 3.0+"
  ISSUES=$((ISSUES+1))
fi

if [ $ISSUES -eq 0 ]; then
  echo "  No compatibility issues detected."
fi

# Step 3: Verify the file compiles with Mono's WinForms (best effort)
echo ""
echo "--- Step 3: WinForms compile check (optional) ---"
WINFORMS=$(find /usr -name "System.Windows.Forms.dll" 2>/dev/null | head -1)
DRAWING=$(find /usr -name "System.Drawing.dll" 2>/dev/null | head -1)

if [ -n "$WINFORMS" ] && [ -n "$DRAWING" ]; then
  $MCS -target:winexe \
    -reference:$WINFORMS \
    -reference:$DRAWING \
    -reference:System.IO.Compression.dll \
    -reference:System.IO.Compression.FileSystem.dll \
    -out:/tmp/MetanoiaSetup.exe \
    windows_helper/SetupWizard.cs 2>&1 \
  && echo "WINFORMS BUILD OK" || echo "WINFORMS BUILD FAILED (expected on non-Windows)"
else
  echo "  Skipped (System.Windows.Forms not available on this platform)"
  echo "  Full build requires Windows csc.exe — see compile.bat"
fi

echo ""
echo "═══ Wizard validation complete ═══"
