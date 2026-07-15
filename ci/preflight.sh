#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}❯${NC} $1"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; }

info "Metanoia — CI Preflight Check"
echo ""

OS="$(uname -s)"
ARCH="$(uname -m)"
HAS_DOCKER=false
HAS_KVM=false
HAS_NESTED=false

# ── Docker ─────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
    HAS_DOCKER=true
    ok "Docker found: $(docker --version)"
else
    fail "Docker not found. Install Docker Desktop."
fi

# ── KVM (Linux hosts only) ─────────────────────────────────────
if [ "$OS" = "Linux" ]; then
    if [ -e /dev/kvm ]; then
        HAS_KVM=true
        ok "/dev/kvm available"
    else
        warn "/dev/kvm not found (KVM acceleration unavailable)"
    fi

    if [ -f /sys/module/kvm_intel/parameters/nested ] || [ -f /sys/module/kvm_amd/parameters/nested ]; then
        HAS_NESTED=true
        ok "Nested virtualization available"
    fi
fi

echo ""

# ── Available pipelines ────────────────────────────────────────
info "Available pipelines:"
echo ""

if $HAS_DOCKER; then
    echo "  ${GREEN}docker compose --profile check run crosscheck${NC}"
    echo "  → Cross-compile Zig for Windows target (any host)"
    echo ""

    echo "  ${GREEN}docker compose --profile check run wizard${NC}"
    echo "  → Validate C# setup wizard compiles via Mono (any host)"
    echo ""

    if [ "$OS" = "Linux" ] && $HAS_KVM; then
        echo "  ${GREEN}docker compose -f docker-compose.yml -f ci/docker-compose.windows.yml up windows${NC}"
        echo "  → Boot Windows 11 VM with KVM acceleration (Linux only)"
        echo ""
    else
        warn "Windows VM pipeline requires Linux host with KVM."
        warn "  Skipped (current: $OS, KVM: $HAS_KVM)"
        echo ""
    fi
fi

# ── Quick reference ────────────────────────────────────────────
info "Quick start:"
echo "  docker compose --profile check run crosscheck"
echo "  docker compose --profile check run wizard"
echo ""
