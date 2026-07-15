#!/bin/bash
# ============================================================================
# Metanoia CI Pipeline
# Runs the full local CI cycle and reports pass/fail for each step.
#
# Steps:
#   1. Cross-compile check      (Docker)
#   2. Native build             (zig build)
#   3. Windows VM build         (if container running)
#   4. Tests                    (pytest + zig test)
#
# Usage:
#   ./scripts/ci.sh            # run everything
#   ./scripts/ci.sh --watch    # re-run on file changes (requires entr)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

PASS=0
FAIL=0
FAILED_STEPS=""

# ── Colours & helpers ──────────────────────────────────────────────────

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

header()  { echo ""; echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}   $1${NC}"; echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"; }
step()    { echo ""; echo -e "${YELLOW}[STEP]${NC} $1"; }
ok()      { echo -e "  ${GREEN}✓ PASS${NC}"; PASS=$((PASS+1)); }
fail()    { echo -e "  ${RED}✗ FAIL${NC}"; FAIL=$((FAIL+1)); FAILED_STEPS="$FAILED_STEPS\n    - $1"; }
skip()    { echo -e "  ${YELLOW}∼ SKIP${NC}"; }
summary() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}   CI Summary${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}Passed:${NC} $PASS    ${RED}Failed:${NC} $FAIL"
    if [ -n "$FAILED_STEPS" ]; then
        echo -e "  ${RED}Failed steps:${NC}$FAILED_STEPS"
    fi
    echo ""
    if [ "$FAIL" -gt 0 ]; then
        echo -e "${RED}${BOLD}CI FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}${BOLD}CI PASSED${NC}"
        exit 0
    fi
}

# ── Watch mode (requires entr) ─────────────────────────────────────────

if [ "${1:-}" = "--watch" ]; then
    if ! command -v entr &>/dev/null; then
        echo "Error: --watch requires entr (install with: sudo apt install entr)" >&2
        exit 1
    fi
    echo "Watching for changes in $PROJECT_DIR ..."
    find "$PROJECT_DIR" -type f \( -name '*.zig' -o -name '*.py' -o -name '*.ps1' -o -name '*.sh' -o -name 'Makefile' -o -name 'Dockerfile*' -o -name 'docker-compose*.yml' \) \
        ! -path '*/.git/*' ! -path '*/zig-out/*' ! -path '*/.zig-cache/*' |
        entr -c "$0"
    exit $?
fi

# ============================================================================
# Step 1 — Cross-compile check
# ============================================================================
header "1/4  Cross-compile Check"
step "Building and running Docker crosscheck container..."
if make crosscheck 2>&1; then
    ok
else
    fail "cross-compile check"
fi

# ============================================================================
# Step 2 — Native build
# ============================================================================
header "2/4  Native Build"
step "Running zig build..."
if make build 2>&1; then
    ok
else
    fail "native build"
fi

# ============================================================================
# Step 3 — Windows VM build (only if the container is running)
# ============================================================================
header "3/4  Windows VM Build"
WIN_RUNNING="$(docker inspect --format='{{.State.Status}}' metanoia-windows 2>/dev/null || true)"
if [ "$WIN_RUNNING" = "running" ]; then
    step "metanoia-windows container is running — triggering build..."
    if make windows-build 2>&1; then
        ok
    else
        fail "windows-vm build"
    fi
else
    skip
    echo "  (metanoia-windows container not running — skipping Windows build)"
    echo "  Start it with: make windows-vm"
fi

# ============================================================================
# Step 4 — Tests
# ============================================================================
header "4/4  Tests"
step "Running unit tests (pytest + zig test)..."
if make test 2>&1; then
    ok
else
    fail "tests"
fi

# ============================================================================
# Summary
# ============================================================================
summary
