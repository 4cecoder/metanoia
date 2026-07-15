#!/usr/bin/env bash
# MSYS2 names import libraries libfoo.dll.a but Zig looks for libfoo.a.
# Create symlinks so Zig's linker can find them.
set -euo pipefail
for dir in /ucrt64/lib /mingw64/lib /mingw32/lib; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.dll.a; do
    [ -f "$f" ] || continue
    base="$(basename "$f" .dll.a)"
    target="$dir/$base.a"
    [ -e "$target" ] || ln -s "$f" "$target"
  done
done
