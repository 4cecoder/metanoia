//! Raw C FFI to Apple's MLX (`mlx-c`), for a Metal-accelerated backend on
//! macOS. Adapted from the working binding in the user's `cosmic` project
//! (`/Users/fource/bytecats/cosmic/src/platform/macos/mlx.zig`), which
//! proved this exact API surface links and runs (a small feed-forward net
//! via matmul/tanh) against `mlx-c` installed through Homebrew
//! (`brew install mlx-c` — confirmed present here too: 0.6.0_3, headers at
//! `/opt/homebrew/include/mlx`, `libmlxc.dylib` at `/opt/homebrew/lib`).
//!
//! Why this backend exists alongside `ggml.zig`: the project's current
//! Python TTS pipeline already runs Qwen3-TTS through `mlx_audio.tts.load`
//! (Apple's MLX) on Apple Silicon — see `tools/mlx_engine.py`. A native MLX
//! backend would run the *same* framework, same quantized weights, most
//! likely to match today's behavior/quality exactly. `backend/ggml.zig`
//! (qwentts.cpp) is the cross-platform path (Linux/Windows have no MLX) —
//! see `capabilities/tts.zig` for how `models/` picks a backend per target.
//!
//! IMPORTANT SCOPE NOTE: this file only wraps MLX's low-level tensor
//! primitives (array creation, matmul, elementwise ops, eval) — the same
//! level as PyTorch's `torch.*` ops, not a "load this HuggingFace model"
//! API. `mlx_audio`'s Python model classes implement Qwen3-TTS's actual
//! architecture (28-layer Talker transformer, Code Predictor, RVQ vocoder)
//! *on top of* these primitives. Using this backend for real TTS inference
//! means porting that architecture to Zig using these ops — a materially
//! larger task than `backend/ggml.zig`, where qwentts.cpp already
//! implements the full model in C++. Track that as its own scoped task
//! before assuming this file alone gets TTS working on this backend.

const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .macos) {
        @compileError("backend/mlx.zig is macOS-only (Apple MLX/Metal) — see backend/ggml.zig for the cross-platform path");
    }
}

// --- MLX C API types ---------------------------------------------------
pub const mlx_array = extern struct { ctx: ?*anyopaque };
pub const mlx_stream = extern struct { ctx: ?*anyopaque };
pub const mlx_vector_array = extern struct { ctx: ?*anyopaque };
pub const mlx_device = extern struct { ctx: ?*anyopaque };
pub const mlx_map_string_to_array = extern struct { ctx: ?*anyopaque };
pub const mlx_map_string_to_string = extern struct { ctx: ?*anyopaque };
pub const mlx_optional_int = extern struct { value: c_int, has_value: bool };
pub const mlx_optional_dtype = extern struct { value: c_int, has_value: bool };
pub const mlx_optional_float = extern struct { value: f32, has_value: bool };

// --- MLX C API functions (manual extern declarations, mlx-c 0.6.x) -----
pub extern "c" fn mlx_vector_array_new() callconv(.c) mlx_vector_array;
pub extern "c" fn mlx_vector_array_append_value(vec: mlx_vector_array, v: mlx_array) callconv(.c) c_int;
pub extern "c" fn mlx_vector_array_free(vec: mlx_vector_array) callconv(.c) c_int;

pub extern "c" fn mlx_array_new_data(data: ?*const anyopaque, shape: [*]const i32, dim: c_int, dtype: c_int) callconv(.c) mlx_array;
pub extern "c" fn mlx_array_data_float32(arr: mlx_array) callconv(.c) [*]const f32;
pub extern "c" fn mlx_array_free(arr: mlx_array) callconv(.c) c_int;
pub extern "c" fn mlx_array_ndim(arr: mlx_array) callconv(.c) usize;
pub extern "c" fn mlx_array_shape(arr: mlx_array) callconv(.c) [*]const c_int;
pub extern "c" fn mlx_array_dtype(arr: mlx_array) callconv(.c) c_int;

pub extern "c" fn mlx_add(res: *mlx_array, a: mlx_array, b: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_subtract(res: *mlx_array, a: mlx_array, b: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_multiply(res: *mlx_array, a: mlx_array, b: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_matmul(res: *mlx_array, a: mlx_array, b: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_transpose(res: *mlx_array, a: mlx_array, s: mlx_stream) callconv(.c) c_int;

/// Permutes `a`'s axes to the given order (e.g. `axes=&.{0,2,1,3}` swaps
/// axes 1 and 2) — unlike `mlx_transpose` (full axis reversal), this picks
/// an arbitrary permutation. Used for the `(B,L,H,D) -> (B,H,L,D)` reshape
/// every attention head split needs. Mirrors Python
/// `mlx.core.transpose(a, axes)`.
pub extern "c" fn mlx_transpose_axes(res: *mlx_array, a: mlx_array, axes: [*]const c_int, axes_num: usize, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_tanh(res: *mlx_array, a: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_sin(res: *mlx_array, a: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_cos(res: *mlx_array, a: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_eval(outputs: mlx_vector_array) callconv(.c) c_int;
pub extern "c" fn mlx_random_seed(seed: u64) callconv(.c) c_int;
pub extern "c" fn mlx_device_new_type(device_type: c_int, index: c_int) callconv(.c) mlx_device;
pub extern "c" fn mlx_default_gpu_stream_new() callconv(.c) mlx_stream;
pub extern "c" fn mlx_default_cpu_stream_new() callconv(.c) mlx_stream;

pub extern "c" fn mlx_sigmoid(res: *mlx_array, a: mlx_array, s: mlx_stream) callconv(.c) c_int;

/// Row-gather along `axis` — e.g. embedding lookup: `a` is the `[vocab,
/// dim]` embedding matrix, `indices` an int32 array of token ids, `axis=0`.
/// (mirrors Python `mlx.core.take(a, indices, axis)`.)
pub extern "c" fn mlx_take_axis(res: *mlx_array, a: mlx_array, indices: mlx_array, axis: c_int, s: mlx_stream) callconv(.c) c_int;

pub extern "c" fn mlx_softmax_axis(res: *mlx_array, a: mlx_array, axis: c_int, precise: bool, s: mlx_stream) callconv(.c) c_int;

pub extern "c" fn mlx_reshape(res: *mlx_array, a: mlx_array, shape: [*]const i32, shape_num: usize, s: mlx_stream) callconv(.c) c_int;

/// Splits `a` along `axis` at the given section boundaries (e.g.
/// `indices=[3]` on a length-6 axis splits it into `[0:3]` and `[3:6]`).
/// Mirrors Python `mlx.core.split(a, indices, axis)`.
pub extern "c" fn mlx_split_sections(res: *mlx_vector_array, a: mlx_array, indices: [*]const i32, indices_num: usize, axis: c_int, s: mlx_stream) callconv(.c) c_int;

pub extern "c" fn mlx_concatenate_axis(res: *mlx_array, arrays: mlx_vector_array, axis: c_int, s: mlx_stream) callconv(.c) c_int;

pub extern "c" fn mlx_slice(
    res: *mlx_array,
    a: mlx_array,
    start: [*]const i32,
    start_num: usize,
    stop: [*]const i32,
    stop_num: usize,
    strides: [*]const i32,
    strides_num: usize,
    s: mlx_stream,
) callconv(.c) c_int;

pub extern "c" fn mlx_vector_array_size(vec: mlx_vector_array) callconv(.c) usize;
pub extern "c" fn mlx_vector_array_get(res: *mlx_array, vec: mlx_vector_array, idx: usize) callconv(.c) c_int;

/// RMSNorm, fused: `weight` may be a null `mlx_array` (`.{ .ctx = null }`)
/// for unweighted normalization; Qwen2 layers always supply one.
pub extern "c" fn mlx_fast_rms_norm(res: *mlx_array, x: mlx_array, weight: mlx_array, eps: f32, s: mlx_stream) callconv(.c) c_int;

/// Rotary positional encoding, fused. `x` must be at least 3D,
/// `(B, *, T, D)`. Exactly one of `base`/`freqs` must be set — pass
/// `freqs` as a null `mlx_array` when using `base`. `offset` is the
/// starting sequence position (0 for a fresh forward pass, `cache_len`
/// when decoding with a KV cache).
pub extern "c" fn mlx_fast_rope(
    res: *mlx_array,
    x: mlx_array,
    dims: c_int,
    traditional: bool,
    base: mlx_optional_float,
    scale: f32,
    offset: c_int,
    freqs: mlx_array,
    s: mlx_stream,
) callconv(.c) c_int;

/// Fused multi-head attention: `O = softmax(Q @ K^T * scale) @ V`.
/// `queries`/`keys`/`values` are `[B, N_heads, T, D]` (K/V may have fewer
/// heads than Q for GQA — not pre-tiled). `mask_mode` is `"causal"` for
/// causal masking, `""` for none; `mask_arr`/`sinks` are null `mlx_array`s
/// (`.{ .ctx = null }`) when unused.
pub extern "c" fn mlx_fast_scaled_dot_product_attention(
    res: *mlx_array,
    queries: mlx_array,
    keys: mlx_array,
    values: mlx_array,
    scale: f32,
    mask_mode: [*:0]const u8,
    mask_arr: mlx_array,
    sinks: mlx_array,
    s: mlx_stream,
) callconv(.c) c_int;

/// Loads an MLX-format `.safetensors` checkpoint (weights + metadata),
/// e.g. `model.safetensors` from any `mlx-community/*` HuggingFace repo.
/// LLM-capability groundwork — see the "LLM inference (research)" section
/// below; validated against a real 265MB Qwen2.5-0.5B-4bit checkpoint in
/// aikit/examples/llm_spike.zig.
///
/// NOTE (mlx-c 0.6.0): loading is CPU-only — evaluating a `Load` op on the
/// GPU stream fails with "Load::eval_gpu Not implemented". Pass
/// `defaultCpuStream()` here, not `defaultStream()`.
pub extern "c" fn mlx_load_safetensors(
    weights_out: *mlx_map_string_to_array,
    metadata_out: *mlx_map_string_to_string,
    file: [*:0]const u8,
    s: mlx_stream,
) callconv(.c) c_int;
pub extern "c" fn mlx_map_string_to_array_new() callconv(.c) mlx_map_string_to_array;
pub extern "c" fn mlx_map_string_to_array_get(value: *mlx_array, map: mlx_map_string_to_array, key: [*:0]const u8) callconv(.c) c_int;
pub extern "c" fn mlx_map_string_to_string_new() callconv(.c) mlx_map_string_to_string;

/// Dequantizes an affine-quantized weight matrix (the format `mlx_lm`/
/// `mlx-community` checkpoints ship linear-layer weights in: a packed
/// `w` tensor plus per-group `scales`/`biases`) back to float32.
/// `group_size`/`bits` come from the checkpoint's `config.json`
/// `"quantization"` block (commonly `{group_size: 64, bits: 4}`).
pub extern "c" fn mlx_dequantize(
    res: *mlx_array,
    w: mlx_array,
    scales: mlx_array,
    biases: mlx_array,
    group_size: mlx_optional_int,
    bits: mlx_optional_int,
    mode: [*:0]const u8,
    global_scale: mlx_array,
    dtype: mlx_optional_dtype,
    s: mlx_stream,
) callconv(.c) c_int;

/// Fused affine-quantized linear layer: `x @ w^T` (when `transpose=true`,
/// the layout every `mlx-community`/`mlx_lm` checkpoint's quantized
/// `nn.Linear`/tied-embedding weights use) without ever materializing a
/// dequantized `[out, in]` float matrix — the counterpart to
/// `mlx_dequantize` used for the *embedding lookup* path (small `take`d
/// row slice, cheap to dequantize) vs. this one for the *projection* path
/// (full weight matrix, e.g. the 151936-row tied `lm_head`, where
/// dequantizing the whole thing first would be wasteful).
/// `biases` may be a null `mlx_array` (`.{ .ctx = null }`) when the
/// quantized layer has none (mlx-c 0.6.0's affine mode always has one in
/// practice, but the C API allows it).
pub extern "c" fn mlx_quantized_matmul(
    res: *mlx_array,
    x: mlx_array,
    w: mlx_array,
    scales: mlx_array,
    biases: mlx_array,
    transpose: bool,
    group_size: mlx_optional_int,
    bits: mlx_optional_int,
    mode: [*:0]const u8,
    s: mlx_stream,
) callconv(.c) c_int;

var g_stream: ?mlx_stream = null;
var g_cpu_stream: ?mlx_stream = null;

fn defaultStream() mlx_stream {
    if (g_stream) |s| return s;
    const s = mlx_default_gpu_stream_new();
    g_stream = s;
    return s;
}

/// See `mlx_load_safetensors`'s doc comment — checkpoint loading must run
/// on this stream, not the GPU one.
pub fn defaultCpuStream() mlx_stream {
    if (g_cpu_stream) |s| return s;
    const s = mlx_default_cpu_stream_new();
    g_cpu_stream = s;
    return s;
}

pub fn getMetalDevice() mlx_device {
    return mlx_device_new_type(1, 0); // GPU device
}

/// Thin owning wrapper around `mlx_array`. Mirrors cosmic's `Array` type —
/// deliberately minimal (the primitives an actual model port will need
/// first: construction from host data, matmul, elementwise ops, eval,
/// readback). Extend as real Qwen3-TTS-porting work needs more ops
/// (softmax, embedding lookup, RoPE, etc. aren't here yet).
pub const Array = struct {
    handle: mlx_array,

    pub fn fromFloat32(data: []const f32, dims: []const i32) Array {
        const arr = mlx_array_new_data(data.ptr, dims.ptr, @intCast(dims.len), 10); // 10 = float32 dtype
        return .{ .handle = arr };
    }

    pub fn asFloat32(self: Array, out: []f32) void {
        self.eval();
        const ptr = mlx_array_data_float32(self.handle);
        @memcpy(out, ptr[0..out.len]);
    }

    pub fn matmul(a: Array, b: Array) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_matmul(&res, a.handle, b.handle, defaultStream());
        return .{ .handle = res };
    }

    pub fn add(a: Array, b: Array) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_add(&res, a.handle, b.handle, defaultStream());
        return .{ .handle = res };
    }

    pub fn sub(a: Array, b: Array) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_subtract(&res, a.handle, b.handle, defaultStream());
        return .{ .handle = res };
    }

    pub fn mul(a: Array, b: Array) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_multiply(&res, a.handle, b.handle, defaultStream());
        return .{ .handle = res };
    }

    pub fn tanh(a: Array) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_tanh(&res, a.handle, defaultStream());
        return .{ .handle = res };
    }

    pub fn transpose(a: Array) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_transpose(&res, a.handle, defaultStream());
        return .{ .handle = res };
    }

    /// Permutes axes to an arbitrary order (`mlx_transpose_axes`) — e.g.
    /// `a.transposeAxes(&.{ 0, 2, 1, 3 })` for the `(B,L,H,D) -> (B,H,L,D)`
    /// head split every multi-head attention projection needs.
    pub fn transposeAxes(a: Array, axes: []const i32) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_transpose_axes(&res, a.handle, axes.ptr, axes.len, defaultStream());
        return .{ .handle = res };
    }

    pub fn sigmoid(a: Array) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_sigmoid(&res, a.handle, defaultStream());
        return .{ .handle = res };
    }

    /// SwiGLU's activation half: `silu(x) = x * sigmoid(x)`. mlx-c 0.6.0
    /// has no fused `mlx_silu` — composed from `mlx_sigmoid`/`mlx_multiply`.
    pub fn silu(a: Array) Array {
        return a.mul(a.sigmoid());
    }

    /// From int32 token ids: `fromInt32(&.{ 5, 12 }, &.{2})`. Needed for
    /// embedding lookup indices (`mlx_take_axis` requires an integral dtype).
    pub fn fromInt32(data: []const i32, dims: []const i32) Array {
        const arr = mlx_array_new_data(data.ptr, dims.ptr, @intCast(dims.len), 7); // 7 = int32 dtype
        return .{ .handle = arr };
    }

    /// Embedding lookup: row-gathers `table` (`[vocab, dim]`) by
    /// `indices` (int32, e.g. `[seq_len]`), producing `[seq_len, dim]`.
    pub fn embedding(table: Array, indices: Array) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_take_axis(&res, table.handle, indices.handle, 0, defaultStream());
        return .{ .handle = res };
    }

    pub fn softmax(a: Array, axis: i32) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_softmax_axis(&res, a.handle, axis, true, defaultStream());
        return .{ .handle = res };
    }

    pub fn reshape(a: Array, dims: []const i32) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_reshape(&res, a.handle, dims.ptr, dims.len, defaultStream());
        return .{ .handle = res };
    }

    /// General slice: `start[i]..stop[i]` (step `strides[i]`, default 1
    /// each) along every axis. `stop`/`strides` must be `null` together
    /// with unit strides, or provided per-axis matching `start`'s length.
    pub fn slice(a: Array, start: []const i32, stop: []const i32, strides: ?[]const i32) Array {
        var res = mlx_array{ .ctx = null };
        var ones_buf: [8]i32 = undefined;
        const strides_slice = strides orelse blk: {
            for (ones_buf[0..start.len]) |*v| v.* = 1;
            break :blk ones_buf[0..start.len];
        };
        _ = mlx_slice(
            &res,
            a.handle,
            start.ptr,
            start.len,
            stop.ptr,
            stop.len,
            strides_slice.ptr,
            strides_slice.len,
            defaultStream(),
        );
        return .{ .handle = res };
    }

    /// Splits `a` along `axis` at section boundaries given by `indices`
    /// (e.g. `indices=&.{3}` on a length-6 axis yields two parts,
    /// `[0:3]` and `[3:6]`) — used for e.g. pulling Q/K/V out of a fused
    /// QKV projection. Caller owns the returned slice (`allocator.free`)
    /// and each resulting `Array` (`.free()`).
    pub fn split(a: Array, allocator: std.mem.Allocator, indices: []const i32, axis: i32) ![]Array {
        var vec = mlx_vector_array{ .ctx = null };
        _ = mlx_split_sections(&vec, a.handle, indices.ptr, indices.len, axis, defaultStream());
        defer _ = mlx_vector_array_free(vec);

        const n = mlx_vector_array_size(vec);
        const out = try allocator.alloc(Array, n);
        for (out, 0..) |*slot, i| {
            var elem = mlx_array{ .ctx = null };
            _ = mlx_vector_array_get(&elem, vec, i);
            slot.* = .{ .handle = elem };
        }
        return out;
    }

    /// Concatenates `arrays` along `axis` — e.g. growing a KV cache by
    /// appending the current step's keys/values along the sequence axis.
    pub fn concat(arrays: []const Array, axis: i32) Array {
        const vec = mlx_vector_array_new();
        defer _ = mlx_vector_array_free(vec);
        for (arrays) |arr| _ = mlx_vector_array_append_value(vec, arr.handle);

        var res = mlx_array{ .ctx = null };
        _ = mlx_concatenate_axis(&res, vec, axis, defaultStream());
        return .{ .handle = res };
    }

    /// RMSNorm, fused (`mlx_fast_rms_norm`): `x / sqrt(mean(x^2) + eps) * weight`.
    pub fn rmsNorm(x: Array, weight: Array, eps: f32) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_fast_rms_norm(&res, x.handle, weight.handle, eps, defaultStream());
        return .{ .handle = res };
    }

    /// Rotary positional encoding, fused (`mlx_fast_rope`). `x` must be
    /// at least 3D, `(B, *, T, D)`. `dims` is how many of the trailing
    /// feature dims get rotated (Qwen2: the full head dim). `offset` is
    /// the starting sequence position (0 on a fresh forward pass).
    pub fn rope(x: Array, dims: i32, traditional: bool, base: f32, scale: f32, offset: i32) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_fast_rope(
            &res,
            x.handle,
            dims,
            traditional,
            .{ .value = base, .has_value = true },
            scale,
            offset,
            mlx_array{ .ctx = null }, // freqs: unused when base is set
            defaultStream(),
        );
        return .{ .handle = res };
    }

    /// Fused scaled dot-product attention (`mlx_fast_scaled_dot_product_attention`):
    /// `softmax(Q @ K^T * scale) @ V`. `q`/`k`/`v` are `[B, N_heads, T, D]`
    /// (K/V may have fewer heads than Q for GQA — not pre-tiled).
    /// `causal` selects mlx's built-in causal mask; there's no support
    /// here yet for an explicit mask array.
    pub fn attention(q: Array, k: Array, v: Array, scale: f32, causal: bool) Array {
        var res = mlx_array{ .ctx = null };
        const mask_mode: [*:0]const u8 = if (causal) "causal" else "";
        _ = mlx_fast_scaled_dot_product_attention(
            &res,
            q.handle,
            k.handle,
            v.handle,
            scale,
            mask_mode,
            mlx_array{ .ctx = null },
            mlx_array{ .ctx = null },
            defaultStream(),
        );
        return .{ .handle = res };
    }

    /// See `mlx_dequantize`'s doc comment for what `group_size`/`bits`/
    /// `scales`/`biases` mean — this wraps the common "affine" mode case.
    pub fn dequantizeAffine(w: Array, scales: Array, biases: Array, group_size: i32, bits: i32) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_dequantize(
            &res,
            w.handle,
            scales.handle,
            biases.handle,
            .{ .value = group_size, .has_value = true },
            .{ .value = bits, .has_value = true },
            "affine",
            mlx_array{ .ctx = null },
            .{ .value = 10, .has_value = true }, // 10 = float32
            defaultStream(),
        );
        return .{ .handle = res };
    }

    /// Affine-quantized linear layer, fused (`mlx_quantized_matmul`):
    /// `x @ w^T` where `w`/`scales`/`biases` are a checkpoint's packed
    /// `*.weight` (`uint32`) / `*.scales` / `*.biases` triple for one
    /// quantized `nn.Linear` (or a tied embedding used as `lm_head`).
    /// `transpose=true` always, matching every `mlx-community` checkpoint's
    /// `[out_features, in_features]` weight layout.
    pub fn linearQuantized(x: Array, w: Array, scales: Array, biases: Array, group_size: i32, bits: i32) Array {
        var res = mlx_array{ .ctx = null };
        _ = mlx_quantized_matmul(
            &res,
            x.handle,
            w.handle,
            scales.handle,
            biases.handle,
            true,
            .{ .value = group_size, .has_value = true },
            .{ .value = bits, .has_value = true },
            "affine",
            defaultStream(),
        );
        return .{ .handle = res };
    }

    pub fn shape(a: Array) []const c_int {
        return mlx_array_shape(a.handle)[0..mlx_array_ndim(a.handle)];
    }

    pub fn eval(a: Array) void {
        const vec = mlx_vector_array_new();
        defer _ = mlx_vector_array_free(vec);
        _ = mlx_vector_array_append_value(vec, a.handle);
        _ = mlx_eval(vec);
    }

    pub fn free(a: Array) void {
        _ = mlx_array_free(a.handle);
    }
};

/// An open `.safetensors` checkpoint's weight map — `get()` looks up a
/// tensor by its checkpoint key (e.g. `"model.layers.0.self_attn.q_proj.weight"`).
/// Validated against a real Qwen2.5-0.5B-4bit checkpoint (see
/// aikit/examples/llm_spike.zig) — this is LLM-capability groundwork, not
/// yet used by any shipped capability.
pub const Checkpoint = struct {
    weights: mlx_map_string_to_array,
    metadata: mlx_map_string_to_string,

    pub fn load(path: [:0]const u8) !Checkpoint {
        var weights = mlx_map_string_to_array_new();
        var metadata = mlx_map_string_to_string_new();
        // Loading is CPU-only in mlx-c 0.6.0 — see mlx_load_safetensors's doc comment.
        if (mlx_load_safetensors(&weights, &metadata, path.ptr, defaultCpuStream()) != 0) {
            return error.CheckpointLoadFailed;
        }
        return .{ .weights = weights, .metadata = metadata };
    }

    pub fn get(self: Checkpoint, key: [:0]const u8) !Array {
        var arr = mlx_array{ .ctx = null };
        if (mlx_map_string_to_array_get(&arr, self.weights, key.ptr) != 0) {
            return error.KeyNotFound;
        }
        return .{ .handle = arr };
    }
};

test "Array round-trips float32 data through MLX" {
    const data = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const shape = [_]i32{ 2, 2 };
    const arr = Array.fromFloat32(&data, &shape);
    defer arr.free();

    var out: [4]f32 = undefined;
    arr.asFloat32(&out);
    try std.testing.expectEqualSlices(f32, &data, &out);
}

test "Array.matmul produces correct shape/values for a small case" {
    // [[1,2],[3,4]] x [[1,0],[0,1]] (identity) = [[1,2],[3,4]]
    const a_data = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const identity = [_]f32{ 1.0, 0.0, 0.0, 1.0 };
    const shape = [_]i32{ 2, 2 };

    const a = Array.fromFloat32(&a_data, &shape);
    defer a.free();
    const id = Array.fromFloat32(&identity, &shape);
    defer id.free();

    const res = Array.matmul(a, id);
    defer res.free();

    var out: [4]f32 = undefined;
    res.asFloat32(&out);
    try std.testing.expectEqualSlices(f32, &a_data, &out);
}

test "Array.embedding gathers rows by int32 index" {
    // table = [[10,11],[20,21],[30,31],[40,41]] (4 rows, dim 2)
    const table_data = [_]f32{ 10, 11, 20, 21, 30, 31, 40, 41 };
    const table = Array.fromFloat32(&table_data, &[_]i32{ 4, 2 });
    defer table.free();

    const idx_data = [_]i32{ 2, 0 };
    const idx = Array.fromInt32(&idx_data, &[_]i32{2});
    defer idx.free();

    const res = Array.embedding(table, idx);
    defer res.free();

    var out: [4]f32 = undefined;
    res.asFloat32(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 30, 31, 10, 11 }, &out);
}

test "Array.rmsNorm matches hand-computed values" {
    // x = [1,2,3,4], weight = [1,1,1,1], eps = 1e-6.
    // rms = sqrt(mean(x^2) + eps) = sqrt(7.5 + 1e-6) ~= 2.738613
    const x_data = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const w_data = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    const x = Array.fromFloat32(&x_data, &[_]i32{4});
    defer x.free();
    const w = Array.fromFloat32(&w_data, &[_]i32{4});
    defer w.free();

    const res = Array.rmsNorm(x, w, 1e-6);
    defer res.free();

    var out: [4]f32 = undefined;
    res.asFloat32(&out);

    const rms: f32 = std.math.sqrt(7.5 + 1e-6);
    for (x_data, out) |xv, ov| {
        try std.testing.expectApproxEqAbs(xv / rms, ov, 1e-4);
    }
}

test "Array.rope is the identity at offset 0" {
    // At sequence position 0, every RoPE rotation angle is 0*freq = 0,
    // so the output must equal the input exactly, regardless of base.
    const x_data = [_]f32{ 1.0, 2.0 };
    const x = Array.fromFloat32(&x_data, &[_]i32{ 1, 1, 2 }); // (B=1, T=1, D=2)
    defer x.free();

    const res = Array.rope(x, 2, true, 10000.0, 1.0, 0);
    defer res.free();

    var out: [2]f32 = undefined;
    res.asFloat32(&out);
    try std.testing.expectApproxEqAbs(x_data[0], out[0], 1e-5);
    try std.testing.expectApproxEqAbs(x_data[1], out[1], 1e-5);
}

test "Array.attention matches hand-computed causal weighted average" {
    // Q=[[1],[1]], K=[[0],[0]] (scores are 0 for both tokens either way),
    // V=[[5],[9]], shape (B=1, N=1, T=2, D=1), scale=1, causal=true.
    // Token 0 (causal) only attends itself -> output 5.
    // Token 1 attends both with equal score 0 -> softmax([0,0])=[.5,.5]
    // -> output = 0.5*5 + 0.5*9 = 7.
    const q_data = [_]f32{ 1.0, 1.0 };
    const k_data = [_]f32{ 0.0, 0.0 };
    const v_data = [_]f32{ 5.0, 9.0 };
    const dims = [_]i32{ 1, 1, 2, 1 };
    const q = Array.fromFloat32(&q_data, &dims);
    defer q.free();
    const k = Array.fromFloat32(&k_data, &dims);
    defer k.free();
    const v = Array.fromFloat32(&v_data, &dims);
    defer v.free();

    const res = Array.attention(q, k, v, 1.0, true);
    defer res.free();

    var out: [2]f32 = undefined;
    res.asFloat32(&out);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), out[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), out[1], 1e-4);
}

test "Array.softmax matches hand-computed values for [1,2,3]" {
    const data = [_]f32{ 1.0, 2.0, 3.0 };
    const a = Array.fromFloat32(&data, &[_]i32{3});
    defer a.free();

    const res = Array.softmax(a, 0);
    defer res.free();

    var out: [3]f32 = undefined;
    res.asFloat32(&out);
    // exp(1),exp(2),exp(3) = 2.71828, 7.38906, 20.0855; sum = 30.19265
    try std.testing.expectApproxEqAbs(@as(f32, 0.090031), out[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.244728), out[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.665241), out[2], 1e-4);
}

test "Array.silu matches hand-computed sigmoid-gated values" {
    const data = [_]f32{ -1.0, 0.0, 1.0, 2.0 };
    const a = Array.fromFloat32(&data, &[_]i32{4});
    defer a.free();

    const res = a.silu();
    defer res.free();

    var out: [4]f32 = undefined;
    res.asFloat32(&out);
    // silu(x) = x * sigmoid(x)
    try std.testing.expectApproxEqAbs(@as(f32, -0.268941), out[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), out[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.731059), out[2], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1.761594), out[3], 1e-4);
}

test "Array.reshape preserves row-major data under a new shape" {
    const data = [_]f32{ 1, 2, 3, 4, 5, 6 };
    const a = Array.fromFloat32(&data, &[_]i32{ 2, 3 });
    defer a.free();

    const res = a.reshape(&[_]i32{ 3, 2 });
    defer res.free();

    try std.testing.expectEqualSlices(c_int, &[_]c_int{ 3, 2 }, res.shape());
    var out: [6]f32 = undefined;
    res.asFloat32(&out);
    try std.testing.expectEqualSlices(f32, &data, &out);
}

test "Array.slice extracts a sub-range" {
    const data = [_]f32{ 1, 2, 3, 4, 5, 6 };
    const a = Array.fromFloat32(&data, &[_]i32{6});
    defer a.free();

    const res = a.slice(&[_]i32{2}, &[_]i32{5}, null);
    defer res.free();

    var out: [3]f32 = undefined;
    res.asFloat32(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 3, 4, 5 }, &out);
}

test "Array.split cuts an array at section boundaries" {
    const data = [_]f32{ 1, 2, 3, 4, 5, 6 };
    const a = Array.fromFloat32(&data, &[_]i32{6});
    defer a.free();

    const parts = try Array.split(a, std.testing.allocator, &[_]i32{3}, 0);
    defer std.testing.allocator.free(parts);
    defer for (parts) |p| p.free();

    try std.testing.expectEqual(@as(usize, 2), parts.len);
    var out0: [3]f32 = undefined;
    parts[0].asFloat32(&out0);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 1, 2, 3 }, &out0);
    var out1: [3]f32 = undefined;
    parts[1].asFloat32(&out1);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 4, 5, 6 }, &out1);
}

test "Array.transposeAxes permutes to an arbitrary axis order" {
    // a: shape (1,2,3,1) = [[[[0],[1],[2]],[[3],[4],[5]]]] (B=1,L=2,H=3,D=1)
    // transposeAxes([0,2,1,3]) -> shape (1,3,2,1): swap L and H.
    //
    // `transposeAxes` (like numpy/MLX transpose generally) produces a
    // non-contiguous *view* — reading it back via `asFloat32` (raw buffer
    // pointer, ignoring strides) would see the untransposed byte layout.
    // Real callers (see `models/qwen2_mlx.zig`'s `splitHeads`, and the
    // attention-output un-split below) always immediately `reshape` a
    // transpose's result, which — like MLX's own reshape — forces a
    // contiguous copy first; this test exercises that same pattern rather
    // than reading the raw (pre-copy) view directly.
    const data = [_]f32{ 0, 1, 2, 3, 4, 5 };
    const a = Array.fromFloat32(&data, &[_]i32{ 1, 2, 3, 1 });
    defer a.free();

    const transposed = a.transposeAxes(&[_]i32{ 0, 2, 1, 3 });
    defer transposed.free();
    try std.testing.expectEqualSlices(c_int, &[_]c_int{ 1, 3, 2, 1 }, transposed.shape());

    const res = transposed.reshape(&[_]i32{6});
    defer res.free();
    var out: [6]f32 = undefined;
    res.asFloat32(&out);
    // Row-major (1,3,2,1): [ [0,3], [1,4], [2,5] ] flattened.
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0, 3, 1, 4, 2, 5 }, &out);
}

test "Array.concat joins arrays along an axis" {
    const a_data = [_]f32{ 1, 2 };
    const b_data = [_]f32{ 3, 4 };
    const a = Array.fromFloat32(&a_data, &[_]i32{ 1, 2 });
    defer a.free();
    const b = Array.fromFloat32(&b_data, &[_]i32{ 1, 2 });
    defer b.free();

    const res = Array.concat(&[_]Array{ a, b }, 0);
    defer res.free();

    try std.testing.expectEqualSlices(c_int, &[_]c_int{ 2, 2 }, res.shape());
    var out: [4]f32 = undefined;
    res.asFloat32(&out);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 1, 2, 3, 4 }, &out);
}
