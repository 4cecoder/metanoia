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
capability the way it was for TTS. A clean-room implementation means
hand-writing the actual model forward pass (attention, matmul, whatever the
architecture needs) plus its own weight-loading code, using nothing beyond
the Zig standard library (and OS/GPU-vendor system frameworks where compute
genuinely requires them — e.g. Metal/Vulkan compute shaders can't be pure
Zig, but "don't link someone else's ML inference library" is the actual
rule being enforced here). This is a large undertaking per capability —
budget for it accordingly, and scope/spike first (same as TTS's Phase 0)
rather than assuming it's a quick add.

**How this actually played out for the next two capabilities:** LLM
inference followed the principle — `models/qwen2_mlx.zig` is a hand-written
Qwen2 forward pass on top of `backend/mlx.zig`'s tensor primitives, no
LLM-specific library wrapped (see the "LLM inference" section below). STT
did not — `models/whisper_stt.zig` FFI-binds whisper.cpp, a second explicit,
documented exception alongside TTS's (see the "STT" section below for the
reasoning and the clean-room-Zig-Whisper backlog item that exception
creates). Two capabilities, two different honest calls — not a rule that
silently stopped being followed.

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

## LLM inference (working capability, native + remote)

Replaces metanoia's Ollama dependency (`src/ollama_client.zig`, a `curl`
subprocess to a locally-running Ollama server) with native in-process LLM
inference, kept alongside the old path exactly like TTS's `tts_backend`
switch — `data/config.json`'s `llm_backend: "native" | "remote"` (default
`"remote"`), see `src/llm_client.zig`.

`capabilities/llm.zig` (`Generator` interface) + `models/qwen2_mlx.zig`
(`Model`, `KVCache`, `Qwen2LLM`) implement this end to end against a real
`mlx-community/Qwen2.5-0.5B-Instruct-4bit` checkpoint (~265MB): a from-scratch
Zig BPE tokenizer (`src/tokenizer.zig`) for Qwen's `tokenizer.json`; the full
per-layer forward pass (embed → 24×[RMSNorm → GQA attention w/ RoPE →
residual → RMSNorm → SwiGLU MLP → residual] → final norm → tied lm_head)
on top of `backend/mlx.zig`'s fused ops (`mlx_fast_scaled_dot_product_attention`,
`mlx_fast_rope`, `mlx_fast_rms_norm`, quantized matmul); a KV cache so
autoregressive decoding only computes attention for each new token against
the cached prefix, not the whole sequence every step; and greedy generation,
verified token-for-token against a real `mlx_lm` Python reference (`"The
capital of France is"` → the same 10 greedily-decoded token ids the Python
run produces, exactly). `Qwen2LLM` wraps this with the checkpoint's own
ChatML instruct template for the app-facing text-in/text-out `Generator`
interface `src/llm_client.zig` calls into.

Model weights: expected at `vendor/llm/qwen2.5-0.5b-instruct-4bit/`
(`tokenizer.json` + `model.safetensors`), gitignored — see
`src/llm_client.zig`'s `native_model_dir` doc comment.

Along the way, this hit exactly the class of silent FFI-ABI bug this
section used to warn about in the abstract: `mlx_dequantize`'s `dtype`
parameter being a struct, not a bare `c_int`, caught only by comparing
against expected value ranges rather than a crash. Worth remembering for
the next FFI surface (see the STT section below, which hit its own
version of this with `whisper_full_params`).

## STT (speech-to-text): whisper.cpp now, clean-room Zig later (backlog)

**A deliberate, explicitly-acknowledged new exception to "no new external
native deps going forward" above — not a quiet reach for the easy option.**
`capabilities/stt.zig` (`Transcriber` interface) is implemented by
`models/whisper_stt.zig` on top of `backend/whisper.zig`, a raw FFI binding
to [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (installed via
`brew install whisper-cpp`, 1.9.1 — real Metal GPU support on Apple
Silicon, same `ggml` lineage as `backend/ggml.zig`/qwentts.cpp). This is
a second FFI exception on top of TTS's grandfathered one, chosen for the
same reason: a real, battle-tested, already-correct Whisper implementation
now is worth more than a from-scratch encoder/decoder port up front, and
the `capabilities/stt.zig` seam keeps a future clean-room replacement a
drop-in swap for callers rather than a rewrite.

**Backlog: clean-room Zig Whisper port.** The eventual replacement — a
hand-written Whisper encoder/decoder (conv stem → transformer encoder →
cross-attention transformer decoder) on top of `backend/mlx.zig`'s
primitives, mirroring the LLM capability's own FFI-spike → clean-room
trajectory — is **not started**, and not scoped in detail yet. Roughly
comparable in size to the LLM build (Whisper's architecture is smaller
per-layer than a modern LLM but needs a mel-spectrogram frontend and
cross-attention, neither of which the LLM work needed). Filed here as an
explicit backlog item, not assumed to happen automatically just because
the seam exists.

**Verified against real audio and a real checkpoint**
(`examples/stt_transcribe.zig`, `zig build run-stt-transcribe`): loads
`ggml-tiny.en.bin` (downloaded from
`https://huggingface.co/ggerganov/whisper.cpp`) and transcribes
`data/tommy.wav` (24kHz mono — resampled to the 16kHz mono float32
`whisper_full` requires by a from-scratch linear-interpolation resampler
in `models/whisper_stt.zig`, so this capability doesn't pull in a *second*
new dependency — e.g. whisper.cpp's own CLI tools use a vendored
`miniaudio` for this, which this binding deliberately doesn't link
against). Real output: `" Okay. I do believe I am alive."` — a real
transcription, not a hardcoded/mocked one (compare `whisper-cli`'s own
CLI, run standalone against the same file/model with its different
default decoding strategy — beam search 5 + best-of-5 vs. this binding's
greedy default — which produced the very similar `" I do believe I am
live."`; the difference is decoding-strategy noise on a short, slightly
ambiguous utterance, not a correctness bug).

**FFI struct layout, done the careful way (see this section's own
close call):** `whisper_full_params` is a large (~50-field) struct passed
*by value* to `whisper_full`. An earlier draft of this binding declared
only the leading fields this capability actually sets and left the rest
implicit — that's **not safe** for a by-value C call (unlike reading
through an already-correctly-sized pointer): the C ABI needs the caller's
declared struct size to match the real one, or trailing fields (including
several callback function pointers) get read from uninitialized/adjacent
stack memory. `backend/whisper.zig` transcribes every field from the
installed `whisper.h` in exact order instead — the only safe way to pass
this type by value. A sanity-check test (`@sizeOf(WhisperFullParams) >
150`) guards against the layout collapsing silently in a future edit, but
isn't a substitute for the real-transcription test above.

**A second real gotcha, found empirically, not predicted:**
`whisper_init_from_file_with_params` crashed
(`GGML_ASSERT(device) failed` inside `make_buft_list`, "devices = 0,
backends = 0") the first time this ran, despite `whisper-cli` (Homebrew's
own prebuilt binary) working fine against the identical model/library
install. Root cause: ggml's `ggml_backend_load_all()` (which
`models/whisper_stt.zig` now calls before every `whisper_init_from_file_with_params`
— required, not automatic) `dlopen`s its actual CPU/Metal backends from
separate plugin files under `/opt/homebrew/Cellar/ggml/*/libexec/*.so` —
discovered by inspecting that directory directly, since neither
`whisper-cpp`'s nor `ggml`'s own `lib/` dirs contain them. That discovery
only succeeded once this binary's own rpath included `ggml`'s `lib/` dir
too, not just `whisper-cpp`'s (see `build.zig`'s `linkWhisper` for the fix
and the standalone `zig build-exe` repro that isolated it). Filed here
because it's exactly the kind of "worked in the reference CLI, silently
different in a fresh binding" trap this README's LLM section already
warned about in the abstract — this is what it looks like in practice for
a second, unrelated FFI surface.

**Not wired into the app.** Unlike TTS/LLM, metanoia currently has no
existing speech-input feature/call site to swap a backend under — this is
new capability infrastructure, not a drop-in replacement for something
that already existed. Wiring it into the app (a dictation/voice-note
feature, or whatever the actual product need turns out to be) is separate,
unscoped follow-up work.

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
