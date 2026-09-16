//! CLI for the external Qwen3-TTS model cache.
//!
//! Examples:
//!   metanoia-models status
//!   metanoia-models status --json
//!   metanoia-models verify --dir /path/to/qwen3
//!   metanoia-models install --source vendor/qwentts.cpp/models

const std = @import("std");
const models = @import("qwen_models.zig");

fn usage() void {
    std.debug.print(
        "Usage: metanoia-models <status|verify|install> [options]\n" ++
            "\n" ++
            "Options:\n" ++
            "  --dir PATH              managed model directory\n" ++
            "  --source PATH           source directory for install\n" ++
            "  --dest PATH             destination directory for install\n" ++
            "  --json                  status as machine-readable JSON\n",
        .{},
    );
}

const Options = struct {
    directory: ?[]const u8 = null,
    source: ?[]const u8 = null,
    destination: ?[]const u8 = null,
    json: bool = false,
};

fn parseOptions(args: []const []const u8, allocator: std.mem.Allocator) !Options {
    var options = Options{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            options.json = true;
        } else if (std.mem.eql(u8, arg, "--dir") or std.mem.eql(u8, arg, "--source") or std.mem.eql(u8, arg, "--dest")) {
            if (i + 1 >= args.len) return error.InvalidArguments;
            i += 1;
            const value = try allocator.dupe(u8, args[i]);
            if (std.mem.eql(u8, arg, "--dir")) options.directory = value;
            if (std.mem.eql(u8, arg, "--source")) options.source = value;
            if (std.mem.eql(u8, arg, "--dest")) options.destination = value;
        } else {
            return error.InvalidArguments;
        }
    }
    return options;
}

fn writeJson(io: std.Io, value: anytype) !void {
    var buffer: [16 * 1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    var stringify: std.json.Stringify = .{ .writer = &writer.interface };
    try stringify.write(value);
    try writer.interface.writeAll("\n");
    try writer.interface.flush();
}

const JsonArtifact = struct {
    role: []const u8,
    filename: []const u8,
    path: []const u8,
    present: bool,
    bytes: u64,
    sha256: []const u8,
};

const JsonStatus = struct {
    directory: []const u8,
    ready: bool,
    artifacts: [2]JsonArtifact,
};

fn jsonStatus(status: *const models.Status) JsonStatus {
    return .{
        .directory = status.directory,
        .ready = status.ready(),
        .artifacts = .{
            .{
                .role = status.talker.artifact.role,
                .filename = status.talker.artifact.filename,
                .path = status.talker.path,
                .present = status.talker.present,
                .bytes = status.talker.bytes,
                .sha256 = &status.talker.sha256,
            },
            .{
                .role = status.codec.artifact.role,
                .filename = status.codec.artifact.filename,
                .path = status.codec.path,
                .present = status.codec.present,
                .bytes = status.codec.bytes,
                .sha256 = &status.codec.sha256,
            },
        },
    };
}

fn printHuman(status: models.Status) void {
    std.debug.print("Qwen model directory: {s}\n", .{status.directory});
    for (&[_]models.ArtifactStatus{ status.talker, status.codec }) |item| {
        std.debug.print(
            "  {s}: {s} ({d} bytes)\n    {s}\n    sha256={s}\n",
            .{
                item.artifact.role,
                if (item.present) "ready" else "missing/invalid",
                item.bytes,
                item.path,
                &item.sha256,
            },
        );
    }
    std.debug.print("Ready: {}\n", .{status.ready()});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) {
        usage();
        return error.InvalidArguments;
    }

    const command = args[1];
    const options = parseOptions(args[2..], allocator) catch {
        usage();
        return error.InvalidArguments;
    };

    var threaded_io = std.Io.Threaded.init(allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    if (std.mem.eql(u8, command, "status") or std.mem.eql(u8, command, "verify")) {
        const directory = try models.resolveModelDirectory(allocator, options.directory);
        const status = try models.inspect(io, allocator, directory);
        if (options.json) {
            try writeJson(io, jsonStatus(&status));
        } else {
            printHuman(status);
        }
        if (std.mem.eql(u8, command, "verify") and !status.ready()) return error.IncompleteModels;
        return;
    }

    if (std.mem.eql(u8, command, "install")) {
        const source = try models.resolveSourceDirectory(allocator, options.source);
        const destination = try models.resolveModelDirectory(allocator, options.destination orelse options.directory);
        const status = try models.install(io, allocator, source, destination);
        if (options.json) {
            try writeJson(io, jsonStatus(&status));
        } else {
            printHuman(status);
        }
        if (!status.ready()) return error.IncompleteModels;
        return;
    }

    usage();
    return error.InvalidArguments;
}
