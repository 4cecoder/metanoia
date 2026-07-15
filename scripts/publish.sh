#!/usr/bin/env bash
set -euo pipefail

# Publish a new release.
# This pushes a git tag, which triggers .github/workflows/release.yml
# to build on Windows and create the GitHub Release automatically.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}❯${NC} $1"; }

VERSION="v$(date +%Y.%m.%d)-$(git rev-parse --short HEAD)"

info "Tagging: $VERSION"
git tag "$VERSION"
git push origin "$VERSION"

info "GitHub Actions will build Windows release at:"
info "  https://github.com/4cecoder/metanoia/actions"
info "When complete, release appears at:"
info "  https://github.com/4cecoder/metanoia/releases/tag/$VERSION"
