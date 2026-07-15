#!/usr/bin/env bash
# MSYS2 names import libraries libfoo.dll.a but Zig looks for libfoo.a.
# Copy .dll.a → .a so Zig's native linker finds them.
set -euo pipefail
for dir in /ucrt64/lib /mingw64/lib /mingw32/lib; do
  [ -d "$dir" ] || { echo "skip $dir (not found)"; continue; }
  count=0
  for f in "$dir"/*.dll.a; do
    [ -f "$f" ] || continue
    target="${f%.dll.a}.a"
    if [ ! -e "$target" ]; then
      cp "$f" "$target" && count=$((count + 1))
    fi
  done
  echo "linked $count .dll.a → .a in $dir"
done