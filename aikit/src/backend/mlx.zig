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
pub extern "c" fn mlx_tanh(res: *mlx_array, a: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_sin(res: *mlx_array, a: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_cos(res: *mlx_array, a: mlx_array, s: mlx_stream) callconv(.c) c_int;
pub extern "c" fn mlx_eval(outputs: mlx_vector_array) callconv(.c) c_int;
pub extern "c" fn mlx_random_seed(seed: u64) callconv(.c) c_int;
pub extern "c" fn mlx_device_new_type(device_type: c_int, index: c_int) callconv(.c) mlx_device;
pub extern "c" fn mlx_default_gpu_stream_new() callconv(.c) mlx_stream;
pub extern "c" fn mlx_default_cpu_stream_new() callconv(.c) mlx_stream;

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
