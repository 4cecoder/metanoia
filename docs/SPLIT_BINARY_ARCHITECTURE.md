# Split-binary architecture for the next Metanoia bundle

**Status:** phase 1 landed; native TTS worker remains a follow-up
**Date:** 2026-09-16
**Scope:** macOS bundle first; the same build boundaries should remain usable on Linux and Windows.

## Decision summary

The next bundle should keep the GTK reader small and move native inference behind a long-lived TTS sidecar. The sidecar owns Qwen/qwentts, MLX/Metal, model loading, voice-reference caching, and batching. The reader owns the UI, database, and a stable transport client. A scraper is a separate maintenance binary rather than another dependency of the reader.

This gives the high-volatility native path an independent build, release, crash boundary, and model lifecycle without forcing the stable reader to link native AI libraries.

## Current state

The repository already has useful pieces, but they are still joined at the executable boundary:

| Area | Current state | Volatility consequence |
| --- | --- | --- |
| Build graph | `build.zig` now exposes `core`, `services`, `kit`, `stable`, `scraper`, and app bundle steps. | Reader and scraper have separate executable roots; native AI remains opt-in. |
| App imports | `src/main.zig` imports named `core` and `services` modules plus app wiring. | The reader no longer imports the scraper implementation. |
| Barrel module | `src/root.zig` remains a compatibility barrel but no longer re-exports the scraper. | The app executable does not inherit the broad scraper dependency. |
| Native AI | `build.zig:73-105` gates `aikit` behind `-Dnative-ai=true`; `src/tts_client.zig` conditionally imports it. | The default build is safe, but native mode still links inference into the app. |
| TTS orchestration | `src/services/tts_engine.zig` owns GTK playback callbacks and calls `src/tts_client.zig`. | UI scheduling and inference implementation cannot evolve independently. |
| Scraping | `src/native_scraper.zig` is built as `metanoia-scraper`; `src/scraper_client.zig` supervises it. | Markup drift invalidates the companion target, not the reader link graph. |
| macOS packaging | `scripts/create_app_bundle.sh` copies the reader, scraper companion, data, assets, static resources, and `tools/bible_books.json`. | The stable bundle has the volatile scraper payload but no native-AI/model payload. |
| Tests | `build.zig:346-390` has module, kit, build-config, and executable tests; native tests are opt-in at `build.zig:405-435`. | The native test gate is useful and should remain separate. |

`src/app_state.zig` is not core-stable: it imports GTK, database types, kit widgets, config, and `tts_engine`. It belongs with the application layer, not in a headless core library. This is the important refinement to the broader layering described in `docs/VOLATILITY_REFACTOR.md`.

Phase 1 implements the reader/scraper side of this boundary. Native TTS is
still the transitional in-process `-Dnative-ai=true` path; the resident TTS
worker and protocol remain the next phase so this landing does not pretend
that the engine is already independently deployable.

## Volatility boundaries

### Low volatility: reusable foundations

- `src/bible_db.zig`: database schema, queries, and canonical book metadata.
- `src/models/config.zig`: persisted configuration schema.
- `src/kit/`: GTK widget/component abstractions with no application state or service imports.
- A new `src/protocol/tts.zig`: versioned request/response types and framing rules, with only `std` dependencies.

These layers must not import `main`, `app_state`, `services`, scraper networking, model code, or `aikit`.

### Medium volatility: application adapters

- `src/main.zig` and `src/app_state.zig`.
- GTK-facing playback orchestration from `src/services/tts_engine.zig`.
- Remote TTS/LLM clients, network discovery, and update checking.
- A headless database adapter used by the scraper.

These are allowed to depend on the foundations and the protocol, but not the native worker implementation.

### High volatility: isolated executables

- Native TTS forward pass, decoder, Metal/qwentts ABI, voice cloning, prompt caching, and batching.
- Native LLM/STT implementations when they are enabled again.
- BibleHub HTTP/HTML scraping and schema import glue.
- Site content and release-specific packaging scripts.

The high-volatility code should change without changing the `metanoia` executable's link inputs.

## Target binaries and artifacts

| Artifact | Owns | Must not depend on | Bundle policy |
| --- | --- | --- | --- |
| `metanoia` | GTK reader, `AppState`, config, database access, playback UI, protocol client, remote fallback | `aikit`, qwentts, MLX/Metal, Whisper, scraper implementation | Always included. Built by the default target without native AI. |
| `metanoia-tts-worker` | Long-lived native TTS process, model loading, voice-reference/prompt cache, 5-segment batching, streaming audio, cancellation | GTK, `AppState`, database, scraper, site code | Included in the native macOS bundle or shipped as an optional native-TTS payload. |
| `metanoia-scraper` | Interlinear/lexicon HTTP fetching, HTML parsing, and database import | GTK, `kit`, TTS/LLM, application state | Separate developer/release-tool artifact; not required to read the bundled Bible. |
| `site/out` | Static web content | Zig desktop graph | Built and deployed by the existing site workflow. |
| `metanoia-llm-worker` *(later)* | Native LLM forward pass and model lifecycle | GTK and TTS worker implementation | Do not put it in the next TTS bundle; use the same protocol family when needed. |

The worker is a process boundary, not a Zig import. Both `metanoia` and the worker may import the small protocol module, but the reader never imports the worker module or `aikit`.

## Dependency direction

```text
                         high volatility
       ┌──────────────────────┐       ┌────────────────────────┐
       │ metanoia app         │       │ metanoia-tts-worker     │
       │ main + AppState      │       │ Qwen/qwentts + Metal    │
       │ GTK playback/UI      │       │ prompt cache + batches  │
       └──────────┬───────────┘       └───────────┬────────────┘
                  │                               │
                  │ imports                       │ imports
                  └──────────────┬────────────────┘
                                 ▼
                    ┌────────────────────────┐
                    │ tts-protocol           │
                    │ versioned RPC + frames │
                    └────────────┬───────────┘
                                 │
             ┌───────────────────┴───────────────────┐
             ▼                                       ▼
   ┌────────────────────┐                 ┌────────────────────┐
   │ core               │                 │ kit                │
   │ DB + config        │                 │ GTK primitives     │
   │ std + sqlite       │                 │ no app/service     │
   └────────────────────┘                 └────────────────────┘

       ┌──────────────────────┐
       │ metanoia-scraper     │ ──────imports──────▶ core
       │ HTTP/HTML + imports  │
       └──────────────────────┘
                         low volatility
```

The arrows are build/import edges. The runtime edge from `metanoia` to `metanoia-tts-worker` is a supervised child process using the protocol; it is intentionally not a compile-time dependency.

## TTS worker contract

Use one resident worker per app session. Spawning one process per verse would erase much of the speedup for a 33-verse reading.

The first transport should be length-prefixed frames over the worker's stdin/stdout. It is local, does not expose a TCP port, works inside an `.app`, and is easy to supervise. The same semantic messages can later be adapted to the existing HTTP server.

Protocol v1 should provide:

- `hello`: protocol version, worker version, model manifest hash, and capabilities.
- `warmup`: voice identifier and reference-audio/cache key; returns when the prompt is resident.
- `synthesize`: request id, ordered verse/segment ids, text, speed, emotion, mode, and stream preference.
- `audio`: ordered PCM/WAV chunks associated with a segment id.
- `done`, `error`, and `cancel`.

The default batch size should be five segments, configurable by the client. A 33-verse request is therefore seven worker requests or one stream of seven batches, while the worker keeps the model and voice prompt hot. Audio should stream as soon as the first segment is decoded so playback does not wait for all 33 verses.

The app-side `tts_engine` remains responsible for GTK playback and verse highlighting. It should only know the protocol client, not the Qwen forward-pass types. The Python server launched with `uv run` remains a compatibility/remote backend during migration.

## Build graph shape

The root `build.zig` should expose target-specific modules rather than one globally native app graph:

```text
protocol_mod  = src/protocol/root.zig       (std only)
core_mod      = src/core.zig                (DB/config/GTK foundation)
kit_mod       = src/kit/root.zig            (GTK kit)
app_mod       = src/main.zig                (core + kit + services + clients)
tts_mod       = src/tts_worker/root.zig     (protocol + aikit, native only)
scraper_mod   = src/native_scraper.zig      (headless core + sqlite)
```

The initial barrels can re-export the existing files; physical moves are optional. The critical boundary is the `std.Build.Module` import list and the executable root, not the directory name.

Recommended steps:

```text
zig build                                      # metanoia only, no aikit
zig build tts-worker -Dnative-ai=true          # native sidecar only
zig build scraper                               # maintenance binary only
zig build bundle -Dnative-tts=true             # app + worker + resources
zig build test                                  # fast/default tests
zig build test-native-tts -Dnative-ai=true     # explicit model-backed test
```

Keep `-Dnative-ai=true` backward-compatible while the extraction lands, but attach the option to `tts-worker` in the final graph. The default `metanoia` target must not instantiate `aikit` or require qwentts/MLX/Whisper libraries. Native model weights are packaging inputs, not build dependencies: the build must never download them. A model manifest containing version, SHA-256, voice-reference hashes, and relative install paths prevents unnecessary re-downloads.

## macOS bundle layout

The next native bundle should have this shape:

```text
Metanoia.app/
└── Contents/
    ├── MacOS/
    │   ├── metanoia
    │   └── metanoia-tts-worker
    ├── Resources/
    │   ├── Info.plist
    │   ├── data/
    │   ├── assets/
    │   ├── static/
    │   └── ai/
    │       ├── manifest.json
    │       ├── models/
    │       └── voices/
    └── Frameworks/
        └── native TTS dylibs, if the worker needs them
```

`create_app_bundle.sh` should receive the built worker and staged AI resource directory explicitly. It should fail with an actionable message when native packaging is requested but a model or dylib is missing. The regular app bundle can omit `ai/` and the worker when producing a small remote-only build.

Nested executables and dylibs must be signed in dependency order, then the app bundle. The release job must test the final copied bundle, not only `zig-out/bin/metanoia`; launching from a different working directory must still resolve `Resources/data` and `Resources/ai`.

## Migration sequence

1. **Freeze the boundary.** Add `protocol` request/response types and pure framing tests. Keep the current remote and in-process paths unchanged.
2. **Split low-risk modules.** Add `core` and `protocol` build modules, make `kit` explicit, and move `AppState`/GTK service glue into the app root. Retire the broad `src/root.zig` barrel incrementally.
3. **Add target roots.** Add `tts-worker` and `scraper` build steps. Keep native tests opt-in and make the default test graph independent of model files.
4. **Extract native TTS.** Move model initialization, qwentts calls, codec decode, voice-reference caching, and batching behind the worker entrypoint. Keep an in-process native mode only as a development benchmark until sidecar parity is proven.
5. **Wire runtime selection.** Add `remote`, `sidecar`, and temporary `inprocess` modes to the client. Start one sidecar, perform the handshake/warmup once per voice, send five-segment batches, and fall back to the Python/remote path if the worker is unavailable.
6. **Package the next bundle.** Update the macOS bundle script and release job to stage the worker, dylibs, model manifest, and optional weights; codesign and smoke-test the finished `.app`.
7. **Measure and remove duplication.** Compare 33-verse wall time, time-to-first-audio, real-time factor, worker startup, prompt warmup, peak RSS, and cache hits against the current in-process and Python paths. Remove the in-process release path only after sidecar results are equal or better.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| IPC adds latency | Keep the worker alive, batch five segments, stream chunks, and measure time-to-first-audio separately from total generation. |
| App and worker versions drift | Require a protocol-version and model-manifest handshake; reject incompatible workers with a visible fallback. |
| Worker crashes during playback | Parent owns the child, sends cancellation, cleans temporary audio, and falls back to remote generation without freezing GTK. |
| Native assets cause another large download | Build from staged assets, use content hashes, keep a user-cache directory, and download only a missing manifest entry. |
| macOS signing or resource-path failures | Sign nested code explicitly and run a clean-bundle smoke test from outside the repository. |
| Duplicate model memory | Keep native model code out of the app so exactly one worker owns model memory. |
| Scraper markup changes break releases | Ship the scraper separately, keep parser fixtures/unit tests, and never make reader startup depend on network access. |
| Voice/reference-audio rights | Record provenance and consent metadata in the voice manifest; do not silently redistribute a reference recording without permission. |

## Definition of done for the next bundle

- `zig build` produces a usable reader without native AI dependencies or model weights.
- `zig build tts-worker -Dnative-ai=true` builds only the native sidecar graph.
- A packaged app starts one worker, warms one cloned voice, and processes 33 verses in five-segment batches with streaming playback.
- A worker failure falls back cleanly and does not block the GTK main loop.
- The bundle contains a checked model manifest and signed nested code, with no unconditional redownload.
- Scraper changes and TTS changes do not require relinking the stable reader foundations or each other.
- The release artifact and the benchmark report identify whether native TTS is bundled or remote-only.
