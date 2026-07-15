<#
.SYNOPSIS
    Build Metanoia inside dockur/windows container.
    Clones repo, installs Zig/MSYS2/GTK4, builds, copies output.
    Auto-runs on boot via /storage/ mount. Logs to C:\build.log
#>

$log = "C:\build.log"
$workspace = "C:\project"
$cache = "$workspace\.cache"
$zigDir = "$cache\zig"
$msysDir = "$cache\msys64"

function Log($msg) {
    $line = "[$(Get-Date -Format HH:mm:ss)] $msg"
    Write-Host $line
    Add-Content -Path $log -Value $line
}

Log "=== Metanoia Windows Build ==="

# Clone repo (source not accessible from inside Windows VM otherwise)
if (-not (Test-Path "$workspace\build.zig")) {
    Log "Cloning metanoia..."
    git clone --depth 1 https://github.com/4cecoder/metanoia.git $workspace 2>&1 | ForEach-Object { Log $_ }
}
$commit = git -C $workspace rev-parse --short HEAD 2>$null
Log "Repo: $workspace (commit: $commit)"

# ── 1. Zig ─────────────────────────────────────────────────────
Log "Step 1/5: Zig..."
if (Test-Path "$zigDir\zig.exe") {
    $zigExe = (Get-ChildItem $zigDir -Recurse -Filter "zig.exe").FullName | Select-Object -First 1
    Log "Cached: $( & $zigExe version )"
} else {
    Log "Downloading latest Zig..."
    $index = Invoke-RestMethod -Uri "https://ziglang.org/download/index.json"
    $url = $index.master."x86_64-windows".tarball
    $zip = "$env:TEMP\zig.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $zigDir -Force
    $zigExe = (Get-ChildItem $zigDir -Recurse -Filter "zig.exe").FullName | Select-Object -First 1
    Log "Installed: $( & $zigExe version )"
}
$env:PATH = "$(Split-Path $zigExe);$env:PATH"

# ── 2. MSYS2 ────────────────────────────────────────────────────
Log "Step 2/5: MSYS2..."
if (-not (Test-Path "$msysDir\ucrt64.exe")) {
    $url = "https://github.com/msys2/msys2-installer/releases/download/2025-04-14/msys2-x86_64-20250414.exe"
    $exe = "$env:TEMP\msys2.exe"
    Invoke-WebRequest -Uri $url -OutFile $exe
    Start-Process -Wait -FilePath $exe -ArgumentList "install", "--quiet", "--root", $msysDir
    Log "Installed"
} else { Log "Cached" }

# ── 3. GTK4 ─────────────────────────────────────────────────────
Log "Step 3/5: GTK4..."
$pacman = "$msysDir\ucrt64.exe"
$pkgs = "mingw-w64-ucrt-x86_64-gtk4 mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-sqlite3 mingw-w64-ucrt-x86_64-curl"
$env:PATH += ";$msysDir\ucrt64\bin"
$gtkVer = & "$msysDir\ucrt64\bin\pkg-config.exe" --modversion gtk4 2>$null
if (-not $gtkVer) {
    Start-Process -Wait -FilePath $pacman -ArgumentList "-Syu --noconfirm" -NoNewWindow
    Start-Process -Wait -FilePath $pacman -ArgumentList "-S --needed --noconfirm $pkgs" -NoNewWindow
    $gtkVer = & "$msysDir\ucrt64\bin\pkg-config.exe" --modversion gtk4 2>$null
    Log "Installed GTK4 $gtkVer"
} else { Log "GTK4 $gtkVer — cached" }

# ── 4. Build + Copy DLLs ───────────────────────────────────────
Log "Step 4/5: Build..."
Push-Location $workspace
& $zigExe build 2>&1 | ForEach-Object { Log $_ }
$buildOk = ($LASTEXITCODE -eq 0)
if ($buildOk) {
    Log "BUILD SUCCESS"
    $outDir = "$workspace\zig-out\bin"
    if (Test-Path "$msysDir\ucrt64\bin") {
        $count = 0
        foreach ($dll in (Get-ChildItem "$msysDir\ucrt64\bin\*.dll")) {
            Copy-Item $dll.FullName "$outDir\" -Force; $count++
        }
        Log "Copied $count DLLs to zig-out\bin"
    }
} else { Log "BUILD FAILED (exit $LASTEXITCODE)" }
Pop-Location

# ── 5. Smoke test: run the exe ──────────────────────────────────
Log "Step 5/6: Smoke test..."
$exe = "$workspace\zig-out\bin\metanoia.exe"
if (Test-Path $exe) {
    Log "Launching metanoia.exe..."
    $proc = Start-Process -FilePath $exe -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 5
    if (-not $proc.HasExited) {
        Log "  metanoia.exe is running (PID: $($proc.Id)) — killing..."
        $proc.Kill()
        Log "  Killed successfully"
    } else {
        Log "  metanoia.exe exited immediately (code: $($proc.ExitCode))"
    }
} else {
    Log "  metanoia.exe not found — skipping smoke test"
}

# ── 6. Done ─────────────────────────────────────────────────────
Log "=== Build complete ==="
