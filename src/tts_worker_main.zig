//! Long-lived native Qwen3-TTS worker.
//!
//! The reader launches this process for native mode.  The worker loads the
//! talker and codec once, then accepts newline-delimited JSON requests over
//! stdin.  Keeping the model resident is the important performance property:
//! a 33-verse chapter must not reload a ~1 GB checkpoint for every verse.

const std = @import("std");
const aikit = @import("aikit");
const models = @import("qwen_models.zig");
const protocol = @import("tts_worker_protocol.zig");

const WorkerArgs = struct {
    model: ?[]const u8 = null,
    codec: ?[]const u8 = null,
    model_dir: ?[]const u8 = null,
    once: bool = false,
};

fn usage() void {
    std.debug.print(
        "Usage: metanoia-tts --model PATH --codec PATH [--stdio|--once]\n" ++
            "       metanoia-tts --model-dir PATH [--stdio|--once]\n" ++
            "\n" ++
            "Reads one JSON request per line and writes one JSON response per line.\n",
        .{},
    );
}

fn parseArgs(args: []const []const u8, allocator: std.mem.Allocator) !WorkerArgs {
    var result = WorkerArgs{};
    var stdio = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--stdio")) {
            stdio = true;
        } else if (std.mem.eql(u8, arg, "--once")) {
            result.once = true;
            stdio = true;
        } else if (std.mem.eql(u8, arg, "--model") or std.mem.eql(u8, arg, "--codec") or std.mem.eql(u8, arg, "--model-dir")) {
            if (i + 1 >= args.len) return error.InvalidArguments;
            i += 1;
            const value = try allocator.dupe(u8, args[i]);
            if (std.mem.eql(u8, arg, "--model")) result.model = value;
            if (std.mem.eql(u8, arg, "--codec")) result.codec = value;
            if (std.mem.eql(u8, arg, "--model-dir")) result.model_dir = value;
        } else {
            return error.InvalidArguments;
        }
    }

    if (!stdio or (result.model_dir == null and (result.model == null or result.codec == null))) {
        return error.InvalidArguments;
    }
    if (result.model_dir != null and (result.model != null or result.codec != null)) {
        return error.InvalidArguments;
    }
    return result;
}

fn parentPath(path: []const u8) ?[]const u8 {
    return std.fs.path.dirname(path);
}

fn writeWav(io: std.Io, path: []const u8, audio: aikit.tts.Audio) !void {
    if (parentPath(path)) |parent| {
        if (parent.len > 0) try std.Io.Dir.cwd().createDirPath(io, parent);
    }

    const data_size: u32 = @intCast(audio.samples.len * 2);
    const channels: u16 = audio.channels;
    var header: [44]u8 = undefined;
    @memcpy(header[0..4], "RIFF");
    std.mem.writeInt(u32, header[4..8], 36 + data_size, .little);
    @memcpy(header[8..12], "WAVE");
    @memcpy(header[12..16], "fmt ");
    std.mem.writeInt(u32, header[16..20], 16, .little);
    std.mem.writeInt(u16, header[20..22], 1, .little);
    std.mem.writeInt(u16, header[22..24], channels, .little);
    std.mem.writeInt(u32, header[24..28], audio.sample_rate, .little);
    std.mem.writeInt(u32, header[28..32], audio.sample_rate * @as(u32, channels) * 2, .little);
    std.mem.writeInt(u16, header[32..34], channels * 2, .little);
    std.mem.writeInt(u16, header[34..36], 16, .little);
    @memcpy(header[36..40], "data");
    std.mem.writeInt(u32, header[40..44], data_size, .little);

    const file = if (std.fs.path.isAbsolute(path))
        try std.Io.Dir.createFileAbsolute(io, path, .{})
    else
        try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    var write_buffer: [64 * 1024]u8 = undefined;
    var writer = file.writer(io, &write_buffer);
    try writer.interface.writeAll(&header);

    var sample_bytes: [4096]u8 = undefined;
    var index: usize = 0;
    while (index < audio.samples.len) {
        var written: usize = 0;
        while (index < audio.samples.len and written + 2 <= sample_bytes.len) : (index += 1) {
            std.mem.writeInt(i16, sample_bytes[written..][0..2], audio.samples[index], .little);
            written += 2;
        }
        try writer.interface.writeAll(sample_bytes[0..written]);
    }
    try writer.interface.flush();
}

fn errorText(allocator: std.mem.Allocator, err: anyerror) []const u8 {
    return std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)}) catch "worker error";
}

fn handleRequest(
    io: std.Io,
    allocator: std.mem.Allocator,
    model: *aikit.models.qwen3_tts.Qwen3TTS,
    request: protocol.Request,
) protocol.Response {
    const options: aikit.tts.SynthesizeOptions = .{
        .voice = request.voice,
        .speed = request.speed,
        .seed = request.seed,
        .reference_audio_path = request.reference_audio,
        .reference_text = request.reference_text,
    };

    const audio = model.synthesizer().synthesize(io, allocator, request.text, options) catch |err| {
        std.debug.print("[metanoia-tts] synthesis failed for {s}: {s}\n", .{ request.id, @errorName(err) });
        return .{ .id = request.id, .ok = false, .error_message = errorText(allocator, err) };
    };
    defer audio.deinit(allocator);

    writeWav(io, request.output, audio) catch |err| {
        std.debug.print("[metanoia-tts] output failed for {s}: {s}\n", .{ request.id, @errorName(err) });
        return .{ .id = request.id, .ok = false, .error_message = errorText(allocator, err) };
    };

    return .{
        .id = request.id,
        .ok = true,
        .output = request.output,
        .sample_rate = audio.sample_rate,
    };
}

fn serve(
    io: std.Io,
    allocator: std.mem.Allocator,
    model: *aikit.models.qwen3_tts.Qwen3TTS,
    once: bool,
) !void {
    var input_buffer: [128 * 1024]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &input_buffer);
    var output_buffer: [16 * 1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &output_buffer);

    while (true) {
        const line = (try protocol.readLine(&reader.interface)) orelse break;
        if (line.len == 0) continue;

        const request = protocol.parseRequest(allocator, line) catch |err| {
            try protocol.writeResponse(&writer.interface, .{
                .id = "",
                .ok = false,
                .error_message = errorText(allocator, err),
            });
            if (once) break;
            continue;
        };
        std.debug.print("[metanoia-tts] request {s} begin\n", .{request.id});
        const response = handleRequest(io, allocator, model, request);
        std.debug.print("[metanoia-tts] request {s} end ok={}\n", .{ request.id, response.ok });
        try protocol.writeResponse(&writer.interface, response);
        if (once) break;
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const worker_args = parseArgs(args, allocator) catch {
        usage();
        return error.InvalidArguments;
    };

    var threaded_io = std.Io.Threaded.init(allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    const model_paths = if (worker_args.model_dir) |directory|
        try models.modelPaths(allocator, directory)
    else
        models.Paths{
            .directory = "",
            .talker = worker_args.model.?,
            .codec = worker_args.codec.?,
        };

    std.debug.print("[metanoia-tts] loading talker={s} codec={s}\n", .{ model_paths.talker, model_paths.codec });
    var model = try aikit.models.qwen3_tts.Qwen3TTS.init(model_paths.talker, model_paths.codec);
    defer model.synthesizer().deinit();
    std.debug.print("[metanoia-tts] model loaded; ready\n", .{});

    try serve(io, allocator, &model, worker_args.once);
}
