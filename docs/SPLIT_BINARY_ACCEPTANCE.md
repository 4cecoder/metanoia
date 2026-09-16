# Split-binary acceptance contract

This is the acceptance contract for the volatility split described in
`docs/VOLATILITY_REFACTOR.md`. It is intentionally written before the build
graph is changed: a split is complete only when these checks are executable
and passing.

## Boundary under test

The stable reader binary owns the reusable UI and Bible-reading path (`kit`,
the database/core layer, and the app shell). Volatile work is moved behind
separate build roots:

| Artifact | Volatility | Allowed dependencies |
| --- | --- | --- |
| `metanoia` stable reader | low/semi-stable | `kit`, core/database, remote-service clients, system GTK/SQLite |
| `metanoia-scraper` | high | scraper code, core/database, libc/SQLite; no UI or AI |
| native-AI worker | high/heavy | `aikit`, qwentts.cpp, MLX/Metal, whisper.cpp, native model files |
| `Metanoia.app` stable bundle | low/semi-stable | stable reader plus ordinary app data; no native-AI payload |

The native-AI worker may depend on stable interfaces, but the stable reader
must never depend on the worker's implementation or its native libraries.
IPC/HTTP is the intended seam for native TTS/LLM/STT. An in-process native
path is a transitional opt-in build, not a stable-bundle dependency.

## Current baseline

The first phase now exposes separate `stable`, `scraper`, `app`,
`bundle-stable`, `run`, and `test` steps. The `aikit` dependency and its
imports are conditionally created by `-Dnative-ai=true` and default to false;
the native TTS/LLM tests are separately gated. `metanoia-scraper` is now a
real build target and the macOS bundle includes it. The resident native-AI
worker remains a later phase, so passing the current stable checks proves the
reader/scraper split, not the full TTS sidecar definition of done.

## Required build-target invariants

The next build graph should expose explicit stable, scraper, and native-AI
targets. The names below are the recommended contract; if names change, the
replacement must preserve the same one-to-one boundaries.

1. `zig build stable -Dnative-ai=false -Doptimize=ReleaseFast` produces the
   stable `metanoia` binary and does not create, compile, or link `aikit`.

2. `zig build scraper -Dnative-ai=false -Doptimize=ReleaseFast` produces
   `metanoia-scraper` without GTK, `services`, `app_state`, `aikit`, qwentts,
   MLX, or whisper dependencies. The scraper target must not be an implicit
   dependency of the stable bundle.

3. `zig build native-ai -Dnative-ai=true -Doptimize=ReleaseFast` produces the
   native-AI worker and its explicitly declared model/runtime payload. It may
   link qwentts.cpp, MLX/Metal, and whisper.cpp; those dependencies must be
   reachable only from this target (and native-only tests).

4. `zig build bundle-stable -Dnative-ai=false -Doptimize=ReleaseFast` creates
   a relocatable `Metanoia.app` whose executable and resources contain no
   native-AI worker, dylib, GGUF model, MLX checkpoint, or whisper model.

5. `zig build bundle-native-ai -Dnative-ai=true -Doptimize=ReleaseFast` is the
   explicit opt-in full bundle. It must not replace or mutate the stable
   bundle as a side effect. Both bundles must carry a manifest identifying
   the build flavor and the files included.

6. The default install step must remain stable-only. A contributor who runs
   `zig build` or `zig build test` on a clean checkout without
   `vendor/qwentts.cpp`, MLX, or whisper.cpp must not be asked to discover or
   link those libraries.

7. Changing scraper sources must invalidate `metanoia-scraper` only; changing
   native-AI sources must invalidate the native-AI worker only; changing the
   reader/core contract may invalidate its dependents. The stable target must
   have no reverse edge into either volatile target.

## Link and payload checks

On macOS, the stable artifact must pass all of the following. The forbidden
pattern is deliberately limited to native-AI names so GTK's own system
dependencies are not falsely rejected.

```sh
set -euo pipefail

stable_bin="zig-out/bin/metanoia"
test -x "$stable_bin"

if otool -L "$stable_bin" | rg -i \
  'libqwen|libmlxc|libwhisper|libggml|qwen_|ggml_|whisper_'; then
  echo "native-AI dependency leaked into stable binary" >&2
  exit 1
fi

if nm -u "$stable_bin" 2>/dev/null | rg -i \
  'qwen_|ggml_|whisper_|mlx'; then
  echo "native-AI symbol leaked into stable binary" >&2
  exit 1
fi
```

The equivalent Linux check is `ldd "$stable_bin"` plus
`readelf -d "$stable_bin"`; the same forbidden names must be absent. For a
Windows GNU cross-build, inspect the PE import table with
`llvm-objdump -p` or `objdump -p` and reject the same library names.

The stable app bundle must also prove absence at the payload level:

```sh
set -euo pipefail

stable_app="zig-out/Metanoia.app"
test -d "$stable_app"
! find "$stable_app" -type f -print | rg -i \
  'libqwen|libmlxc|libwhisper|libggml|qwen.*\\.(gguf|bin)|mlx|whisper.*\\.(bin|gguf)'
```

The native-AI bundle should perform the inverse positive check: its manifest
must list the worker executable, each required dynamic library, and each
model file with a size and checksum. A native bundle that happens to build
but cannot be relocated and load its libraries is not accepted.

## Clean-checkout and graph checks

The strongest stable-build check removes accidental reliance on ignored local
vendor directories by building a disposable Git archive:

```sh
set -euo pipefail

scratch="$(mktemp -d /private/tmp/metanoia-stable.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
git archive HEAD | tar -x -C "$scratch"
(cd "$scratch" && zig build stable -Dnative-ai=false -Doptimize=ReleaseFast)
```

The build must succeed without `vendor/qwentts.cpp`, MLX, or whisper.cpp. The
same archive must pass the stable test target. A failure here means the
stable graph has an undeclared native dependency, even if the developer's
full local checkout happens to build.

The build graph must expose the split and its opt-in nature:

```sh
set -euo pipefail

zig build --help | rg 'stable|scraper|native-ai|bundle-stable|bundle-native-ai'
zig build stable -Dnative-ai=false --verbose 2>&1 | tee /private/tmp/metanoia-stable-build.log
! rg -i 'aikit|qwentts|libqwen|mlx-c|whisper-cpp' \
  /private/tmp/metanoia-stable-build.log
```

The verbose command is a graph audit, not a substitute for `otool`/`ldd`:
source comments and cache paths can mention a dependency without linking it.
The link-table and symbol checks remain mandatory.

## Test-target invariants

`test-stable` must be the cheap, dependency-free gate for every change. It
must include the core/database, kit, app/build-configuration, and scraper
parser tests that do not perform network or native inference. It must not
instantiate a native model or require native model weights.

`test-native-ai` must be separate and must run only when the native target is
requested. It should cover the worker protocol, dynamic-library loading, and
one real TTS smoke test when local weights are present. Missing optional
weights may produce an explicit skip, but a missing required library or a
worker protocol failure must fail the target rather than silently falling back.

The current repository's transitional commands are:

```sh
zig build test -Dnative-ai=false -Doptimize=ReleaseFast
zig build -Dnative-ai=false -Doptimize=ReleaseFast

# Only on a machine with the native dependencies and model files:
zig build -Dnative-ai=true -Doptimize=ReleaseFast
zig build test-native-tts -Dnative-ai=true -Doptimize=ReleaseFast
```

The Python sidecar contract remains separate from the Zig link contract and
must use the repository's `uv` workflow:

```sh
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 uv run python -m pytest tests/test_tts_speed.py -q
uv run python -m py_compile tools/mlx_engine.py tools/metanoia_server/engine_loader.py
```

No bare `python` invocation should be added to acceptance or packaging
instructions.

## CI acceptance matrix

At minimum, CI should run these independent jobs:

- stable macOS arm64: clean archive, `stable`, `bundle-stable`, link/payload
  checks, and `test-stable`;
- stable Linux and Windows GNU cross-build: `stable` and target-appropriate
  dependency inspection;
- native macOS arm64: `native-ai`, `bundle-native-ai`, and
  `test-native-ai`, with the required qwentts/MLX/whisper assets provisioned
  explicitly;
- Python sidecar: the two `uv run` checks above.

The stable job must not install or cache native-AI dependencies. The native
job must not publish over the stable artifact. A green native job cannot mask
a failing stable job.

## Acceptance decision

The split is accepted only when the target list, clean-archive build,
dependency inspections, bundle payload checks, and test-target separation all
pass. Until then, `-Dnative-ai=false` is an opt-out safety gate, not evidence
that the next macOS bundle is fully isolated.
