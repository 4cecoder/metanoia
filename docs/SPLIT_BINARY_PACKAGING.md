# Split macOS Bundle: Stable Reader + Volatile TTS Engine

**Status:** phase 1 packaging wiring landed; native TTS engine packaging is
still design work.

## Goal

Ship a small, durable `Metanoia.app` whose reader/data release can be updated
independently from the fast-moving native TTS implementation and its large
model files. The reader must still work when the native engine is absent:
`tts_backend: "remote"` remains the default and the existing Python server is
the fallback.

The split is by volatility and ownership:

1. **Reader layer (stable):** GTK app, Bible data, UI assets, canonical voice
   references, and the stable TTS client/IPC contract.
2. **Engine layer (volatile):** a separate `metanoia-tts` process, qwentts and
   GGML/Metal dynamic libraries, and engine metadata. It is not linked into
   the reader executable.
3. **Model layer (large, independently versioned):** Qwen GGUF files. A model
   refresh must not require replacing either the reader app or the engine
   executable.

This is the packaging counterpart to `docs/VOLATILITY_REFACTOR.md`: the
reader is the user-facing application binary; native TTS is a separately
versioned binary root rather than another dependency of that root.

## Current artifact inventory and gaps

| Current source/artifact | Role | Current state | Next-bundle disposition |
|---|---|---|---|
| `zig-out/Metanoia.app/Contents/MacOS/metanoia` | Reader executable | Built by `zig build app`; the checked-in release script uses `-Dnative-ai=false` implicitly | Keep in the reader app; build explicitly without native AI |
| `data/bible.db` | Reader content | Tracked and copied to `Contents/Resources/data/` | Keep in reader layer |
| `data/voices.json` and the referenced `data/*.wav` clips | Canonical voice references | Copied with reader data; native TTS currently resolves these using a relative path | Keep as reader-owned content; pass an absolute voice-root/manifest path to the engine |
| `assets/`, `static/`, `assets/Info.plist` | Reader UI/runtime resources | Copied by `scripts/create_app_bundle.sh` | Keep in reader layer |
| `vendor/qwentts.cpp/build/libqwen.dylib` | Native TTS code | Local, ignored, arm64 dylib; linked through `@rpath` | Move to the engine layer's private `lib/` directory |
| `vendor/qwentts.cpp/build/libggml*.dylib` | Qwen GGML/Metal dependencies | Local, ignored, versioned dylibs plus symlinks | Move the required TTS-only libraries to engine `lib/`; do not ship unused MLX/Whisper dependencies |
| `vendor/qwentts.cpp/models/qwen-talker-0.6b-base-Q8_0.gguf` | TTS model | Local, ignored, roughly 947 MiB in this checkout | Model layer, addressed by manifest/hash |
| `vendor/qwentts.cpp/models/qwen-tokenizer-12hz-Q8_0.gguf` | Speech tokenizer | Local, ignored, roughly 278 MiB in this checkout | Model layer, addressed by manifest/hash |
| `/opt/homebrew/opt/{gtk4,mlx-c,ggml,whisper-cpp}/...` | Build/host libraries | Current native executable records Homebrew paths; not portable | Reader release must not depend on native-AI Homebrew paths; package or declare only the reader's supported GTK runtime policy |

The current `scripts/create_app_bundle.sh` copies the reader and the
`metanoia-scraper` companion, plus `data/`, `assets/`, `static/`, and
`tools/bible_books.json`. It still does not copy qwentts dylibs or GGUFs.
That is correct for the stable reader but means a native-enabled executable
cannot be treated as a self-contained release bundle today. The current native
link also contains a relative `vendor/qwentts.cpp/build` rpath and Homebrew
rpaths; neither is a valid release lookup strategy after the app is moved to
`/Applications`.

## Next release artifacts

Publish these as separate, architecture-specific release assets. The reader
asset stays compatible with machines that never install native TTS.

```text
Metanoia-macos-arm64.tar.gz             # stable reader app
Metanoia-arm64.dmg                      # stable reader installer
Metanoia-tts-engine-macos-arm64.tar.gz  # volatile engine code + dylibs
Metanoia-tts-models-qwen3-base-arm64.tar.zst
                                        # large, content-addressed model pack
```

The DMG should contain the reader app and an `Applications` link only. It
must not grow by roughly 1.2 GiB merely because native TTS exists. The engine
and model archives may be downloaded by the app's optional native-TTS setup,
or installed manually for offline use.

The engine archive has a self-contained, versioned root:

```text
Metanoia-TTS-Engine/
  manifest.json
  bin/
    metanoia-tts
  lib/
    libqwen.dylib
    libggml.0.dylib
    libggml-base.0.dylib
    libggml-cpu.0.dylib
    libggml-metal.0.dylib
    libggml-blas.0.dylib       # only if the built engine needs it
  models/                      # optional when models are in a separate pack
    README
```

The model archive installs separately:

```text
Metanoia-TTS-Models/
  manifest.json
  qwen-talker-0.6b-base-Q8_0.gguf
  qwen-tokenizer-12hz-Q8_0.gguf
```

No engine archive may contain a nested git checkout, a build directory, Mach-O
symlink chains that point outside its root, or a `/Users/...`/`/opt/homebrew`
absolute dependency.

## Installed paths

The stable app remains conventional:

```text
/Applications/Metanoia.app/
  Contents/
    Info.plist
    MacOS/metanoia
    Resources/
      data/bible.db
      data/voices.json
      data/<canonical voice clips>.wav
      assets/
      static/
```

Volatile files live outside the signed app bundle so replacing them does not
invalidate the reader's code signature or require reinstalling the reader:

```text
~/Library/Application Support/Metanoia/
  engines/
    tts/
      2026.09.16-<engine-sha>/
        manifest.json
        bin/metanoia-tts
        lib/*.dylib
      active -> 2026.09.16-<engine-sha>
  models/
    qwen3-tts-base-<model-sha>/
      manifest.json
      qwen-talker-0.6b-base-Q8_0.gguf
      qwen-tokenizer-12hz-Q8_0.gguf
    active -> qwen3-tts-base-<model-sha>
  voices/                         # future user-created voices
  run/                            # transient socket/lock/handshake files
```

The `active` links are changed atomically. Version directories are immutable
after installation; this makes rollback and crash recovery straightforward.
The app bundle itself is never used as the mutable engine install location.

## Mach-O linking and runtime lookup

The TTS binary must be a TTS-only build target. It should link qwentts/GGML and
system frameworks required by that target, but not pull the reader's GTK UI or
unrelated MLX/Whisper capability into the engine. The build should establish
these release-safe load paths:

```text
metanoia-tts -> @rpath/libqwen.dylib
metanoia-tts LC_RPATH -> @executable_path/../lib
libqwen.dylib -> @rpath/libggml*.dylib
each shipped dylib ID -> @rpath/<its filename>
```

Before archiving, the packaging check must reject an engine if `otool -L` or
`otool -l` finds a repository path, a user-home path, `/opt/homebrew`, or a
relative `vendor/...` rpath. The engine's loader must resolve only within its
own `bin/../lib` root plus Apple system frameworks.

The reader and engine must use explicit paths rather than relying on the
reader's current working directory. The existing `resolveBundleRoot()` may
continue to chdir the reader to `Contents/Resources` for its current database
behavior, but the engine launch contract is:

```text
engine root = METANOIA_TTS_ENGINE_ROOT, when set (developer/recovery override)
           = ~/Library/Application Support/Metanoia/engines/tts/active
             otherwise
model root  = METANOIA_TTS_MODEL_ROOT, when set
           = ~/Library/Application Support/Metanoia/models/active otherwise
voice root  = explicit path passed by the reader
           = <Metanoia.app>/Contents/Resources/data for shipped voices
```

The checkout path `vendor/qwentts.cpp/{build,models}` is a development-only
fallback, selected explicitly by a dev flag or environment variable. A
release build must never silently fall back to it.

## Process and compatibility contract

`metanoia-tts` is launched as a child process by the reader only when
`tts_backend` is `native`. It must expose the same generation semantics as the
existing local TTS server (health, generation request, voice name/reference
text, and WAV result). The transport should be a per-user local endpoint
(Unix-domain socket preferred; loopback HTTP is an acceptable transitional
adapter), never a public listening address.

The launch handshake must include:

```text
engine protocol/API major
engine version and commit
model id and model hash
endpoint and process id
voice-root and model-root actually selected
```

`manifest.json` should contain at least:

```json
{
  "component": "tts-engine",
  "version": "2026.09.16-<engine-sha>",
  "api_major": 1,
  "architectures": ["arm64"],
  "min_reader_version": "0.0.1",
  "model_ids": ["qwen3-tts-base-q8_0"],
  "files": {"bin/metanoia-tts": "sha256:...", "lib/libqwen.dylib": "sha256:..."}
}
```

The reader accepts an engine only when architecture, API major, manifest
hashes, and model compatibility all match. If any check fails, it keeps the
engine disabled and uses the configured remote path. A reader update is not
required for an engine patch as long as the API major remains compatible.

## Update and rollback strategy

1. Download the engine or model archive and its signed manifest to a temporary
   directory under the same filesystem as the final Application Support root.
2. Verify the release signature, SHA-256 file hashes, architecture, Mach-O
   load paths, and engine health check before activation.
3. Rename the complete temporary directory to its immutable version/hash
   directory. Never update files in an active directory in place.
4. Atomically replace `engines/tts/active` or `models/active` with a new
   symlink. Write the previous target to a small rollback record first.
5. Start the engine, perform one short synthesis/health request, and mark the
   version good only after it responds.
6. On launch failure, protocol mismatch, crash during the health request, or
   repeated generation failure, restore the previous `active` target and fall
   back to remote TTS. Keep at least one known-good engine and model version.
7. Garbage-collect older versions only after a later version has passed health
   checks and only when they are not the rollback target.

This makes a native engine update a reversible data-plane update. Reinstalling
or replacing `Metanoia.app` cannot remove the user's engine, model cache, or
personal library data.

## Packaging acceptance checks

The next macOS packaging job should verify, before publishing:

- `zig build app -Doptimize=ReleaseFast` produces the reader without native-AI
  dependencies; `zig build` remains the normal reader build.
- The TTS target is built separately with `-Dnative-ai=true` and produces only
  the engine artifacts needed for TTS.
- The reader DMG/tarball contains no GGUF files and no `vendor/` directory.
- The engine archive contains no absolute developer/Homebrew paths and runs
  when copied to a different directory on an Apple Silicon machine.
- The model archive's manifest hashes both GGUF files and can be installed or
  rolled back without rebuilding either binary.
- A clean machine with no engine starts the reader and uses remote TTS.
- An installed engine can clone a canonical voice using the reader's explicit
  voice-root path, then survives moving the app to `/Applications`.
- Updating only the engine changes neither the reader code signature nor the
  reader archive checksum; updating only models changes neither binary.
