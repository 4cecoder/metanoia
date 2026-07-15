//! Type-safe GTK signal connection with compile-time destroy callback validation.
//!
//! GTK's `GClosureNotify` has the signature `fn (gpointer, GClosure*)`.
//! Passing a 1-parameter function (as was done before) causes silent memory
//! corruption — the extraneous argument is pushed/popped incorrectly by the
//! C ABI. This wrapper catches mismatches at **compile time**.
//!
//! Usage:
//! ```zig
//! const d = struct {
//!     fn onClick(_: ?*ffi.GtkButton, data: ffi.gpointer) callconv(.c) void { _ = data; }
//!     fn destroy(data: ffi.gpointer, _: ?*anyopaque) callconv(.c) void {
//!         std.heap.page_allocator.destroy(@as(*Context, @ptrCast(@alignCast(data))));
//!     }
//! };
//! signal.Signal.connect(obj, "clicked", @ptrCast(&d.onClick), ctx, d.destroy);
//! ```

const std = @import("std");
const ffi = @import("ffi.zig");

/// GTK's GClosureNotify: `void (*)(gpointer data, GClosure *closure)`.
/// **MUST have exactly 2 parameters.** The compiler enforces this.
pub const DestroyNotify = *const fn (data: ffi.gpointer, closure: ?*anyopaque) callconv(.c) void;

pub const Signal = struct {
    /// Connect a signal handler. `handler` is a raw C function pointer
    /// (cast with `@ptrCast(&fn)`). `destroy`, if non-null, is validated
    /// at compile time to match the 2-parameter `DestroyNotify` signature.
    pub fn connect(
        instance: ffi.gpointer,
        signal_name: [*:0]const u8,
        handler: ?*const anyopaque,
        context: ffi.gpointer,
        destroy: ?DestroyNotify,
    ) u64 {
        return connectFlags(instance, signal_name, handler, context, destroy, 0);
    }

    /// Like `connect` but with explicit connect flags (e.g. `G_CONNECT_AFTER`).
    pub fn connectFlags(
        instance: ffi.gpointer,
        signal_name: [*:0]const u8,
        handler: ?*const anyopaque,
        context: ffi.gpointer,
        destroy: ?DestroyNotify,
        flags: i32,
    ) u64 {
        return ffi.g_signal_connect_data(instance, signal_name, handler, context, @ptrCast(destroy), flags);
    }
};

test "DestroyNotify validates signature at compile time" {
    const T = struct {
        fn good(_: ffi.gpointer, _: ?*anyopaque) callconv(.c) void {}
    };
    const d: DestroyNotify = T.good;
    _ = d;
}
