<#
.SYNOPSIS
    Bootstrap Metanoia development environment on Windows 11.
.DESCRIPTION
    Installs MSYS2, GTK4, Zig (if missing), and verifies the build.
    Run this from PowerShell as Administrator.
#>

$ErrorActionPreference = "Stop"
$MSYS2_URL = "https://github.com/msys2/msys2-installer/releases/download/2025-04-14/msys2-x86_64-20250414.exe"
$MSYS2_PATH = "C:\msys64"
$UCRT64_BIN = "$MSYS2_PATH\ucrt64\bin"
$ZIG_URL = "https://ziglang.org/download/0.17.0/zig-windows-x86_64-0.17.0.zip"
$ZIG_PATH = "$env:USERPROFILE\zig"

function Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }

# ── 1. Check Zig ────────────────────────────────────────────────
Step "1/4: Checking Zig..."
if (Get-Command zig -ErrorAction SilentlyContinue) {
    Write-Host "  Zig found: $(zig version)" -ForegroundColor Green
} else {
    Write-Host "  Zig not found — downloading to $ZIG_PATH ..."
    $zip = "$env:TEMP\zig.zip"
    Invoke-WebRequest -Uri $ZIG_URL -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $ZIG_PATH -Force
    $zig_exe = "$ZIG_PATH\zig-windows-x86_64-0.17.0\zig.exe"
    [Environment]::SetEnvironmentVariable("PATH", "$env:PATH;$ZIG_PATH\zig-windows-x86_64-0.17.0", "User")
    Write-Host "  Added zig to PATH. Restart terminal or run: `$env:PATH += ';$ZIG_PATH\zig-windows-x86_64-0.17.0'" -ForegroundColor Yellow
}

# ── 2. Check / Install MSYS2 ────────────────────────────────────
Step "2/4: Checking MSYS2..."
if (Test-Path "$MSYS2_PATH\ucrt64.exe") {
    Write-Host "  MSYS2 found at $MSYS2_PATH" -ForegroundColor Green
} else {
    Write-Host "  Downloading MSYS2 installer..."
    $installer = "$env:TEMP\msys2.exe"
    Invoke-WebRequest -Uri $MSYS2_URL -OutFile $installer
    Write-Host "  Running installer (silent)..."
    Start-Process -Wait -FilePath $installer -ArgumentList "install", "--quiet", "--root", $MSYS2_PATH
}

# ── 3. Install GTK4 via pacman ──────────────────────────────────
Step "3/4: Installing GTK4 + sqlite3..."
$pacman = "$MSYS2_PATH\ucrt64.exe"
$pkgs = "mingw-w64-ucrt-x86_64-gtk4 mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-sqlite3"
Start-Process -Wait -FilePath $pacman -ArgumentList "-Syu --noconfirm"
Start-Process -Wait -FilePath $pacman -ArgumentList "-S --needed --noconfirm $pkgs"

Write-Host "  Adding UCRT64 bin to system PATH..." -ForegroundColor Yellow
$current = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($current -notlike "*$UCRT64_BIN*") {
    [Environment]::SetEnvironmentVariable("PATH", "$current;$UCRT64_BIN", "User")
}
# Also set for current session
$env:PATH += ";$UCRT64_BIN"

# ── 4. Verify ───────────────────────────────────────────────────
Step "4/4: Verifying setup..."
try {
    $gtk_ver = & pkg-config --modversion gtk4 2>$null
    Write-Host "  GTK4 $gtk_ver — OK" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: pkg-config not found. Ensure $UCRT64_BIN is on PATH." -ForegroundColor Red
}
try {
    $zig_ver = & zig version
    Write-Host "  Zig $zig_ver — OK" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: zig not found on PATH." -ForegroundColor Red
}

# ── 5. Build test ───────────────────────────────────────────────
Step "Build test: running 'zig build'..."
try {
    $output = & zig build 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  BUILD SUCCESS — zig-out/bin/metanoia.exe created." -ForegroundColor Green
    } else {
        Write-Host "  BUILD FAILED (exit $LASTEXITCODE). Check errors above." -ForegroundColor Red
        Write-Host $output
    }
} catch {
    Write-Host "  BUILD FAILED with exception: $_" -ForegroundColor Red
}

Write-Host "`nDone. Open VS Code in this folder and press Ctrl+Shift+B to build." -ForegroundColor Cyan
