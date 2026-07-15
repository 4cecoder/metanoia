#!/bin/bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")"

export ORT_LOGGING_LEVEL=3

exec uv run python tools/tts_server.py
