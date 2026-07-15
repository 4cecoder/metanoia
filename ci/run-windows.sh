#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}❯${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }

info "Metanoia Windows Build Pipeline"
echo ""

# ── 1. Check KVM ───────────────────────────────────────────────
if [ ! -e /dev/kvm ]; then
  warn "/dev/kvm not found — VM will be extremely slow"
  warn "Enable virtualization in BIOS or run on a Linux host with KVM"
fi

# ── 2. Start Windows VM ────────────────────────────────────────
info "Starting Windows 11 VM..."
cd "$(dirname "$0")/.."
docker compose -f ci/docker-compose.windows.yml up -d 2>&1 | grep -v "Network\|Volume\|Container"

info "Windows is booting (first boot: 5-10 min)..."
info "  WebUI: http://localhost:8006"
info "  RDP:   localhost:3389 (user: metanoia / pass: metanoia)"

# ── 3. Wait for build to finish ─────────────────────────────────
info "Waiting for build to complete..."
CONTAINER="metanoia-windows"
START=$(date +%s)
TIMEOUT=3600  # 1 hour max

while true; do
  # Check if container is still running
  if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER"; then
    warn "Container stopped unexpectedly"
    docker logs "$CONTAINER" 2>&1 | tail -20
    exit 1
  fi

  # Try to fetch build log (file written by win-build.ps1 on C:\ = /storage/)
  if docker exec "$CONTAINER" powershell -Command "Test-Path C:\\build.log" 2>/dev/null | grep -q "True"; then
    echo ""
    info "Build log found! Fetching..."
    docker cp "$CONTAINER":/storage/build.log ./zig-out/build.log 2>/dev/null || true
    info "Log saved to zig-out/build.log"
    break
  fi

  # Timeout check
  ELAPSED=$(( $(date +%s) - START ))
  if [ $ELAPSED -gt $TIMEOUT ]; then
    warn "Timeout after ${TIMEOUT}s"
    exit 1
  fi

  printf "\r  Elapsed: ${ELAPSED}s (checking every 15s)..."
  sleep 15
done

echo ""
info "=== RESULTS ==="
if [ -f ./zig-out/bin/metanoia.exe ]; then
  ls -lh ./zig-out/bin/metanoia.exe
  info "Build successful! Binary at zig-out/bin/metanoia.exe"
else
  warn "Binary not found — check zig-out/build.log"
  cat ./zig-out/build.log 2>/dev/null | tail -30
fi

# ── 4. Optional: stop VM ────────────────────────────────────────
echo ""
info "Windows VM still running (http://localhost:8006)"
info "Stop it with: docker compose -f ci/docker-compose.windows.yml down"
