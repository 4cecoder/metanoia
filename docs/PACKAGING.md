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

- **`packaging/build-linux.sh`** — `zig build -Doptimize=ReleaseFast`,
  assembles the `/opt/metanoia` prefix layout + `/usr/bin` wrapper +
  `.desktop` file described above, and produces two artifacts:
  `dist/Metanoia-linux-<arch>.tar.gz` (universal — untar anywhere, run the
  bundled `install.sh` with sudo) and `dist/metanoia_<version>_<arch>.deb`
  (via `dpkg-deb --build`, for Debian/Ubuntu). No `.rpm`/AUR/Flatpak/Snap —
  diminishing returns for a same-day ship, noted as future follow-up.

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
