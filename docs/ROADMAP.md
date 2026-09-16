# Metanoia Roadmap

**Updated:** 2026-09-16
**Purpose:** one short, current plan for the desktop split and the eventual
Zig-only runtime.

This is the status document for the work described in the more detailed split
architecture and packaging contracts. Those documents remain useful design
references; this file records what is actually landed and what is next.

## Current position

| Area | Landed now | Boundary to preserve |
| --- | --- | --- |
| Stable reader | `zig build stable` builds the GTK reader with native AI disabled by default. `metanoia-scraper` is a separate executable, and the app bundle can carry it as a companion. | Reader startup and the default test path must not require Qwen, GGUF weights, MLX/Metal, or Whisper. |
| Native TTS | `zig build tts-worker -Dnative-ai=true` builds `metanoia-tts`. It loads Qwen3-TTS once and serves newline-delimited JSON requests over stdio. | The reader talks to a process, not to the forward-pass implementation. One resident worker should serve a reading session. |
| Voice cloning | The worker/client path accepts a reference recording and transcript, including the configured Jordan voice. Repeated clone requests work in one resident process. | Keep voice-reference loading and prompt state in the worker; do not reload a model for every verse. |
| Model lifecycle | `metanoia-models` resolves, inspects, hashes, verifies, and atomically stages the talker and codec GGUF files. It does not download anything implicitly. | Model files are a separately managed payload, never a build side effect or a reason to redownload an existing checkout. |
| Native client | The native client prefers the resident worker and retains an in-process native fallback while the sidecar is hardened. Remote/Python TTS remains a compatibility path. | A failed worker must not freeze the reader; remove fallbacks only after measured parity. |

The current Zig worker is an integration boundary, not yet a pure-Zig neural
implementation: Qwen3-TTS inference still reaches qwentts.cpp/GGML through the
`aikit` C ABI. Zig owns the process, protocol, model paths, voice inputs, and
WAV output. That distinction is important when reading “native” in older
documents.

## Qwen/qwentts status

The local qwentts.cpp checkout is pinned at:

```text
90efdc60d62f7d6c70113994d0be17e820fd8673
```

As of this update, the checkout is clean and `origin/master` resolves to the
same commit. This is the current local upstream baseline, not a claim that
the upstream Qwen reference implementation has stopped changing. Before an
engine release, compare the pinned qwentts.cpp code and the upstream Qwen3-TTS
behavior, then record the result in the release issue and update the pin only
with a reproducible compatibility test.

The two required model artifacts currently have stable names in the manager:

```text
qwen-talker-0.6b-base-Q8_0.gguf
qwen-tokenizer-12hz-Q8_0.gguf
```

The checkout-side files are ignored development assets. The manager’s default
macOS destination is:

```text
~/Library/Application Support/Metanoia/models/qwen3/
```

Use `METANOIA_MODEL_DIR` to select another managed directory and
`METANOIA_QWEN_SOURCE_DIR` to select an existing source directory. A normal
local development run can continue using the vendored files; installing them
again is not required merely because the manager exists.

## Milestones

### 0. Split and resident execution — landed

- Keep stable reader, scraper, and native-AI build roots independently
  selectable.
- Build `metanoia-models` without inference dependencies.
- Build `metanoia-tts` only with `-Dnative-ai=true`.
- Make the client launch one resident worker and fall back safely when it is
  unavailable.
- Cover the model-path and stdio protocol modules with fast Zig tests.
- Keep the real model-backed test explicit: `zig build test-native-tts
  -Dnative-ai=true`.

### 1. Make the sidecar contract releasable — next

- Add a small protocol version/hello handshake with worker capabilities,
  model-manifest identity, and a clear incompatibility error.
- Define a manifest containing model filenames, sizes, SHA-256 values, engine
  pin, voice-reference hashes, and supported audio formats.
- Test that worker failures, malformed responses, cancellation, and missing
  models fail loudly in native tests instead of being mistaken for successful
  synthesis.
- Make bundle and installed-engine path resolution independent of the current
  working directory. Keep checkout paths as an explicit development fallback.
- Keep one known-good qwentts pin and one known-good model manifest available
  for rollback.

### 2. Throughput for 33 verses — next performance pass

The resident process removes model startup from every request, but the current
client path is still buffered around per-segment WAV generation. The next
speed work should be measured against a fixed 33-verse fixture, not guessed
from one short sentence.

- Expose qwentts’s streaming PCM/chunk callback through the worker protocol so
  the first audio can play before the whole request is complete.
- Keep the voice prompt and codec state warm across requests; avoid repeating
  reference-audio extraction.
- Add an ordered worker queue and bounded batches (start with five verses),
  with cancellation between batches and back-pressure from the player.
- Measure cold start, prompt warmup, time to first audio, total wall time,
  real-time factor, peak RSS, and cache hits on Apple Silicon.
- Compare resident buffered, resident streaming, and the `uv run`
  compatibility server. Keep the fastest path only after audio and clone
  quality match.

The target is a reliable 33-verse reading session with prompt reuse and
streaming playback. “Faster” means both lower time-to-first-audio and lower
total wall time; optimizing one while regressing the other is not complete.

### 3. Package engine and models independently

- Ship the stable reader without GGUF files or native-AI Homebrew paths.
- Produce an engine payload containing `metanoia-tts`, only the required
  dylibs, a manifest, and release-safe `@rpath` entries.
- Let `metanoia-models` verify and install a model pack into the user cache;
  add authenticated download/update/rollback only as a deliberate manager
  feature, never as a build hook.
- Codesign nested binaries and dylibs, then smoke-test the copied `.app` from
  outside the checkout.
- Keep engine/model versions immutable and switch an `active` pointer
  atomically so a failed update can be rolled back.

### 4. Enforce TDD and native E2E in GitHub Actions

The existing fast workflow runs the default Zig tests on macOS/Linux and the
mobile unit tests. Native model-backed execution should remain out of every
ordinary PR by default because it needs large weights and a Metal host, but it
must not remain untested.

The CI follow-up is:

- required stable matrix: default `zig build test`, stable/scraper graph
  checks, and model-manager CLI tests without model downloads;
- required macOS native compile job: build qwentts at the recorded pin and
  compile the worker and native bundle without fetching weights;
- scheduled/manual macOS E2E: cache or provision the exact GGUF manifest,
  run two clone requests through one resident worker, assert two valid WAVs,
  and run `test-native-tts`;
- upload worker stderr, protocol responses, benchmark timings, and failed
  audio metadata as CI artifacts, never model weights;
- use `uv run` for any Python compatibility-server or Python fixture command.

Every new speed fix should add a small regression test or benchmark assertion
at the boundary it changes. The native E2E must prove resident reuse rather
than only proving that a fresh process can synthesize once.

### 5. Move toward a Zig-only shipping path

“Zig-only” is a sequence of removals, not a flag flip:

1. Make Zig the sole desktop application, worker, protocol, model-manager,
   packaging, and test-orchestration language. Keep qwentts.cpp temporarily
   behind one narrow, version-pinned ABI while results are compared.
2. Replace the C++ integration in layers: tokenizer/codec interfaces first,
   then prompt/reference handling, then talker forward-pass kernels. Preserve
   golden tensors and WAV fixtures for numerical/audio parity at each layer.
3. Move platform kernels to a Zig-owned backend boundary (Metal on macOS and
   the appropriate native backend elsewhere) without coupling the GTK reader
   to those kernels.
4. Retire the in-process native fallback, Python server, and other runtime
   language bridges only when the resident Zig path passes clone quality,
   reliability, startup, and 33-verse throughput gates on supported machines.

The Python server remains useful during migration and is launched with
`uv run`; it is not part of the intended final shipping path. Android/Kotlin
and other clients can migrate behind the same versioned engine contract rather
than forcing the desktop reader to keep their implementations.

## Working commands

Fast/default checks:

```sh
zig build test --summary all
zig build stable --summary all
zig build scraper --summary all
zig build models --summary all
./zig-out/bin/metanoia-models status --json
```

Native development, only on a machine with qwentts.cpp, its libraries, and
the GGUF files:

```sh
zig build tts-worker -Dnative-ai=true -Doptimize=ReleaseFast --summary all
zig build test-native-tts -Dnative-ai=true -Doptimize=ReleaseFast --summary all
zig build app -Dnative-ai=true -Doptimize=ReleaseFast --summary all
```

The compatibility server remains:

```sh
uv run tools/tts_server.py
```

## Stop conditions for the next release

Do not call the next native release complete until all of these are true:

- the stable reader builds and tests without native assets;
- one worker can serve repeated cloned requests without model or prompt
  reloads;
- the protocol has version and model identity checks;
- the model manager reports exact file hashes and never overwrites an active
  version in place;
- native CI has both a weight-free compile gate and a scheduled/manual
  resident-worker E2E gate;
- a fixed 33-verse benchmark reports cold start, time to first audio, total
  time, RTF, memory, and audio-quality observations;
- packaging works after moving the app out of the checkout; and
- any remaining C++/Python/Kotlin bridge is named, measured, and assigned a
  removal milestone rather than silently becoming permanent.
