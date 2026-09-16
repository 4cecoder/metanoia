//! Resolution and validation of the native Qwen3-TTS model payload.
//!
//! This module deliberately has no inference dependency.  It is shared by
//! the model-manager CLI and the native TTS launcher so a bundle can keep its
//! large, volatile GGUF payload outside the stable reader executable.

const std = @import("std");
const builtin = @import("builtin");

pub const talker_filename = "qwen-talker-0.6b-base-Q8_0.gguf";
pub const codec_filename = "qwen-tokenizer-12hz-Q8_0.gguf";

pub const Artifact = struct {
    role: []const u8,
    filename: []const u8,
};

pub const artifacts = [_]Artifact{
    .{ .role = "talker", .filename = talker_filename },
    .{ .role = "codec", .filename = codec_filename },
};

pub const Paths = struct {
    directory: []const u8,
    talker: []const u8,
    codec: []const u8,
};

pub const ArtifactStatus = struct {
    artifact: Artifact,
    path: []const u8,
    present: bool,
    bytes: u64,
    sha256: [64]u8,
};

pub const Status = struct {
    directory: []const u8,
    talker: ArtifactStatus,
    codec: ArtifactStatus,

    pub fn ready(self: Status) bool {
        return self.talker.present and self.codec.present;
    }
};

fn envValue(allocator: std.mem.Allocator, name: []const u8) !?[]const u8 {
    const name_z = try allocator.dupeSentinel(u8, name, 0);
    defer allocator.free(name_z);
    const value = std.c.getenv(name_z.ptr) orelse return null;
    return try allocator.dupe(u8, std.mem.span(value));
}

fn join(allocator: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    return std.fs.path.join(allocator, parts);
}

/// Resolve the managed model cache. Explicit paths win, then the environment
/// override, then the platform's normal per-user application-data directory.
pub fn resolveModelDirectory(allocator: std.mem.Allocator, explicit: ?[]const u8) ![]const u8 {
    if (explicit) |path| return allocator.dupe(u8, path);
    if (try envValue(allocator, "METANOIA_MODEL_DIR")) |path| return path;

    switch (builtin.os.tag) {
        .macos => {
            const home = std.c.getenv("HOME") orelse return allocator.dupe(u8, "models");
            return join(allocator, &.{ std.mem.span(home), "Library", "Application Support", "Metanoia", "models", "qwen3" });
        },
        .windows => {
            const base = std.c.getenv("LOCALAPPDATA") orelse std.c.getenv("USERPROFILE") orelse return allocator.dupe(u8, "models");
            return join(allocator, &.{ std.mem.span(base), "Metanoia", "models", "qwen3" });
        },
        else => {
            if (std.c.getenv("XDG_DATA_HOME")) |xdg| {
                return join(allocator, &.{ std.mem.span(xdg), "metanoia", "models", "qwen3" });
            }
            if (std.c.getenv("HOME")) |home| {
                return join(allocator, &.{ std.mem.span(home), ".local", "share", "metanoia", "models", "qwen3" });
            }
            return allocator.dupe(u8, "models");
        },
    }
}

/// Resolve the checkout/bundle-side source directory used by `install`.
pub fn resolveSourceDirectory(allocator: std.mem.Allocator, explicit: ?[]const u8) ![]const u8 {
    if (explicit) |path| return allocator.dupe(u8, path);
    if (try envValue(allocator, "METANOIA_QWEN_SOURCE_DIR")) |path| return path;
    return allocator.dupe(u8, "vendor/qwentts.cpp/models");
}

fn openFile(path: []const u8, io: std.Io) !std.Io.File {
    if (std.fs.path.isAbsolute(path)) return std.Io.Dir.openFileAbsolute(io, path, .{ .allow_directory = false });
    return std.Io.Dir.cwd().openFile(io, path, .{ .allow_directory = false });
}

fn stat(path: []const u8, io: std.Io) !std.Io.File.Stat {
    return std.Io.Dir.cwd().statFile(io, path, .{});
}

fn sha256File(path: []const u8, io: std.Io) ![64]u8 {
    var file = try openFile(path, io);
    defer file.close(io);

    var read_buffer: [128 * 1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    while (true) {
        const n = reader.interface.readSliceShort(&read_buffer) catch |err| return err;
        if (n == 0) break;
        hasher.update(read_buffer[0..n]);
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    var hex: [64]u8 = undefined;
    const digits = "0123456789abcdef";
    for (digest, 0..) |byte, i| {
        hex[i * 2] = digits[byte >> 4];
        hex[i * 2 + 1] = digits[byte & 0x0f];
    }
    return hex;
}

pub fn inspectArtifact(io: std.Io, allocator: std.mem.Allocator, directory: []const u8, artifact: Artifact) !ArtifactStatus {
    const path = try join(allocator, &.{ directory, artifact.filename });
    errdefer allocator.free(path);
    const file_stat = stat(path, io) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return .{
            .artifact = artifact,
            .path = path,
            .present = false,
            .bytes = 0,
            .sha256 = @splat('0'),
        },
        else => return err,
    };

    if (file_stat.kind != .file or file_stat.size == 0) {
        return .{
            .artifact = artifact,
            .path = path,
            .present = false,
            .bytes = file_stat.size,
            .sha256 = @splat('0'),
        };
    }

    const digest = try sha256File(path, io);
    return .{
        .artifact = artifact,
        .path = path,
        .present = true,
        .bytes = file_stat.size,
        .sha256 = digest,
    };
}

pub fn inspect(io: std.Io, allocator: std.mem.Allocator, directory: []const u8) !Status {
    const talker = try inspectArtifact(io, allocator, directory, artifacts[0]);
    errdefer allocator.free(talker.path);
    const codec = try inspectArtifact(io, allocator, directory, artifacts[1]);
    return .{ .directory = directory, .talker = talker, .codec = codec };
}

pub fn modelPaths(allocator: std.mem.Allocator, directory: []const u8) !Paths {
    return .{
        .directory = try allocator.dupe(u8, directory),
        .talker = try join(allocator, &.{ directory, talker_filename }),
        .codec = try join(allocator, &.{ directory, codec_filename }),
    };
}

pub fn install(io: std.Io, allocator: std.mem.Allocator, source_directory: []const u8, destination_directory: []const u8) !Status {
    try std.Io.Dir.cwd().createDirPath(io, destination_directory);
    for (artifacts) |artifact| {
        const source = try join(allocator, &.{ source_directory, artifact.filename });
        defer allocator.free(source);
        const destination = try join(allocator, &.{ destination_directory, artifact.filename });
        defer allocator.free(destination);
        // updateFile uses an atomic temporary file and preserves source
        // timestamps, avoiding a partially copied multi-hundred-MB GGUF if a
        // process is interrupted.
        _ = try std.Io.Dir.cwd().updateFile(io, source, std.Io.Dir.cwd(), destination, .{});
    }
    return inspect(io, allocator, destination_directory);
}

pub fn formatDigest(digest: *const [64]u8) []const u8 {
    return digest.*[0..];
}

test "required Qwen filenames are stable" {
    try std.testing.expectEqualStrings("qwen-talker-0.6b-base-Q8_0.gguf", talker_filename);
    try std.testing.expectEqualStrings("qwen-tokenizer-12hz-Q8_0.gguf", codec_filename);
    try std.testing.expectEqual(@as(usize, 2), artifacts.len);
}

test "model paths use the managed directory" {
    const paths = try modelPaths(std.testing.allocator, "/tmp/metanoia-models");
    defer std.testing.allocator.free(paths.directory);
    defer std.testing.allocator.free(paths.talker);
    defer std.testing.allocator.free(paths.codec);
    try std.testing.expectEqualStrings("/tmp/metanoia-models/qwen-talker-0.6b-base-Q8_0.gguf", paths.talker);
    try std.testing.expectEqualStrings("/tmp/metanoia-models/qwen-tokenizer-12hz-Q8_0.gguf", paths.codec);
}

test "zero digest is visibly incomplete" {
    const digest: [64]u8 = @splat('0');
    try std.testing.expectEqual(@as(usize, 64), formatDigest(&digest).len);
    try std.testing.expectEqualStrings("00000000", formatDigest(&digest)[0..8]);
}
