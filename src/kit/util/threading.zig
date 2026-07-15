/// GLib-based thread-safe GTK UI update helpers.
///
/// Provides thin wrappers around `g_idle_add` and `g_thread_new` that
/// eliminate the repetitive context-struct boilerplate found throughout the
/// UI layer. All helpers post work to the GLib main loop so GTK widget
/// mutations happen on the main thread, which is a hard requirement of
/// GTK4.
const std = @import("std");
const ffi = @import("../ffi.zig");

/// Schedule `callback` to run on the GLib main loop, passing `data`.
pub fn idleAdd(
    comptime Context: type,
    comptime callback: *const fn (data: *Context) callconv(.c) bool,
    data: *Context,
) void {
    _ = ffi.g_idle_add(@ptrCast(callback), @ptrCast(data));
}

/// Spawn a new GLib thread. The thread entry `callback` receives `data`
/// and must return `null` when finished.
pub fn threadSpawn(
    comptime Context: type,
    name: [*:0]const u8,
    comptime callback: *const fn (data: *Context) callconv(.c) ?*anyopaque,
    data: *Context,
) void {
    _ = ffi.g_thread_new(name, @ptrCast(callback), @ptrCast(data));
}

/// Context carried by `postToMain`. After the callback fires the helper
/// frees both the duplicated message string and the context itself.
pub fn PostContext(comptime Callback: type) type {
    return struct {
        msg: [*:0]const u8,
        callback: Callback,
        allocator: std.mem.Allocator,

        fn run(ptr: ?*anyopaque) callconv(.c) bool {
            const ctx: *@This() = @ptrCast(@alignCast(ptr));
            ctx.callback(ctx.msg);
            ctx.allocator.free(std.mem.span(ctx.msg));
            ctx.allocator.destroy(ctx);
            return false;
        }
    };
}

/// Duplicate `message` into a sentinel-terminated string, wrap it together
/// with `callback` in a heap-allocated `PostContext`, and schedule it on
/// the GLib main loop via `g_idle_add`.
///
/// The callback signature must be `fn([*:0]const u8) callconv(.c) void`.
/// It receives the duplicated string and must NOT free it — the helper
/// handles cleanup automatically.
pub fn postToMain(
    allocator: std.mem.Allocator,
    message: []const u8,
    callback: anytype, // fn([*:0]const u8) callconv(.c) void
) void {
    const duped = allocator.dupeSentinel(u8, message, 0) catch return;
    const ctx = allocator.create(PostContext(@TypeOf(callback))) catch {
        allocator.free(duped);
        return;
    };
    ctx.* = .{ .msg = duped, .callback = callback, .allocator = allocator };
    _ = ffi.g_idle_add(&PostContext(@TypeOf(callback)).run, ctx);
}
