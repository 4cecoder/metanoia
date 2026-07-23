# Packaging & Release (macOS / Linux / Android)

This covers the packaging added in `packaging/*.sh` and
`.github/workflows/release-unix.yml`. Windows has its own separate, working
pipeline at `.github/workflows/release.yml` — not covered here, not touched
by any of this.

## Cutting a release

Push a tag matching `20*.*.*` (the existing convention, e.g.
`2026.07.19-abc1234`):

```bash
git tag 2026.07.19-$(git rev-parse --short HEAD)
git push origin 2026.07.19-$(git rev-parse --short HEAD)
```

That single tag push fires **both** `release.yml` (Windows) and
`release-unix.yml` (macOS, Linux, Android) as separate workflows. Each job
uploads its own artifact to the same GitHub Release via
`softprops/action-gh-release@v2` — safe, this is how the existing Windows
job already behaves and multiple jobs/workflows can append files to one
release without conflict.

## Continuous "latest" releases (no tag needed)

Separately, `.github/workflows/release-latest.yml` runs on **every push to
master** — no tag required. It builds all four platforms (Windows, macOS,
Linux, Android) and republishes them under a single rolling GitHub Release
tagged `latest` (https://github.com/4cecoder/metanoia/releases/tag/latest),
overwriting each platform's asset every push. This is for quick
distribution/testing off the tip of master, not a substitute for the
versioned tag releases above.

Each platform's build job (`build-windows`/`build-macos`/`build-linux`/
`build-android`) is gated on its own test job (`test-zig` for the three
native ones, `test-kotlin` for Android) so a broken build never overwrites
a working `latest` asset. A dedicated `move-tag` job force-moves the `latest`
git tag to the new commit before any build job publishes against it —
`softprops/action-gh-release` does not move an already-existing tag on its
own, so skipping this step would leave the release's tag pointing at a
stale commit even though the uploaded files are fresh.

The Android job is debug-signed only (same caveat as below); Windows/macOS/
Linux builds use the same `packaging/*.sh` scripts as the tag-triggered
flow, which already produce stable, non-versioned filenames (arch-based, no
git tag baked in) — so no script changes were needed to make them safe for
a rolling release with a fixed asset name.

## Data distribution — resolved

`data/` was originally entirely gitignored (110MB, including a lot of unused
dev scratch recordings). As of 2026-07-19 the two files the shipped app
actually needs are tracked directly in git as explicit exceptions to the
`data/*.db` / `*.wav` rules in `.gitignore`:

- `data/bible.db` (31MB) — well under GitHub's 100MB hard limit, no git-lfs
  needed.
- The **7 wav clips actually referenced by `data/voices.json`**: `tommy.wav`,
  `lennox_ref.wav`, `mari_ref.wav`, `jordan_ref.wav`, `shamoun_ref.wav`,
  `roumie_perfect_15s.wav`, `shapiro.wav` (~7MB total).

Everything else under `data/` (`reference.wav` alone was 55MB and referenced
by nothing; `roumie.wav`/`roumie2.wav`/`roumie_15s.wav`/`roumie_combined.wav`
were earlier iterations superseded by `roumie_perfect_15s.wav`; `me.wav`,
scraped `.html`/`.txt` fixtures) stays gitignored — it was never shipped to
users and doesn't need to be.

A plain `actions/checkout@v4` is now sufficient — `packaging/build-macos.sh`
and `packaging/build-linux.sh` still fail fast with a clear error if
`data/bible.db` is somehow missing (e.g. a shallow/sparse checkout
misconfiguration), as a defensive check, not because it's expected to
happen in normal CI.

The existing Windows `release.yml` pipeline still never copies `data/` into
`dist/` — that's pre-existing and out of scope here (constraint: don't touch
`release.yml`), but now that the data is a normal tracked file, fixing that
is a small, low-risk follow-up whenever someone picks Windows back up.

**Update:** Windows *was* picked back up — `release-latest.yml`'s
`build-windows` job now runs `packaging/build-windows.sh` (real recursive
DLL-dependency bundling via `ldd`, plus GDK-Pixbuf loaders and an
Adwaita/hicolor icon theme for GTK4's runtime resource discovery) and
`packaging/windows-installer.nsi` (an NSIS installer, built with
`makensis`, producing `Metanoia-Setup.exe` alongside the existing portable
zip). `release.yml` (the tag-triggered versioned release) deliberately was
**not** touched yet — same "don't touch it in this pass" reasoning as
above, now doubled: it's the real user-facing release channel, and this
approach is unproven on real Windows CI. Once a real `release-latest.yml`
run confirms metanoia.exe actually launches on a clean Windows box, port
the same two steps into `release.yml` — it has the identical bare
`Copy-Item` gap today. See `packaging/build-windows.sh`'s header comment
for exactly what could and couldn't be verified without a Windows/MSYS2
environment (there was none available), and its inline comments for the
system-vs-MSYS2-DLL distinction and the GDK-Pixbuf `loaders.cache`
relocatable-path limitation that's still open for the portable zip
specifically (the NSIS installer fixes it properly via a post-install
`gdk-pixbuf-query-loaders --update-cache` step; the zip does not, since
there's no "install step" to hook).

Android is unaffected either way — the mobile client doesn't bundle
`data/bible.db` the same way (it's Gradle/Kotlin, separate assets pipeline).

## The macOS vs. Linux asymmetry (read this before changing packaging)

`src/main.zig` opens the database with a bare relative path:
`sqlite3_open("data/bible.db", ...)`. Where that resolves depends entirely
on the process's current working directory at the time — and the two
platforms get there very differently:

- **macOS**: `resolveBundleRoot()` (main.zig, called first thing in `main()`)
  inspects the running binary's own path via `_NSGetExecutablePath`. If it
  contains `.app/Contents/MacOS/`, it `chdir`s to the sibling
  `Contents/Resources` directory *before* the database is opened. This is
  why `packaging/build-macos.sh` packages a real `.app` bundle (binary at
  `Metanoia.app/Contents/MacOS/metanoia`, with `data/` and `assets/` copied
  into `Metanoia.app/Contents/Resources/` — this bundle assembly is done by
  the pre-existing `scripts/create_app_bundle.sh`, invoked via `zig build
  app`). As long as the `.app` structure is preserved, it works no matter
  where the `.app` is moved to (verified — see "What was verified" below).

- **Linux**: there is **no equivalent logic at all**. The relative-path
  `sqlite3_open` call resolves against whatever the OS happened to set as
  cwd when the process was launched — which, for a binary invoked from a
  `.desktop` file or `$PATH`, could be anything (often the user's home
  directory or wherever their file manager/launcher was invoked from). We
  deliberately did **not** patch `src/main.zig` to add proper XDG data-dir
  resolution (`$XDG_DATA_HOME`/`/usr/share/metanoia` etc.) — that's a real
  fix but bigger than today's scope. Instead, `packaging/build-linux.sh`
  works around it at the packaging layer: everything installs under one
  prefix, `/opt/metanoia/{bin,data,assets}`, and the thing actually on
  `$PATH` (`/usr/bin/metanoia`, and the `.desktop` file's `Exec=`) is a thin
  wrapper script:
  ```sh
  cd /opt/metanoia && exec /opt/metanoia/bin/metanoia "$@"
  ```
  **Follow-up worth doing properly later**: add real XDG-dir resolution to
  `src/main.zig` (check `$XDG_DATA_HOME`, fall back to
  `/usr/share/metanoia` or similar, same idea as `resolveBundleRoot` but for
  Linux) so the binary doesn't depend on a launcher wrapper at all.

`data/` is bundled in full (~110MB) on both platforms for now — no attempt
was made to slim it down (e.g. dropping redundant reference `.wav` files);
that's a separate optimization for another day.

## What each script does

- **`packaging/build-macos.sh`** — `zig build app -Doptimize=ReleaseFast`
  (which shells out to `scripts/create_app_bundle.sh`), ad-hoc codesigns the
  bundle (`codesign --force --deep --sign -`, no paid cert needed/used), tars
  it to `dist/Metanoia-macos-<arch>.tar.gz`.

- **`packaging/build-macos-dmg.sh`** — takes the already-built, already-signed
  `zig-out/Metanoia.app` (delegating to `build-macos.sh` first if it isn't
  present yet — not a duplicate build pipeline, just a call to the one that
  already owns the build/vtool/codesign ordering) and assembles a polished,
  standard drag-to-Applications installer at `dist/Metanoia-<arch>.dmg` via
  [`create-dmg`](https://github.com/create-dmg/create-dmg) (`brew install
  create-dmg`). Produces a 660×400 Finder window with `Metanoia.app` and an
  `Applications` symlink side by side (128px icons, positioned at (180,170)
  and (480,170)), a custom Tokyo-Night-themed background
  (`assets/dmg-background.png` — dark navy `#1a1b26`→`#20222f` gradient, the
  "METANOIA" wordmark and a small arrow in the brand accent blue `#7aa2f7`,
  generated with ImageMagick; the exact recipe is in the script's header
  comment for easy regeneration/tweaking), and a custom volume icon (reusing
  `assets/Metanoia.icns`). This does **not** re-run or duplicate
  `build-macos.sh`'s vtool-minos-patch/codesign steps, and does not
  re-codesign anything itself — it only copies the already-signed `.app`
  into a disk image, so the embedded signature is untouched (verified:
  `codesign -dv` on the `.app` as mounted from a real built DMG shows the
  identical `CodeDirectory`/`Signature=adhoc` as the source bundle). Verified
  end-to-end on a real macOS machine: the DMG was actually built, mounted
  read-only, and inspected — Finder window bounds queried via AppleScript
  came back exactly `660x400` at the position the script requested, per-icon
  positions queried the same way matched `(180,170)`/`(480,170)` exactly,
  the `Applications` item resolved to a real symlink to `/Applications`,
  `GetFileInfo` on the mounted volume showed the custom-icon flag set, and
  the background PNG was present at `.background/dmg-background.png` inside
  the volume. The one thing *not* independently confirmed is the pixel-exact
  rendered appearance of the background image at every possible Retina/non-
  Retina display scaling — Finder's folder-background mechanism doesn't
  reliably honor an `@2x` HiDPI pair the way app icons do, so the background
  is shipped at exactly the window's 1x pixel size (660×400, the same
  convention virtually all `create-dmg`-based tutorials use) rather than a
  higher-resolution asset that could render at the wrong scale; expect it to
  look slightly softer than a native asset on a Retina display, not blurry
  or broken.

- **`packaging/build-linux.sh`** — `zig build -Doptimize=ReleaseFast`,
  assembles the `/opt/metanoia` prefix layout + `/usr/bin` wrapper +
  `.desktop` file described above, and produces two artifacts:
  `dist/Metanoia-linux-<arch>.tar.gz` (universal — untar anywhere, run the
  bundled `install.sh` with sudo) and `dist/metanoia_<version>_<arch>.deb`
  (via `dpkg-deb --build`, for Debian/Ubuntu). No `.rpm`/AUR/Snap —
  diminishing returns for a same-day ship, noted as future follow-up.

- **`packaging/build-appimage.sh`** — builds (or reuses) the same
  `zig build -Doptimize=ReleaseFast` binary as `build-linux.sh`, assembles a
  standard `AppDir`, and runs `linuxdeploy` + `linuxdeploy-plugin-gtk` (both
  pinned by URL+sha256, matching this repo's Zig-nightly-fetch house style —
  see the script's own header comment for exactly why each is pinned the
  way it is; `linuxdeploy-plugin-gtk` has no versioned releases at all, so
  it's pinned to a specific commit instead) to produce a single portable
  `dist/Metanoia-x86_64.AppImage` — no installation, `chmod +x` and run on
  virtually any x86_64 Linux distro. Same cwd/relative-data-path problem as
  `build-linux.sh` (see "macOS vs. Linux asymmetry" above); solved via a
  `apprun-hooks/*.sh` hook (the same mechanism `linuxdeploy-plugin-gtk`
  itself uses to inject GTK env vars) instead of a custom `AppRun`, so it
  composes with the plugin rather than fighting it. GTK4/SQLite3's `.so`
  dependency closure is bundled automatically by linuxdeploy's own default
  behavior (it `ldd`-traces the given executable) — no extra flags needed
  beyond the gtk plugin, which additionally handles GLib schemas/GDK-Pixbuf
  loaders/theme bits that raw `.so`-copying wouldn't catch. Not run
  end-to-end anywhere yet except in CI (this repo's dev machine for this
  work was macOS, which cannot run ELF AppImage tooling at all).

- **`packaging/com.bytecats.metanoia.yml`** (a Flatpak manifest, not a
  shell script) — builds a single-file `.flatpak` bundle via
  `flatpak-builder`/`flatpak build-bundle` (CI job `build-flatpak` in
  `release-latest.yml`, using the `flatpak/flatpak-github-actions` action).
  Targets `org.gnome.Platform`//`org.gnome.Sdk` version 50 (verified as the
  current stable GNOME runtime via Flathub's own API, not guessed), which
  already includes GTK4. Since Flatpak's sandboxed build step has no
  network access by default, sqlite3, curl, and a specific pinned Zig
  nightly are all built/installed as manifest **modules** with hash-verified
  sources fetched by `flatpak-builder` itself *before* the sandbox closes —
  sqlite3 and curl because it could not be confirmed whether
  `org.gnome.Sdk`//50 ships their dev files/CLI at all (this codebase shells
  out to a real `curl` binary — see `src/tts_client.zig`/
  `src/ollama_client.zig`/`src/services/network_discovery.zig` — it does not
  link `libcurl`), Zig because no released Zig version satisfies
  `build.zig.zon`'s nightly-only `minimum_zig_version` and this repo's other
  CI jobs acquire it via a live network `curl` unavailable inside a Flatpak
  build sandbox. `packaging/flatpak-metanoia-wrapper.sh` (installed as
  `/app/bin/metanoia`, the actual compiled binary lives at
  `/app/lib/metanoia/metanoia-bin`) solves the same relative-data-path
  problem as `build-linux.sh`/`build-appimage.sh`, but with one Flatpak-
  specific wrinkle: `/app` is *always* read-only at runtime (not just
  root-owned like `/opt/metanoia`), so config persistence needs a genuinely
  writable location — it symlinks the read-only bundled `data`/`assets`
  into each Flatpak app's automatic, no-extra-permission-needed
  `$XDG_DATA_HOME/metanoia`, where `config.json` can then be created for
  real. `finish-args` are `--share=network` (loopback TTS/Ollama servers,
  LAN auto-discovery, and `src/native_scraper.zig`'s biblehub.com fetches —
  all grepped from actual runtime code, not assumed), `--share=ipc`,
  `--socket=wayland`/`--socket=fallback-x11`, and `--device=dri`; no
  `--filesystem=*` entries were needed. Not run end-to-end anywhere yet
  except in CI — `flatpak`/`flatpak-builder` are not installed on this
  repo's macOS dev machine either, so only YAML-schema-level and manual
  reasoning-based checks were possible locally.

- **`packaging/build-android.sh`** — thin wrapper around
  `cd mobile && ./gradlew assembleDebug`, copies the resulting APK to
  `dist/metanoia-android-debug.apk`.

## Android signing caveat

`mobile/app/build.gradle.kts` has **no `signingConfigs` block**, so
`assembleRelease` cannot produce an installable APK (Android refuses to
install an unsigned release build). Rather than either (a) provisioning a
throwaway keystore and wiring `signingConfigs.release` into
`build.gradle.kts`, or (b) generating/storing a real release keystore as a
CI secret, today's build uses **`assembleDebug`** — Gradle's own default
debug keystore auto-signs it, it's installable via sideload/`adb install`,
but it is explicitly **not** a Play Store-eligible artifact. The GitHub
Release notes for the Android asset say this plainly.

**What a real signed release needs later**:
1. Generate a release keystore (`keytool -genkeypair ...`).
2. Add a `signingConfigs { release { ... } }` block to
   `mobile/app/build.gradle.kts` referencing it via Gradle properties.
3. Store the keystore + passwords as GitHub Actions secrets, decode them to
   a file in the `build-android` job before `assembleRelease`.
4. Switch `packaging/build-android.sh` (or the workflow step) to
   `assembleRelease` and rename the output away from `-debug`.

## Homebrew formula

`Formula/metanoia.rb` uses the binary-download pattern: it fetches
`Metanoia-macos-arm64.tar.gz` from a GitHub Release (does not build from
source), depends on `gtk4`/`sqlite3` at runtime only, and installs the
`.app` bundle into `libexec` with a `bin/metanoia` wrapper.

Two things are **not done yet** and need a human:

1. **No tap repo exists.** Homebrew formulae are installed from a separate
   `homebrew-<name>` repo. This repo is not one. You need to create
   `github.com/4cecoder/homebrew-metanoia` and copy `Formula/metanoia.rb`
   into it. Users then run `brew tap 4cecoder/metanoia && brew install
   metanoia`.
2. **No real sha256 yet** — there's no release artifact to hash. Once you've
   cut a real tag and `release-unix.yml` has uploaded
   `Metanoia-macos-arm64.tar.gz`:
   ```bash
   curl -fsSL -o /tmp/m.tar.gz \
     https://github.com/4cecoder/metanoia/releases/download/<TAG>/Metanoia-macos-arm64.tar.gz
   shasum -a 256 /tmp/m.tar.gz
   ```
   Paste that hash into `Formula/metanoia.rb`'s `sha256` line, and set
   `url`/`version` to the real tag.

Only an arm64 (Apple Silicon) tarball is produced today, since
`release-unix.yml`'s `build-macos` job runs on `macos-latest` (an
Apple-Silicon GitHub-hosted runner). Intel Mac support would need an
additional Intel runner (e.g. `macos-13`) added to the job matrix — not
done today.

## What was actually verified locally (today, on this machine)

- `zig build app -Doptimize=ReleaseFast` → produces a working
  `zig-out/Metanoia.app`.
- `packaging/build-macos.sh` ran end-to-end: built, ad-hoc signed, tarred.
- The resulting tarball was extracted to an **unrelated temp directory**
  (simulating a real user's download-and-unzip), launched with `open`, and
  confirmed via `lsof` to have `cwd` = `.../Metanoia.app/Contents/Resources`
  and an open file handle on `.../Contents/Resources/data/bible.db` — i.e.
  `resolveBundleRoot()` and the DB open both work correctly from a
  freshly-extracted, relocated bundle, not just an in-place build.
- `packaging/build-android.sh` ran end-to-end: `cd mobile && ./gradlew
  assembleDebug` really did produce
  `mobile/app/build/outputs/apk/debug/app-debug.apk` (~100MB), copied to
  `dist/metanoia-android-debug.apk`.

## What was only reasoned about, not run

- `packaging/build-linux.sh` — this machine is macOS, so there's no way to
  actually link a GTK4 Linux binary here. The script was checked with
  `bash -n` (syntax) and reviewed carefully, but its first real end-to-end
  run will be the `build-linux` job in `release-unix.yml` on
  `ubuntu-latest`. Treat the first CI run on this as a real test, not a
  formality.
- The `release-unix.yml` workflow itself (Zig-nightly-fetch logic, Android
  SDK setup action, etc.) — reasoned through by mirroring the existing
  Windows job's PowerShell Zig-fetch logic in bash, but never actually run
  by GitHub Actions yet.
