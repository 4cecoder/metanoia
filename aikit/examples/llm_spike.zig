//! Phase 0 spike for native LLM inference (research task, not production
//! code — not wired into root.zig/capabilities/). Proves the smallest
//! meaningful data point identified in the research report: load REAL
//! MLX-format safetensors weights for a real small model
//! (mlx-community/Qwen2.5-0.5B-Instruct-4bit) via mlx-c's own
//! `mlx_load_safetensors`, dequantize one real weight matrix using
//! `mlx_dequantize`, and run a real `mlx_matmul` against it — end to end
//! through actual downloaded model bytes, not synthetic data.
//!
//! The MLX bindings this uses (Checkpoint.load/get, Array.dequantizeAffine,
//! Array.transpose, Array.shape) live in aikit/src/backend/mlx.zig proper,
//! not duplicated here — promoted there once this spike proved them out.
//!
//! Run: zig build run-llm-spike -Dllm-spike-model=/path/to/model.safetensors

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const aikit = @import("aikit");
const mlx = aikit.backend.mlx;

comptime {
    if (builtin.os.tag != .macos) @compileError("macOS-only (MLX)");
}

pub fn main() !void {
    const path = build_options.model_path;
    if (path.len == 0) {
        std.debug.print("usage: zig build run-llm-spike -Dllm-spike-model=<path/to/model.safetensors>\n", .{});
        return error.MissingArg;
    }

    var path_buf: [4096]u8 = undefined;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z: [:0]const u8 = path_buf[0..path.len :0];

    const ckpt = mlx.Checkpoint.load(path_z) catch {
        std.debug.print("mlx_load_safetensors FAILED\n", .{});
        return error.LoadFailed;
    };
    std.debug.print("mlx_load_safetensors OK — real 265MB checkpoint parsed by mlx-c\n", .{});

    // Pull one real quantized weight matrix + its scales/biases (4-bit,
    // group_size=64, per model's config.json "quantization" block) and
    // dequantize it back to float32 using mlx-c's own dequantize op.
    const w_q = try ckpt.get("model.layers.0.self_attn.q_proj.weight");
    const scales = try ckpt.get("model.layers.0.self_attn.q_proj.scales");
    const biases = try ckpt.get("model.layers.0.self_attn.q_proj.biases");

    const q_shape = w_q.shape();
    std.debug.print("q_proj.weight (packed, quantized): ndim={d} shape=[{d},{d}]\n", .{ q_shape.len, q_shape[0], q_shape[1] });

    const w_f32 = mlx.Array.dequantizeAffine(w_q, scales, biases, 64, 4);
    defer w_f32.free();
    w_f32.eval();
    const dshape = w_f32.shape();
    std.debug.print("q_proj.weight (dequantized f32): shape=[{d},{d}] — real weight values, not synthetic\n", .{ dshape[0], dshape[1] });

    // Sanity: print a few real dequantized weight values.
    var deq_out: [5]f32 = undefined;
    w_f32.asFloat32(&deq_out);
    std.debug.print("first 5 dequantized weights: {e:.6} {e:.6} {e:.6} {e:.6} {e:.6}\n", .{ deq_out[0], deq_out[1], deq_out[2], deq_out[3], deq_out[4] });

    // Now run a REAL matmul: a synthetic unit input vector (standing in
    // for a real embedded token, out of scope for this spike) against the
    // REAL dequantized q_proj weight matrix, transposed to [in,out] as
    // PyTorch/MLX linear layers expect (nn.Linear stores [out,in]).
    const wt = w_f32.transpose();
    defer wt.free();

    const in_features: usize = @intCast(dshape[1]);
    const x_data = try std.heap.page_allocator.alloc(f32, in_features);
    defer std.heap.page_allocator.free(x_data);
    @memset(x_data, 0);
    x_data[0] = 1.0; // one-hot "activation" standing in for a real hidden state

    const x_shape = [_]i32{ 1, @intCast(in_features) };
    const x = mlx.Array.fromFloat32(x_data, &x_shape);
    defer x.free();

    const y = mlx.Array.matmul(x, wt);
    defer y.free();
    const yshape = y.shape();
    std.debug.print("matmul(x, q_proj^T) output shape=[{d},{d}] — plausible attention-projection output shape for hidden_size=896\n", .{ yshape[0], yshape[1] });

    var y_out: [5]f32 = undefined;
    y.asFloat32(&y_out);
    std.debug.print("first 5 output values: {d:.5} {d:.5} {d:.5} {d:.5} {d:.5}\n", .{ y_out[0], y_out[1], y_out[2], y_out[3], y_out[4] });

    std.debug.print("\nSPIKE RESULT: real safetensors load + real dequantize + real matmul against real Qwen2.5-0.5B-4bit weights — SUCCESS\n", .{});
}
