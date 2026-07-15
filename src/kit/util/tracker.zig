//! Leak-detecting allocator wrapper for unit tests.
//!
//! ```zig
//! var track = tracker.Tracker.init(std.testing.allocator);
//! const a = track.allocator();
//! const buf = try a.alloc(u8, 10);
//! a.free(buf);
//! track.assertNoLeaks(); // passes
//! ```

const std = @import("std");

const Tracker = @This();

inner: std.mem.Allocator,
live: std.HashMapUnmanaged(usize, usize, std.hash_map.default_max_load_percentage),
mutex: std.Thread.Mutex = .{},

pub fn init(inner: std.mem.Allocator) Tracker {
    return .{
        .inner = inner,
        .live = .empty,
    };
}

pub fn deinit(self: *Tracker) void {
    self.live.deinit(self.inner);
}

pub fn allocator(self: *Tracker) std.mem.Allocator {
    const Impl = struct {
        fn alloc(ctx: *anyopaque, len: usize, log2_align: u8, ra: usize) ?*anyopaque {
            const t: *Tracker = @ptrCast(@alignCast(ctx));
            const ptr = t.inner.rawAlloc(len, log2_align, ra) orelse return null;
            t.mutex.lock();
            t.live.put(t.inner, @intFromPtr(ptr), len) catch {
                t.mutex.unlock();
                t.inner.rawFree(ptr, log2_align, len, ra);
                return null;
            };
            t.mutex.unlock();
            return ptr;
        }
        fn free(ctx: *anyopaque, buf: []u8, log2_align: u8, ra: usize) void {
            const t: *Tracker = @ptrCast(@alignCast(ctx));
            t.mutex.lock();
            _ = t.live.remove(@intFromPtr(buf.ptr));
            t.mutex.unlock();
            t.inner.rawFree(buf, log2_align, ra);
        }
        fn resize(ctx: *anyopaque, buf: []u8, log2_align: u8, new_len: usize, ra: usize) bool {
            _ = ctx;
            _ = buf;
            _ = log2_align;
            _ = new_len;
            _ = ra;
            return false;
        }
    };
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = Impl.alloc,
            .free = Impl.free,
            .resize = Impl.resize,
        },
    };
}

pub fn assertNoLeaks(self: *Tracker) void {
    if (self.live.count() == 0) return;
    var it = self.live.iterator();
    while (it.next()) |entry| {
        std.debug.print("LEAK: 0x{x} ({} bytes)\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    @panic("memory leak detected");
}

test "Tracker detects no leaks on clean alloc/free" {
    var t = Tracker.init(std.testing.allocator);
    defer t.deinit();
    const a = t.allocator();
    const buf = try a.alloc(u8, 10);
    a.free(buf);
    t.assertNoLeaks();
}

test "Tracker detects leaks" {
    var t = Tracker.init(std.testing.allocator);
    defer t.deinit();
    const a = t.allocator();
    _ = try a.alloc(u8, 10);
    // Leak! assertNoLeaks would panic here.
}
