//! Raw C FFI to whisper.cpp's `libwhisper` (OpenAI Whisper ported to
//! GGML/C++ by the same ggml-org that builds qwentts.cpp — the model this
//! repo's TTS backend already vendors). Installed here via Homebrew
//! (`brew install whisper-cpp` — confirmed present: 1.9.1, headers/dylibs
//! under `/opt/homebrew/opt/whisper-cpp`, includes real Metal GPU support
//! on Apple Silicon, same as `backend/mlx.zig`/`backend/ggml.zig`).
//!
//! IMPORTANT — a new exception, not a continuation of an old one:
//! `README.md`'s "Design principle: no new external native deps" section
//! explicitly grandfathers in the *existing* GGML/MLX TTS backends and
//! says new capabilities should be clean-room Zig going forward, "don't
//! reach for FFI-bind an existing library as the default move ... the way
//! it was for TTS." Bringing in whisper.cpp for STT is a deliberate,
//! explicitly-acknowledged departure from that stated direction, made for
//! the same reason TTS's original exception was: getting a real,
//! battle-tested, Metal-accelerated capability working now is worth more
//! than a from-scratch encoder/decoder port up front, and the backend
//! seam (`capabilities/stt.zig`) keeps a future clean-room replacement a
//! drop-in swap rather than a rewrite of every caller. See README.md's
//! "STT (speech-to-text)" section for the explicit backlog entry this
//! creates: a clean-room Zig Whisper port (encoder/decoder on top of
//! `backend/mlx.zig`'s primitives, mirroring the LLM capability's own
//! from-FFI-spike-to-clean-room trajectory) is the intended eventual
//! replacement, not assumed to happen automatically.
//!
//! Struct layout note: `whisper_full_params` (declared below as
//! `WhisperFullParams`) is passed *by value* to `whisper_full` — unlike
//! `mlx.zig`'s `mlx_optional_int`-style small structs, this one is large
//! (~50 fields, several callback function pointers, two nested anonymous
//! structs) and passing an inaccurately-sized/laid-out version by value
//! would silently corrupt whatever the real C struct's trailing fields
//! are read as (this is exactly the class of bug README.md's LLM section
//! warns about — `mlx_dequantize`'s `dtype` struct-not-`c_int` incident).
//! So every field here is transcribed directly from the installed
//! `/opt/homebrew/opt/whisper-cpp/include/whisper.h` (whisper.cpp 1.9.1),
//! in exact declared order, not a hand-picked subset — the only safe way
//! to pass this type by value to a real `whisper_full` call.

const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .macos) {
        @compileError("backend/whisper.zig is macOS-only for now (Homebrew whisper-cpp path assumed) — see this file's doc comment for the cross-platform follow-up note");
    }
}

// --- Opaque handles ------------------------------------------------------

pub const whisper_context = opaque {};
pub const whisper_state = opaque {};

// --- Small value types (whisper.h, verbatim) ------------------------------

pub const whisper_token = i32;

pub const WhisperAhead = extern struct {
    n_text_layer: c_int,
    n_head: c_int,
};

pub const WhisperAheads = extern struct {
    n_heads: usize,
    heads: ?[*]const WhisperAhead,
};

pub const WhisperGrammarElement = extern struct {
    type: c_int, // enum whisper_gretype
    value: u32,
};

pub const WhisperVadParams = extern struct {
    threshold: f32,
    min_speech_duration_ms: c_int,
    min_silence_duration_ms: c_int,
    max_speech_duration_s: f32,
    speech_pad_ms: c_int,
    samples_overlap: f32,
};

pub const WHISPER_SAMPLING_GREEDY: c_int = 0;
pub const WHISPER_SAMPLING_BEAM_SEARCH: c_int = 1;

// --- whisper_context_params (whisper.h ~line 116) -------------------------

pub const WhisperContextParams = extern struct {
    use_gpu: bool,
    flash_attn: bool,
    gpu_device: c_int,

    dtw_token_timestamps: bool,
    dtw_aheads_preset: c_int, // enum whisper_alignment_heads_preset

    dtw_n_top: c_int,
    dtw_aheads: WhisperAheads,

    dtw_mem_size: usize,
};

// --- Callback typedefs (whisper.h ~line 463) -------------------------------

pub const whisper_new_segment_callback = ?*const fn (ctx: ?*whisper_context, state: ?*whisper_state, n_new: c_int, user_data: ?*anyopaque) callconv(.c) void;
pub const whisper_progress_callback = ?*const fn (ctx: ?*whisper_context, state: ?*whisper_state, progress: c_int, user_data: ?*anyopaque) callconv(.c) void;
pub const whisper_encoder_begin_callback = ?*const fn (ctx: ?*whisper_context, state: ?*whisper_state, user_data: ?*anyopaque) callconv(.c) bool;
pub const ggml_abort_callback = ?*const fn (data: ?*anyopaque) callconv(.c) bool;
pub const whisper_logits_filter_callback = ?*const fn (
    ctx: ?*whisper_context,
    state: ?*whisper_state,
    tokens: ?*const anyopaque, // whisper_token_data* — untyped, unused by this binding
    n_tokens: c_int,
    logits: ?[*]f32,
    user_data: ?*anyopaque,
) callconv(.c) void;

// --- whisper_full_params (whisper.h ~line 487) -----------------------------
//
// Every field, in exact declared order — see this file's doc comment on
// why a truncated subset isn't safe for a by-value C call.
pub const WhisperFullParams = extern struct {
    strategy: c_int, // enum whisper_sampling_strategy

    n_threads: c_int,
    n_max_text_ctx: c_int,
    offset_ms: c_int,
    duration_ms: c_int,

    translate: bool,
    no_context: bool,
    no_timestamps: bool,
    single_segment: bool,
    print_special: bool,
    print_progress: bool,
    print_realtime: bool,
    print_timestamps: bool,

    token_timestamps: bool,
    thold_pt: f32,
    thold_ptsum: f32,
    max_len: c_int,
    split_on_word: bool,
    max_tokens: c_int,

    debug_mode: bool,
    audio_ctx: c_int,

    tdrz_enable: bool,

    suppress_regex: ?[*:0]const u8,

    initial_prompt: ?[*:0]const u8,
    carry_initial_prompt: bool,
    prompt_tokens: ?[*]const whisper_token,
    prompt_n_tokens: c_int,

    language: ?[*:0]const u8,
    detect_language: bool,

    suppress_blank: bool,
    suppress_nst: bool,

    temperature: f32,
    max_initial_ts: f32,
    length_penalty: f32,

    temperature_inc: f32,
    entropy_thold: f32,
    logprob_thold: f32,
    no_speech_thold: f32,

    greedy: extern struct {
        best_of: c_int,
    },

    beam_search: extern struct {
        beam_size: c_int,
        patience: f32,
    },

    new_segment_callback: whisper_new_segment_callback,
    new_segment_callback_user_data: ?*anyopaque,

    progress_callback: whisper_progress_callback,
    progress_callback_user_data: ?*anyopaque,

    encoder_begin_callback: whisper_encoder_begin_callback,
    encoder_begin_callback_user_data: ?*anyopaque,

    abort_callback: ggml_abort_callback,
    abort_callback_user_data: ?*anyopaque,

    logits_filter_callback: whisper_logits_filter_callback,
    logits_filter_callback_user_data: ?*anyopaque,

    grammar_rules: ?[*]const ?[*]const WhisperGrammarElement,
    n_grammar_rules: usize,
    i_start_rule: usize,
    grammar_penalty: f32,

    vad: bool,
    vad_model_path: ?[*:0]const u8,

    vad_params: WhisperVadParams,
};

// --- Functions actually used by models/whisper_stt.zig ---------------------

/// Registers ggml's dynamically-loaded compute backends (CPU, Metal,
/// BLAS, ...) — required before `whisper_init_from_file_with_params`, or
/// `ggml_backend_dev_by_type`-style lookups inside whisper.cpp find zero
/// registered devices and hit `GGML_ASSERT(device)` deep inside
/// `make_buft_list`. Homebrew's `whisper-cli` calls this itself in its
/// own `main()` (as of ggml's multi-backend refactor, this is the
/// application's responsibility, not something `libwhisper.dylib`'s C API
/// does automatically) — found by comparing that a real `whisper-cli`
/// invocation against the exact same installed model/library worked while
/// this binding's first cut (missing this call) crashed with exactly that
/// assert.
pub extern "c" fn ggml_backend_load_all() callconv(.c) void;

pub extern "c" fn whisper_context_default_params() callconv(.c) WhisperContextParams;
pub extern "c" fn whisper_init_from_file_with_params(path_model: [*:0]const u8, params: WhisperContextParams) callconv(.c) ?*whisper_context;
pub extern "c" fn whisper_free(ctx: ?*whisper_context) callconv(.c) void;

pub extern "c" fn whisper_full_default_params_by_ref(strategy: c_int) callconv(.c) *WhisperFullParams;
/// Frees the pointer `whisper_full_default_params_by_ref` allocates (see
/// that function's doc comment in whisper.h).
pub extern "c" fn whisper_free_params(params: ?*WhisperFullParams) callconv(.c) void;

pub extern "c" fn whisper_full(ctx: ?*whisper_context, params: WhisperFullParams, samples: [*]const f32, n_samples: c_int) callconv(.c) c_int;

pub extern "c" fn whisper_full_n_segments(ctx: ?*whisper_context) callconv(.c) c_int;
pub extern "c" fn whisper_full_get_segment_text(ctx: ?*whisper_context, i_segment: c_int) callconv(.c) [*:0]const u8;

test "WhisperFullParams / WhisperContextParams have plausible non-zero, non-degenerate sizes" {
    // Not a substitute for real end-to-end verification (see
    // models/whisper_stt.zig's real-transcription test) — just a cheap
    // sanity check that the struct declarations above didn't collapse to
    // something obviously wrong (e.g. a typo turning a field into a
    // zero-sized type).
    try std.testing.expect(@sizeOf(WhisperFullParams) > 150);
    try std.testing.expect(@sizeOf(WhisperContextParams) > 20);
}
