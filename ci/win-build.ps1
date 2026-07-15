<#
.SYNOPSIS
    Build Metanoia inside the dockur/windows container.
    Runs automatically on VM boot via /storage/ mount.
.DESCRIPTION
    Installs Zig, MSYS2, GTK4, and runs zig build.
    Logs all output to C:\build.log
#>

$log = "C:\build.log"
function Log($msg) {
    $line = "[$(Get-Date -Format HH:mm:ss)] $msg"
    Write-Host $line
    Add-Content -Path $log -Value $line
}

# ── 1. Install Zig ──────────────────────────────────────────────
Log "=== Metanoia Windows Build ==="
Log "Step 1/5: Installing Zig..."

$zigIndexUrl = "https://ziglang.org/download/index.json"
$zigDir = "$env:USERPROFILE\zig"

try {
    Log "Fetching latest Zig version..."
    $index = Invoke-RestMethod -Uri $zigIndexUrl -ErrorAction Stop
    $zigUrl = $index.master."x86_64-windows".tarball
    Log "Latest Zig: $zigUrl"
    
    $zip = "$env:TEMP\zig.zip"
    Invoke-WebRequest -Uri $zigUrl -OutFile $zip -ErrorAction Stop
    Expand-Archive -Path $zip -DestinationPath $zigDir -Force
    $zigExe = Get-ChildItem -Path $zigDir -Recurse -Filter "zig.exe" | Select-Object -First 1 -ExpandProperty FullName
    $env:PATH += ";$(Split-Path $zigExe)"
    $ver = & $zigExe version
    Log "Zig $ver installed at $zigExe"
} catch {
    Log "Zig install FAILED: $_"
    exit 1
}

# ── 2. Install MSYS2 ───────────────────────────────────────────
Log "Step 2/5: Installing MSYS2..."

$msys2Url = "https://github.com/msys2/msys2-installer/releases/download/2025-04-14/msys2-x86_64-20250414.exe"
$msys2Installer = "$env:TEMP\msys2.exe"
$msys2Dir = "C:\msys64"

try {
    Invoke-WebRequest -Uri $msys2Url -OutFile $msys2Installer -ErrorAction Stop
    Start-Process -Wait -FilePath $msys2Installer -ArgumentList "install", "--quiet", "--root", $msys2Dir
    Log "MSYS2 installed"
} catch {
    Log "MSYS2 install FAILED: $_"
    exit 1
}

# ── 3. Install GTK4 via pacman ──────────────────────────────────
Log "Step 3/5: Installing GTK4 + dependencies..."

$pacman = "$msys2Dir\ucrt64.exe"
$pkgs = "mingw-w64-ucrt-x86_64-gtk4 mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-sqlite3 mingw-w64-ucrt-x86_64-curl"

try {
    Start-Process -Wait -FilePath $pacman -ArgumentList "-Syu --noconfirm" -NoNewWindow
    Start-Process -Wait -FilePath $pacman -ArgumentList "-S --needed --noconfirm $pkgs" -NoNewWindow
    $env:PATH += ";$msys2Dir\ucrt64\bin"
    $gtkVer = & "$msys2Dir\ucrt64\bin\pkg-config.exe" --modversion gtk4 2>$null
    Log "GTK4 $gtkVer installed"
} catch {
    Log "GTK4 install FAILED: $_"
    exit 1
}

# ── 4. Build ────────────────────────────────────────────────────
Log "Step 4/5: Building Metanoia..."

$workspace = "C:\workspace"
if (-not (Test-Path $workspace)) {
    Log "Workspace not found at $workspace — looking for mounted volume..."
    # Try common mount points
    $candidates = @("C:\workspace", "D:\workspace", "E:\workspace")
    foreach ($c in $candidates) {
        if (Test-Path "$c\build.zig") { $workspace = $c; break }
    }
}

try {
    Push-Location $workspace
    Log "Building in $workspace..."
    & $zigExe build 2>&1 | ForEach-Object { Log $_ }
    if ($LASTEXITCODE -eq 0) {
        Log "BUILD SUCCESS"
    } else {
        Log "BUILD FAILED (exit $LASTEXITCODE)"
    }
    Pop-Location
} catch {
    Log "Build threw exception: $_"
}

# ── 5. Results ──────────────────────────────────────────────────
Log "Step 5/5: Build complete."
if (Test-Path "$workspace\zig-out\bin\metanoia.exe") {
    $size = (Get-Item "$workspace\zig-out\bin\metanoia.exe").Length
    Log "metanoia.exe created: $size bytes"
} else {
    Log "metanoia.exe NOT FOUND"
}

Log "=== Build log written to $log ==="
