#!/usr/bin/env bash
# packaging/build-windows.sh
#
# Assembles a REAL, standalone Windows distribution folder from an already
# -built zig-out/bin/metanoia.exe: the app's own exe, its full non-system
# DLL dependency closure, and the GTK4/GDK-Pixbuf runtime resources GTK
# needs to discover at runtime (icon theme + pixbuf loaders) — none of
# which the previous "Package" step (a bare `Copy-Item zig-out\bin\*`) did.
# Without this, the shipped zip could not run at all on a clean Windows
# machine without a full MSYS2 UCRT64 install already present system-wide.
#
# MUST be run from inside an MSYS2 bash shell (CI's `shell: msys2 {0}`,
# same shell `ci/fix-msys2-libs.sh` and the `zig build` step before it
# already use) — NOT plain pwsh/cmd. Being inside msys2 bash is what makes
# `/ucrt64/...` and `/c/Windows/...` valid, live POSIX paths without any
# MSYS2_ROOT Windows-path translation (unlike build.zig's Windows block,
# whose linker runs *outside* msys2's POSIX layer — ldd/bash/this script
# run *inside* it, so plain `/ucrt64/bin` etc. always resolve correctly
# regardless of whether the real install root is "C:\msys64" or
# "D:\a\_temp\msys64").
#
# Usage: bash packaging/build-windows.sh
#   (optionally: DIST_ROOT=/some/other/path bash packaging/build-windows.sh)
#
# Prerequisite: `zig build` has already produced zig-out/bin/metanoia.exe
# (this script does not build it — that stays a separate CI step, same
# division of labor the CI job already had).
#
# ── What this script could NOT verify (read before trusting it blindly) ──
# There is no Windows/MSYS2 environment available in the sandbox this was
# written in (confirmed: `uname` reports Darwin, no `wine`/`wine64` on
# PATH). Everything below is based on documented `ldd`/GLib/gdk-pixbuf
# behavior researched via web search (see the task's final report for
# sources), reasoned through carefully, and checked with `bash -n` — but
# has NEVER been run against a real metanoia.exe. The calling session will
# run this for real on Windows CI and iterate on whatever breaks, exactly
# like the four rounds of build.zig fixes that got the exe compiling and
# linking in the first place. Treat every comment below tagged
# "UNVERIFIED" as a real, specific place this could still be wrong.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}!!${NC} $1"; }
fail() { echo -e "${RED}xx${NC} $1"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Metanoia"
EXE_NAME="metanoia.exe"

[ -n "${MSYSTEM:-}" ] || fail "run this from an MSYS2 bash shell (\$MSYSTEM is unset) — see header comment"

# UCRT64 is what this repo's CI (.github/workflows/release-latest.yml,
# release.yml) sets up via msys2/setup-msys2's `msystem: UCRT64`; mingw64
# is kept as a fallback for a local dev's differently-configured MSYS2
# install, matching the same UCRT64-then-MinGW64 fallback order build.zig
# already uses for its library search paths.
MSYS_PREFIX="/ucrt64"
[ -d "$MSYS_PREFIX/bin" ] || MSYS_PREFIX="/mingw64"
[ -d "$MSYS_PREFIX/bin" ] || fail "neither /ucrt64 nor /mingw64 found — unexpected MSYS2 layout"
info "Using MSYS2 prefix: $MSYS_PREFIX"

EXE_SRC="$ROOT/zig-out/bin/${EXE_NAME}"
[ -f "$EXE_SRC" ] || fail "expected $EXE_SRC — run 'zig build' before this script"
[ -f "$ROOT/data/bible.db" ] || fail "data/bible.db is missing (should be checked out from git, see .gitignore's exception)"
[ -f "$ROOT/assets/metanoia.ico" ] || fail "assets/metanoia.ico missing"
command -v ldd >/dev/null 2>&1 || fail "ldd not found — should be present in any MSYS2 shell"

# Flat layout: metanoia.exe stays directly in $DIST_ROOT (NOT nested in a
# bin/ subfolder) — this deliberately matches the pre-existing convention
# both release workflows and the older scripts/package.sh already used
# (dist\Metanoia\metanoia.exe). It also happens to be the *correct* choice
# for GLib's own runtime prefix detection: per GLib's documented algorithm
# for g_win32_get_package_installation_directory_of_module(), if a running
# module's containing directory is named "bin" or "lib", GLib uses that
# directory's *parent* as the install prefix; for any OTHER directory name
# (our flat case), GLib uses the module's own directory AS the prefix
# directly. So keeping metanoia.exe flat here means GTK/GDK-Pixbuf will
# look for "$DIST_ROOT/lib/..." and "$DIST_ROOT/share/..." — exactly where
# section 3/4 below put them — with no bin/ nesting required. This also
# sidesteps a real trap: src/main.zig has NO resolveBundleRoot()-equivalent
# for Windows (that function is `if (builtin.os.tag != .macos) return;`),
# so "data/bible.db" and "assets/themes/tokyo-night.css" are opened as
# bare paths relative to the process's cwd — which Explorer sets to the
# .exe's own directory on double-click. A flat layout means cwd, GLib's
# prefix, and "where data/ and assets/ physically are" are all the SAME
# directory, so nothing needs to be duplicated or symlinked.
DIST_ROOT="${DIST_ROOT:-$ROOT/dist/${APP_NAME}}"

info "Assembling Windows distribution at $DIST_ROOT ..."
rm -rf "$DIST_ROOT"
mkdir -p "$DIST_ROOT"

cp "$EXE_SRC" "$DIST_ROOT/"
cp "$ROOT/assets/metanoia.ico" "$DIST_ROOT/"
cp -r "$ROOT/data" "$DIST_ROOT/data"
cp -r "$ROOT/assets" "$DIST_ROOT/assets"
[ -d "$ROOT/static" ] && cp -r "$ROOT/static" "$DIST_ROOT/static"

# ─────────────────────────────────────────────────────────────────────────
# 1. Recursive DLL dependency closure
# ─────────────────────────────────────────────────────────────────────────
# Approach and line-format assumptions researched (not verified live) from:
#   - MSYS2/MINGW-packages issue history confirming `ldd` marks a missing
#     dependency as "name.dll => not found" (this was a deliberate runtime
#     fix, not always true of very old MSYS2 installs).
#   - janw.name's "Collecting the DLLs Required by an MSYS2 Binary", whose
#     documented one-liner is:
#       ldd my-cool-program.exe | grep /mingw64 | awk '{print $3}' | ...
#     i.e. a resolved dependency line looks like:
#       "        name.dll => /ucrt64/bin/name.dll (0x180000000)"
#     That one-liner only walks ONE level (the direct deps of a single
#     binary) — it does not recurse into the DLLs it finds. Real apps'
#     dependency graphs are deeper than one level (e.g. libgtk-4-1.dll
#     itself depends on libpango-1.0-0.dll, libcairo-2.dll, etc., which
#     depend on further MSYS2 DLLs), so this script re-runs `ldd` on every
#     newly-discovered MSYS2 DLL until a fixed point (no new DLLs found) —
#     the standard pattern for this problem, and safe/idempotent even if a
#     given MSYS2 ldd build already returns a fully-transitive closure in
#     one call (the second pass then just finds nothing new).
#
# "System DLL, never bundle" vs "MSYS2 DLL, must bundle":
#   - Anything ldd resolves under $MSYS_PREFIX/bin (i.e. /ucrt64/bin or
#     /mingw64/bin) is MSYS2/MinGW-provided and MUST be bundled — it will
#     not exist on a clean Windows machine.
#   - Anything ldd resolves under a drive-letter path (/c/Windows/...,
#     case-insensitively — MSYS2 mounts C:\Windows as /c/Windows) is a real
#     Windows system DLL, present on every install, and must NOT be
#     bundled (bundling stale copies of core system DLLs like kernel32/
#     ntdll/user32 can cause the exact instability the task description
#     warned about).
#   - api-ms-win-*.dll / ext-ms-*.dll are "API Set" virtual redirections
#     resolved internally by ntdll at load time (confirmed via web search:
#     this is well-documented MinGW/UCRT behavior, not a metanoia-specific
#     quirk) — they have no backing file to find or copy even on the
#     machine that built them, so `ldd` reporting them "=> not found" is
#     EXPECTED and must not be treated as a real missing dependency. (One
#     real caveat: these API Set stubs require Windows 7 SP1 + KB2999226
#     or Windows 8.1+/10+ to resolve at runtime — a total non-issue for
#     GitHub Actions' windows-latest runner or any realistically current
#     end-user machine, but worth knowing if this is ever run targeting
#     very old Windows.)
#   - Anything else ldd reports as a real path that is neither of the
#     above two prefixes is UNEXPECTED — this script does not silently
#     bundle it (an allow-list, not a deny-list, is the safer default: see
#     task instructions on getting this distinction wrong), it only warns
#     loudly so this exact log line is easy to find and investigate.

declare -A seen=()       # ldd'd files, keyed by absolute path
declare -A to_bundle=()  # basename -> source path, MSYS2-provided only
queue=("$EXE_SRC")

# gdk-pixbuf-query-loaders.exe (see section 2 below — the NSIS installer
# re-runs it post-install to fix a relocatable-path problem) gets shipped
# alongside metanoia.exe, so it needs to be walked through the SAME
# closure computation as metanoia.exe itself — otherwise any DLL it needs
# that metanoia.exe doesn't (unlikely, since both ultimately link
# glib/gobject/gdk-pixbuf, but not verified) would silently be missing.
GDK_PIXBUF_QUERY_TOOL="$MSYS_PREFIX/bin/gdk-pixbuf-query-loaders.exe"
[ -x "$GDK_PIXBUF_QUERY_TOOL" ] && queue+=("$GDK_PIXBUF_QUERY_TOOL")

is_apiset_stub() {
  case "$1" in
    api-ms-win-*|api-ms-win-*.dll|api-ms-win-*.DLL|ext-ms-*|ext-ms-*.dll|ext-ms-*.DLL) return 0 ;;
    *) return 1 ;;
  esac
}

is_windows_system_path() {
  local lower="${1,,}"
  [[ "$lower" =~ ^/[a-z]/windows/ ]]
}

process_one() {
  local f="$1"
  [ -n "${seen[$f]:-}" ] && return
  seen[$f]=1
  local line name path
  # UNVERIFIED: exact ldd output formatting (column spacing, whether the
  # "(0xADDR)" suffix is always present) — parsed defensively with awk
  # field indices ($1 = dep name, $3 = resolved path when "=>" is present)
  # rather than assuming fixed column widths.
  while IFS= read -r line; do
    line="$(echo "$line" | sed 's/^[[:space:]]*//')"
    [ -z "$line" ] && continue
    name="$(echo "$line" | awk '{print $1}')"
    is_apiset_stub "$name" && continue
    if [[ "$line" == *"=> not found"* ]]; then
      warn "  missing dependency of $(basename "$f"): $name (ldd: not found)"
      continue
    fi
    if [[ "$line" != *"=>"* ]]; then
      # A bare "name (0xaddr)" line with no "=>" — observed for a small
      # handful of core DLLs on real Linux/Cygwin ldd output when the
      # loader resolves a name to itself with no further path info. Not
      # expected to be an MSYS2-provided DLL in practice; skip rather than
      # guess at a path.
      continue
    fi
    path="$(echo "$line" | awk '{print $3}')"
    [ -z "$path" ] && continue
    if is_windows_system_path "$path"; then
      continue
    fi
    case "$path" in
      "$MSYS_PREFIX"/bin/*)
        local base; base="$(basename "$path")"
        if [ -z "${to_bundle[$base]:-}" ]; then
          to_bundle[$base]="$path"
          queue+=("$path")
        fi
        ;;
      *)
        warn "  unrecognized dependency path for $(basename "$f"): $name => $path (neither /c/Windows nor $MSYS_PREFIX/bin — NOT bundled, please check manually)"
        ;;
    esac
  done < <(ldd "$f" 2>/dev/null || true)
}

info "Walking DLL dependency closure from ${EXE_NAME}..."
i=0
while [ "$i" -lt "${#queue[@]}" ]; do
  process_one "${queue[$i]}"
  i=$((i + 1))
done

info "Bundling ${#to_bundle[@]} MSYS2-provided DLL(s)."
for base in "${!to_bundle[@]}"; do
  cp "${to_bundle[$base]}" "$DIST_ROOT/$base"
done
if [ "${#to_bundle[@]}" -eq 0 ]; then
  warn "zero DLLs were selected for bundling — that's almost certainly wrong for a GTK4 app; ldd likely didn't behave as expected (see UNVERIFIED notes above)"
fi

# ─────────────────────────────────────────────────────────────────────────
# 2. GDK-Pixbuf loaders (PNG/JPEG/etc. — needed for icon rendering)
# ─────────────────────────────────────────────────────────────────────────
# grep -rn "gtk_image_new_from_icon_name\|icon_name" src/ confirms this app
# DOES ask GTK for named theme icons (src/kit/components/status_bar.zig:
# "emblem-system-symbolic", "audio-input-microphone-symbolic",
# "dialog-error-symbolic") rather than only ever drawing its own bundled
# assets — so both this section and the icon-theme section below genuinely
# apply; this was verified, not assumed.
GDK_PIXBUF_VER_DIR="$(ls -d "$MSYS_PREFIX"/lib/gdk-pixbuf-2.0/*/ 2>/dev/null | head -1 || true)"
if [ -n "$GDK_PIXBUF_VER_DIR" ]; then
  GDK_PIXBUF_VER="$(basename "$GDK_PIXBUF_VER_DIR")"
  DEST_PIXBUF_DIR="$DIST_ROOT/lib/gdk-pixbuf-2.0/$GDK_PIXBUF_VER"
  mkdir -p "$DEST_PIXBUF_DIR/loaders"
  if ls "$GDK_PIXBUF_VER_DIR"/loaders/*.dll >/dev/null 2>&1; then
    cp "$GDK_PIXBUF_VER_DIR"/loaders/*.dll "$DEST_PIXBUF_DIR/loaders/"
  else
    warn "no gdk-pixbuf loader DLLs found under $GDK_PIXBUF_VER_DIR/loaders"
  fi

  # loaders.cache bakes in the ABSOLUTE path of each loader .dll at the
  # moment gdk-pixbuf-query-loaders runs. Regenerating it here bakes in
  # THIS CI RUN's absolute path ($DIST_ROOT, e.g.
  # D:\a\metanoia\metanoia\dist\Metanoia\lib\...) — correct only if the end
  # user happens to unzip to that exact path, which is not realistic. This
  # is a KNOWN, UNRESOLVED LIMITATION of the portable ZIP specifically
  # (flagged prominently in the report for this task) — the NSIS installer
  # (packaging/windows-installer.nsi) fixes this properly by re-running
  # gdk-pixbuf-query-loaders.exe --update-cache as a POST-INSTALL step
  # against the user's REAL chosen install directory, which is the one
  # place this is guaranteed correct. Still generated here so the portable
  # zip at least works when extracted to a stable, predictable path (e.g.
  # if a user always unzips to the same folder) and so local/manual testing
  # of this script has something to inspect.
  if [ -x "$GDK_PIXBUF_QUERY_TOOL" ]; then
    if GDK_PIXBUF_MODULEDIR="$DEST_PIXBUF_DIR/loaders" "$GDK_PIXBUF_QUERY_TOOL" > "$DEST_PIXBUF_DIR/loaders.cache" 2>/dev/null; then
      info "generated loaders.cache (gdk-pixbuf $GDK_PIXBUF_VER)"
    else
      warn "gdk-pixbuf-query-loaders failed — loaders.cache not generated; PNG/icon loading may not work"
      rm -f "$DEST_PIXBUF_DIR/loaders.cache"
    fi
    # Also ship the query tool itself, flat next to metanoia.exe: the NSIS
    # installer (packaging/windows-installer.nsi) re-runs it as a
    # post-install step against the user's REAL chosen install directory,
    # to fix the CI-baked-absolute-path problem described above — it can
    # only do that if the tool is actually present in the installed tree.
    # (Its own DLL dependencies were already walked into $to_bundle by the
    # closure loop in section 1, since it was seeded into the initial
    # queue above.)
    cp "$GDK_PIXBUF_QUERY_TOOL" "$DIST_ROOT/gdk-pixbuf-query-loaders.exe"
  else
    warn "gdk-pixbuf-query-loaders.exe not found at $GDK_PIXBUF_QUERY_TOOL — skipping loaders.cache generation and post-install cache regeneration"
  fi
else
  warn "no gdk-pixbuf-2.0 versioned lib dir found under $MSYS_PREFIX/lib — skipping gdk-pixbuf bundling entirely"
fi

# ─────────────────────────────────────────────────────────────────────────
# 3. Icon theme fallback (Adwaita, with hicolor as its usual base theme)
# ─────────────────────────────────────────────────────────────────────────
# CI must actually install an icon theme package for this to find anything
# — see the "adwaita-icon-theme" addition to release-latest.yml's MSYS2
# package list alongside this script.
mkdir -p "$DIST_ROOT/share/icons"
found_theme=0
for theme in Adwaita hicolor; do
  if [ -d "$MSYS_PREFIX/share/icons/$theme" ]; then
    cp -r "$MSYS_PREFIX/share/icons/$theme" "$DIST_ROOT/share/icons/"
    info "bundled icon theme: $theme"
    found_theme=1
  fi
done
if [ "$found_theme" -eq 0 ]; then
  warn "no Adwaita/hicolor icon theme found under $MSYS_PREFIX/share/icons — the status bar's named icons (emblem-system-symbolic etc.) will likely render blank/broken"
fi

SIZE="$(du -sh "$DIST_ROOT" | cut -f1)"
info "Done: $DIST_ROOT ($SIZE)"
