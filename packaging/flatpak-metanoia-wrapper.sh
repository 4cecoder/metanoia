#!/bin/sh
# packaging/flatpak-metanoia-wrapper.sh
#
# Installed as /app/bin/metanoia (the flatpak's Exec= target) by
# packaging/com.bytecats.metanoia.yml's build-commands. NOT the real
# binary — that's /app/lib/metanoia/metanoia-bin.
#
# Two problems this works around, both stemming from the same root cause
# described in docs/PACKAGING.md's "macOS vs Linux asymmetry" section:
# src/main.zig opens "data/bible.db" (and src/models/config.zig opens/
# creates "data/config.json", and src/main.zig loads
# "assets/themes/tokyo-night.css") via bare relative paths resolved against
# the process's cwd, with zero XDG-style resolution logic. There's no
# equivalent problem on macOS (resolveBundleRoot() in main.zig chdirs into
# the .app bundle's Resources dir) and packaging/build-linux.sh solves it
# for the plain tarball/.deb case with a thin `cd /opt/metanoia && exec ...`
# wrapper — same idea here, but with one extra wrinkle Flatpak adds:
#
#   1. Same as build-linux.sh: whatever launches this process (a desktop
#      launcher, an app grid icon, `flatpak run`) could have any cwd at all,
#      so we must cd somewhere specific before exec'ing the real binary.
#
#   2. UNLIKE a native Linux install, /app is *always* mounted read-only at
#      runtime in a Flatpak sandbox (this is enforced by Flatpak itself, not
#      just a permissions convention we could chmod around, the way you
#      technically could — even if you shouldn't — with /opt/metanoia on a
#      native install). So "cd /app/lib/metanoia && exec metanoia-bin" alone
#      would let bible.db open fine (read-only is fine for reads) but
#      config.zig's Dir.cwd().createFile("data/config.json", ...) would
#      always fail (silently, per config.zig's own error handling — it just
#      never persists settings) since /app/lib/metanoia/data is read-only.
#
# Fix: cd into $XDG_DATA_HOME/metanoia instead, which Flatpak *always* maps
# to a real writable, per-app directory (~/.var/app/<app-id>/data on the
# host) with no extra finish-args permission needed — this is automatic for
# every Flatpak app's own XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME, it
# isn't something we had to request. We populate a "data" subdirectory
# there with symlinks to the real (read-only, inside /app) bible.db/
# voices.json/wav files — cheap, no copying multi-MB files on every launch —
# so "data/bible.db" still resolves and opens fine through the symlink,
# while "data/config.json" has nowhere existing to collide with: it gets
# created as a brand-new regular file directly in that writable directory.
# assets/ has no equivalent write requirement (nothing in src/ ever creates
# files under assets/), so it's just one whole-directory symlink.

set -e

REAL_BIN="/app/lib/metanoia/metanoia-bin"
PAYLOAD="/app/lib/metanoia"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/metanoia"

mkdir -p "$DATA_HOME/data"

if [ ! -e "$DATA_HOME/assets" ]; then
  ln -s "$PAYLOAD/assets" "$DATA_HOME/assets"
fi

for f in "$PAYLOAD"/data/*; do
  b="$(basename "$f")"
  [ -e "$DATA_HOME/data/$b" ] || ln -sf "$f" "$DATA_HOME/data/$b"
done

cd "$DATA_HOME"
exec "$REAL_BIN" "$@"
