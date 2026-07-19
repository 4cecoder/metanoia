//! Low-level C FFI to qwentts.cpp's libqwen (single-header `qwen.h`, plain
//! C99 ABI, validated in the Phase 0 spike — builds clean with Metal on
//! Apple Silicon via `-DQWEN_SHARED=ON`). Nothing in this file is
//! metanoia-specific; it could be lifted into any Zig project that wants to
//! call the same native library.
//!
//! Phase 1: real bindings against the actual `qwen.h` from
//! https://github.com/ServeurpersoCom/qwentts.cpp (commit checked out by
//! the Phase 1 build, QT_ABI_VERSION 2). Struct layouts below mirror the
//! header field-for-field (same order, same types) so `extern struct`
//! produces an ABI-compatible layout without a cImport step — qwen.h is a
//! plain-C99, POD-only header by design specifically so bindings like this
//! can parse it by hand (see qwen.h's own doc comment: "Bindings (Python
//! ctypes, Rust bindgen, Go cgo) parse this file directly").
//!
//! Confirmed against the real header: qwentts.cpp *does* support zero-shot
//! ICL (in-context-learning) voice cloning — pass a mono float32 PCM
//! reference clip at 24kHz via `ref_audio_24k`/`ref_n_samples` plus its
//! exact transcript via `ref_text` on `QtTtsParams`, mutually exclusive
//! with `speaker`/`instruct`. That's mode B in the header's terminology
//! (mode A is x-vector-only: `ref_audio_24k` with no `ref_text`).

const std = @import("std");

/// Opaque context handle. Definition lives in qwen.cpp; Zig only ever
/// holds a pointer.
pub const QwenContext = opaque {};

/// Mirrors `enum qt_status` in qwen.h. QT_STATUS_OK is zero so a caller
/// can still do `if (rc != .ok)`.
pub const QtStatus = enum(c_int) {
    ok = 0,
    invalid_params = -1,
    mode_invalid = -2,
    generate_failed = -3,
    oom = -4,
    cancelled = -5,
    _,
};

/// Mirrors `struct qt_audio`. `samples` is malloc-allocated by
/// `qt_synthesize`/owned by the struct — release with `qt_audio_free`,
/// never `free()` directly.
pub const QtAudio = extern struct {
    samples: ?[*]f32 = null,
    n_samples: c_int = 0,
    sample_rate: c_int = 0,
    channels: c_int = 0,
};

/// Mirrors `struct qt_init_params`.
pub const QtInitParams = extern struct {
    abi_version: c_int = 0,
    talker_path: ?[*:0]const u8 = null,
    codec_path: ?[*:0]const u8 = null,
    use_fa: bool = true,
    clamp_fp16: bool = false,
};

/// Mirrors `struct qt_voice_ref` — precomputed Base-model voice-clone
/// latents (speaker embedding + ICL RVQ codes). Both pointers are
/// malloc-allocated by `qt_extract_voice_ref`; release with
/// `qt_voice_ref_free`.
pub const QtVoiceRef = extern struct {
    ref_spk_emb: ?[*]f32 = null,
    ref_spk_dim: c_int = 0,
    ref_codes: ?[*]i32 = null,
    ref_T: c_int = 0,
    num_codebooks: c_int = 0,
};

pub const QtCancelCb = ?*const fn (user_data: ?*anyopaque) callconv(.c) bool;
pub const QtAudioChunkCb = ?*const fn (samples: ?[*]const f32, n_samples: c_int, user_data: ?*anyopaque) callconv(.c) bool;

pub const QtLogLevel = enum(c_int) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
    _,
};

pub const QtLogCb = ?*const fn (level: QtLogLevel, msg: ?[*:0]const u8, user_data: ?*anyopaque) callconv(.c) void;

/// Mirrors `struct qt_tts_params` (ABI v2). Field order matches the
/// header exactly — this is what makes the `extern struct` layout line
/// up with what `qt_tts_default_params` and `qt_synthesize` expect.
///
/// Voice cloning lives in two mutually-exclusive pairs:
///   - `ref_audio_24k`/`ref_n_samples` (+ optional `ref_text` for ICL
///     mode B) — raw reference WAV samples, decoded by the caller.
///   - `ref_spk_emb`/`ref_codes` (+ `ref_text`) — precomputed latents
///     from `qt_extract_voice_ref`, ABI v2 fast path that skips the
///     speaker encoder + codec encode on every synthesis call.
pub const QtTtsParams = extern struct {
    abi_version: c_int = 0,

    text: ?[*:0]const u8 = null,
    lang: ?[*:0]const u8 = null,
    instruct: ?[*:0]const u8 = null,
    speaker: ?[*:0]const u8 = null,

    ref_audio_24k: ?[*]const f32 = null,
    ref_n_samples: c_int = 0,
    ref_text: ?[*:0]const u8 = null,

    seed: i64 = -1,
    max_new_tokens: c_int = 2048,
    do_sample: bool = true,
    temperature: f32 = 0.9,
    top_k: c_int = 50,
    top_p: f32 = 1.0,
    repetition_penalty: f32 = 1.05,
    subtalker_do_sample: bool = true,
    subtalker_temperature: f32 = 0.9,
    subtalker_top_k: c_int = 50,
    subtalker_top_p: f32 = 1.0,

    dump_dir: ?[*:0]const u8 = null,

    cancel: QtCancelCb = null,
    cancel_user_data: ?*anyopaque = null,

    on_chunk: QtAudioChunkCb = null,
    on_chunk_user_data: ?*anyopaque = null,

    codec_chunk_sec: f32 = 24.0,
    codec_left_context_sec: f32 = 2.0,

    // ABI v2: pre-encoded voice reference latents.
    ref_spk_emb: ?[*]const f32 = null,
    ref_spk_dim: c_int = 0,
    ref_codes: ?[*]const i32 = null,
    ref_T: c_int = 0,
};

pub extern fn qt_version() [*:0]const u8;
pub extern fn qt_last_error() [*:0]const u8;

pub extern fn qt_audio_free(a: *QtAudio) void;

pub extern fn qt_init_default_params(p: *QtInitParams) void;
pub extern fn qt_init(params: *const QtInitParams) ?*QwenContext;
pub extern fn qt_free(q: ?*QwenContext) void;

pub extern fn qt_extract_voice_ref(
    q: *QwenContext,
    ref_audio_24k: [*]const f32,
    ref_n_samples: c_int,
    out: *QtVoiceRef,
) QtStatus;
pub extern fn qt_voice_ref_free(ref: *QtVoiceRef) void;

pub extern fn qt_log_set(cb: QtLogCb, user_data: ?*anyopaque) void;

pub extern fn qt_tts_default_params(p: *QtTtsParams) void;
pub extern fn qt_num_codebooks(q: ?*const QwenContext) c_int;
pub extern fn qt_synthesize(q: *QwenContext, params: *const QtTtsParams, out: *QtAudio) QtStatus;
pub extern fn qt_duration_sec_to_tokens(q: ?*const QwenContext, duration_sec: f32) c_int;

pub extern fn qt_n_speakers(q: ?*const QwenContext) c_int;
pub extern fn qt_speaker_name(q: ?*const QwenContext, i: c_int) ?[*:0]const u8;

test "QtTtsParams default-constructs via zig defaults matching header docs" {
    // Not a link test (no library present at `zig build test` time unless
    // wired via build.zig's linkSystemLibrary) — just a static sanity
    // check that the struct compiles and the Zig-side defaults documented
    // above match qwen.h's own doc comment for qt_tts_default_params.
    const p = QtTtsParams{};
    try std.testing.expectEqual(@as(i64, -1), p.seed);
    try std.testing.expectEqual(@as(c_int, 2048), p.max_new_tokens);
    try std.testing.expectEqual(@as(f32, 0.9), p.temperature);
}
