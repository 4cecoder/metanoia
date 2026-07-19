# aikit

A standalone, backend-agnostic native-AI-inference library for Zig 0.17+.

## Design principle: no new external native deps

**Going forward, new capabilities in this library should be clean-room Zig
implementations — no wrapping a third-party C/C++ inference library.** The
existing TTS backends (`backend/ggml.zig` → qwentts.cpp, `backend/mlx.zig`
→ Apple's mlx-c) are **grandfathered in** — they were built, tested, and
verified working before this principle was set, and are not being ripped
out. But they're the exception, not the pattern to repeat: don't reach for
"just FFI-bind an existing library" as the default move for the next
capability (STT, LLM, etc.) the way it was for TTS. A clean-room
implementation means hand-writing the actual model forward pass (attention,
matmul, whatever the architecture needs) plus its own weight-loading code,
using nothing beyond the Zig standard library (and OS/GPU-vendor system
frameworks where compute genuinely requires them — e.g. Metal/Vulkan
compute shaders can't be pure Zig, but "don't link someone else's ML
inference library" is the actual rule being enforced here). This is a large
undertaking per capability — budget for it accordingly, and scope/spike
first (same as TTS's Phase 0) rather than assuming it's a quick add.

Not tied to metanoia. No imports of GTK, sqlite, or anything app-shaped
anywhere under `src/`. It has its own `build.zig`/`build.zig.zon` so it can
be pulled into any other Zig project independently — via `zig fetch --save`
against a path or git URL — the same way `src/kit/` is a decoupled UI
library *within* metanoia (see `../docs/KIT.md`), but one level further:
genuinely extractable, not just internally decoupled.

## Why this exists

metanoia's TTS voice-cloning feature ran entirely through a Python/FastAPI
server (`tools/tts_server.py`) called over HTTP from `src/tts_client.zig`.
The goal here is a native, in-process path — called directly as Zig
function calls, no subprocess/HTTP round trip — while explicitly **keeping**
the networked path available (bigger/remote models, platforms where local
inference isn't practical). See `../docs/MAINTENANCE.md` and the Phase 0
spike notes for the full history; short version: a native GGML/Metal port
of the target model (Qwen3-TTS, via
[qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp)) was
validated on the project's actual target hardware and passed.

## Design

```text
aikit/
├── build.zig / build.zig.zon   # standalone package — own identity, own deps
├── README.md
└── src/
    ├── root.zig                 # public API surface, re-exports below
    ├── capabilities/
    │   └── tts.zig               # backend-agnostic Synthesizer interface
    ├── backend/
    │   └── ggml.zig               # raw C FFI to a native inference library
    └── models/
        └── qwen3_tts.zig           # Qwen3-TTS impl of the Synthesizer interface
```

**The core idea is the split between `capabilities/` and `models/`.**
`capabilities/tts.zig` defines *what it means to be a TTS backend* — a small
vtable interface (`Synthesizer`), independent of any specific model or
inference runtime. `models/qwen3_tts.zig` is *one implementation* of that
interface, wrapping `backend/ggml.zig`'s raw FFI. A caller only ever holds a
`tts.Synthesizer` value:

```zig
const aikit = @import("aikit");

var model = try aikit.models.qwen3_tts.Qwen3TTS.init(model_path, codec_path);
defer model.synthesizer().deinit();

const audio = try model.synthesizer().synthesize(allocator, "For God so loved the world...", .{
    .voice = "lennox",
    .seed = 42,
});
defer audio.deinit(allocator);
```

**Adding a new capability** (say, LLM inference or native STT): add
`src/capabilities/llm.zig` with its own small interface (don't reuse `tts`'s
shape just because it's there — design each interface around what that
capability actually needs), then a `src/models/<whatever>.zig` implementing
it. `root.zig` re-exports both. Nothing in `capabilities/` or `backend/`
should ever import from `models/` — the dependency direction is strictly
`models/` → `capabilities/` + `backend/`, never the reverse, or the
interface stops being backend-agnostic.

## Cross-platform GPU: Vulkan on Windows/Linux (verified, not yet built)

`backend/ggml.zig`'s bindings (`qt_init`, `qt_synthesize`, ...) are
backend-agnostic — GGML picks its compute backend (Metal, Vulkan, CUDA,
CPU) at **build time** of `libqwen`, not something the Zig-side caller
branches on. Confirmed the vendored `qwentts.cpp`'s bundled `ggml`
submodule already ships a complete Vulkan backend
(`ggml/src/ggml-vulkan/ggml-vulkan.cpp` + `vulkan-shaders/`), gated behind
`option(GGML_VULKAN ... OFF)` in `ggml/CMakeLists.txt` — just switched off
by default. This means Windows/Linux support is expected to be a **build
configuration** change (`cmake .. -DGGML_VULKAN=ON` instead of
`-DGGML_METAL=ON`, requires the Vulkan SDK on that platform), not a new
Zig backend file the way `backend/mlx.zig` was needed for Apple MLX (MLX
has a wholly different C API; Vulkan is just another GGML compute backend
behind the same `qwen.h` surface). Not yet actually built/tested on
Windows or Linux — no such machine available in this environment — so
treat "should work unchanged" as a confident but unverified prediction
until someone builds it there.

**Adding a new backend for an existing capability** (say, an ONNX Runtime
version of TTS instead of/alongside GGML): add `src/backend/onnx.zig` (raw
FFI) and `src/models/qwen3_tts_onnx.zig` (or a differently-named model
entirely) implementing `capabilities/tts.zig`'s same `Synthesizer` vtable.
Callers that only depend on `tts.Synthesizer` don't change at all.

## Native backend (GGML)

`backend/ggml.zig` is currently a stub — the Phase 0 spike validated that
[qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp) builds cleanly
with Metal on Apple Silicon and produces correct output from its CLI, but
the actual Zig `extern fn` declarations against its `qwen.h` C API are
Phase 1 work, not yet written.

To build the native library this will eventually link against:

```bash
git clone --recurse-submodules https://github.com/ServeurpersoCom/qwentts.cpp.git
cd qwentts.cpp && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DQWEN_SHARED=ON
cmake --build .
```

Pre-converted GGUF weights: https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF
(no conversion step needed — verified in the Phase 0 spike).

## How this plugs into metanoia

`src/tts_client.zig` already externalizes its TTS server URL via
`data/config.json` (`tts_server_url`, defaulting to
`http://127.0.0.1:8000`) — the plan is a new `tts_mode: "native" | "remote"`
config field. `"remote"` keeps today's `curl`-to-`tts_server.py` path
completely untouched; `"native"` calls into `aikit.models.qwen3_tts`
in-process instead. Neither precludes the other — this is meant to make the
networked path an explicit choice, not remove it.
