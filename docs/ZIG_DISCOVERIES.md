# Zig Bespoke Discoveries — Metanoia Project

First-hand findings from building a GTK4 desktop app in Zig nightly.

## Table of Contents

- [Zig Versioning](#zig-versioning)
  - [Nightly API churn](#nightly-api-churn)
  - [Compatibility check trick](#compatibility-check-trick)
  - [Survival tips](#survival-tips)
- [Memory Management](#memory-management)
  - [DebugAllocator false positives on exit](#debugallocator-false-positives-on-exit)
  - [GTK destroy callback signature](#gtk-destroy-callback-signature)
  - [Allocator wrapping pattern](#allocator-wrapping-pattern)
  - [Manual memory rules for GTK widgets](#manual-memory-rules-for-gtk-widgets)
- [GTK4 + Zig FFI](#gtk4--zig-ffi)
  - [Signal handler signatures must match exactly](#signal-handler-signatures-must-match-exactly)
  - [G_CONNECT_AFTER for safe self-freeing](#g_connect_after-for-safe-self-freeing)
  - [Widget type casting](#widget-type-casting)
  - [Thread handles must be stored and joined](#thread-handles-must-be-stored-and-joined)
- [Build System](#build-system)
  - [Module imports vs relative imports](#module-imports-vs-relative-imports)
  - [Linking system libraries](#linking-system-libraries)
  - [Test configuration](#test-configuration)
- [IO Engine (`std.Io`)](#io-engine-stdio)
- [Thread Safety Patterns](#thread-safety-patterns)
  - [Atomic flags for stop signaling](#atomic-flags-for-stop-signaling)
  - [Mutex pattern with IO](#mutex-pattern-with-io)
  - [std.Thread.Mutex disappeared](#stdthreadmutex-disappeared-0170-dev1422e863bf3be)
  - [std.json.parseFromSlice for a canonical data file](#stdjsonparsefromslice-for-a-canonical-data-file)
  - [Thread join sequence](#thread-join-sequence)

---

## Zig Versioning

### Nightly API churn

This project tracks Zig **master nightly**. As of 2026-07-19 that's `0.17.0-dev.1422+e863bf3be` (up from `0.17.0-dev.1398+cb5635714` — `std.Thread.Mutex` disappeared between those two builds, see "Thread Safety Patterns" below). Zig nightly breaks APIs weekly, so pinning the exact version and re-verifying after every upgrade is essential — don't assume a section of this doc still matches current `HEAD` without checking.

**Key observations:**

- `std.ArrayListUnmanaged(T){}` — requires `.empty` or explicit field init in 0.17
- `std.mem.Allocator` vtable changed — `rawResize` signature differs between versions
- `@memcpy` now panics on overlapping regions (0.17+) — use `@memmove` for self-copy
- Module system: `b.addModule()` exposes a module to consumers, while `b.createModule()` keeps it private
- `exe.subsystem` flag enables Windows GUI apps
- `build.zig` uses lazy `b.path()` instead of the `.path` field in recent nightly

### Compatibility check trick

```zig
// Always check the Zig version at the top of tricky files
comptime {
    const current = @import("builtin").zig_version;
    if (current.major == 0 and current.minor < 17) {
        @compileError("requires Zig 0.17+");
    }
}
```

### Survival tips

- Pin your Zig binary — don't run `brew upgrade zig` mid-project.
- Save the exact version string from `zig version`.
- Use the `comptime` check above to catch version mismatches early.

---

## Memory Management

### DebugAllocator false positives on exit

`std.heap.DebugAllocator` reports leaks when the process exits before background threads finish their cleanup. This is **not** a real leak — it is a timing false positive.

```zig
// main() pattern that triggers false positives:
var gpa = std.heap.DebugAllocator(.{}).init;
defer _ = gpa_state.deinit(); // <-- reports leaks from still-running threads
```

**Fixes that worked:**

- Join all threads before exit (`g_thread_join`) — prevents thread-race false leaks
- Make background work synchronous (removed async PipeGen sub-threads)
- Changed `g_thread_new` to store handles and join in `stop()`

### GTK destroy callback signature

**The #1 memory corruption bug in this project.**

GTK's `GClosureNotify` takes **two parameters**: `(gpointer data, GClosure *closure)`. But the Zig FFI declared it as `?*const anyopaque`. A one-parameter function compiles silently via `@ptrCast` and corrupts the stack at runtime because the C ABI reads a second argument off the stack.

**Fix:** Create a `DestroyNotify` type alias and validate it at compile time:

```zig
pub const DestroyNotify = *const fn (data: gpointer, closure: ?*anyopaque) callconv(.c) void;
```

Now `destroy: ?DestroyNotify` rejects one-parameter functions at compile time.

> **See also:** [`SIGNAL_SAFETY.md`](./SIGNAL_SAFETY.md) — the project's type-safe signal layer wraps this `DestroyNotify` into a zero-cost compile-time guard with the `Signal.connect` API.

### Allocator wrapping pattern

To catch leaks in unit tests, wrap any allocator with a tracker:

```zig
var tracker = AllocTracker.init(std.testing.allocator);
const alloc = tracker.allocator();
// ... do work ...
tracker.assertNoLeaks();
```

**Key insight:** the wrapper must intercept `rawAlloc`/`rawFree` at the vtable level (not just `alloc`/`free`) to catch **all** allocation paths, including `create`, `dupe`, etc.

> **See also:** [`KIT.md`](./KIT.md) — the `src/kit/util/tracker.zig` module implements this pattern as a reusable component.

### Manual memory rules for GTK widgets

GTK owns its widget memory. Zig owns its context structs. The boundary:

| Owned by GTK | Owned by Zig |
|---|---|
| `GtkWidget`, `GtkWindow`, etc. | Signal handler context structs |
| Strings passed to `gtk_label_set_text` (copied) | Strings passed as `user_data` |
| Resources allocated by GTK internally | Allocations made with Zig allocators |

**Pattern for context cleanup:**

```zig
// Allocate context
const ctx = allocator.create(MyContext) catch return;
// GTK calls destroy when signal is disconnected or widget destroyed
_ = g_signal_connect_data(widget, "clicked", @ptrCast(&handler), ctx, @ptrCast(&destroyContext), 0);
// destroyContext must free ctx — GTK never frees Zig allocations
```

> **See also:** [`KIT.md`](./KIT.md) documents the project's component callback pattern, which encapsulates this memory boundary cleanly.

---

## GTK4 + Zig FFI

### Signal handler signatures must match exactly

Every GTK signal has a specific handler signature. Passing the wrong one corrupts the stack at runtime.

| Signal | Handler signature |
|---|---|
| `"clicked"` | `fn (?*GtkButton, gpointer) callconv(.c) void` |
| `"activate"` (entry) | `fn (?*anyopaque, gpointer) callconv(.c) void` |
| `"search-changed"` | `fn (?*anyopaque, gpointer) callconv(.c) void` |
| `"key-pressed"` | `fn (?*anyopaque, u32, u32, u32, gpointer) callconv(.c) bool` |
| `"close-request"` | `fn (?*anyopaque, gpointer) callconv(.c) bool` |
| `"notify::*"` | `fn (?*anyopaque, ?*anyopaque, gpointer) callconv(.c) void` |
| `"destroy"` | `fn (?*anyopaque, gpointer) callconv(.c) void` |

**Wrong signature = stack corruption.** Always double-check against the GTK4 docs.

> **See also:** [`SIGNAL_SAFETY.md`](./SIGNAL_SAFETY.md) provides a compile-time checked layer for signal connections. [`KIT.md`](./KIT.md) documents the `kit.signal.Signal.connect` wrapper that enforces correct destroy-callback signatures.

### G_CONNECT_AFTER for safe self-freeing

When a component needs to free itself on window close, connect to `"destroy"` with the `G_CONNECT_AFTER` flag (`1`):

```zig
_ = Signal.connectFlags(window, "destroy", @ptrCast(&destroySelf), self, null, 1);
```

This ensures your handler runs **after** GTK's internal destroy processing. The component's window pointer becomes stale, but `self.allocator` and `self.deinit()` remain safe to call.

> **See also:** [`KIT.md`](./KIT.md) demonstrates this pattern in its `Signal.connectFlags` usage examples.

### Widget type casting

GTK4 uses GObject inheritance. Cast between widget types with `@ptrCast`:

```zig
const window: ?*GtkWindow = @ptrCast(gtk_window_new());  // GtkWidget → GtkWindow
const widget: ?*GtkWidget = @ptrCast(window);              // GtkWindow → GtkWidget
```

### Thread handles must be stored and joined

`g_thread_new` returns a thread handle that **must** be stored and joined, or the thread leaks:

```zig
// WRONG — thread leaks, cannot join:
_ = gtk.g_thread_new("name", &func, data);

// RIGHT — store handle:
self.thread_handle = gtk.g_thread_new("name", &func, data);
// Later:
_ = gtk.g_thread_join(self.thread_handle);
```

---

## Build System

### Module imports vs relative imports

Zig supports both import styles. The choice depends on whether you are inside or outside a module:

```zig
// Module import — requires .imports in build.zig:
const kit = @import("kit");

// Relative import — always works, resolved from file location:
const ffi = @import("../ffi.zig");
```

**Rule of thumb:** when creating a reusable library (like `src/kit/`), use relative imports internally and module imports for external consumers.

### Linking system libraries

```zig
exe.root_module.linkSystemLibrary("gtk4", .{});
exe.root_module.linkSystemLibrary("sqlite3", .{});
exe.root_module.link_libc = true;
```

On macOS, Homebrew installs headers and libraries to `/opt/homebrew/`. Zig's build system discovers them automatically via `pkg-config` when available. On Windows (MSYS2), add the UCRT64 `bin` directory to `PATH`.

### Test configuration

```zig
// Test the kit module:
const kit_tests = b.addTest(.{ .root_module = kit_mod });
const run_kit_tests = b.addRunArtifact(kit_tests);
test_step.dependOn(&run_kit_tests.step);
```

Each module can have its own tests. Running `zig build test` executes all of them.

---

## IO Engine (`std.Io`)

Zig 0.16+ replaced `std.fs` with `std.Io`. The IO engine must be passed to almost every operation — a significant breaking change.

```zig
var threaded_io = std.Io.Threaded.init(gpa, .{});
const io = threaded_io.io();

// File operations:
const dir = std.Io.Dir.cwd();
var file = try dir.createFile(io, "path.txt", .{});
defer file.close(io);
```

---

## Thread Safety Patterns

### Atomic flags for stop signaling

A lightweight, lock-free way to signal threads to shut down:

```zig
stop_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

// Thread checks periodically:
if (e.stop_requested.load(.acquire)) break;

// Main thread signals:
self.stop_requested.store(true, .release);
```

### Mutex pattern with IO

```zig
e.mutex.lockUncancelable(e.io);
defer e.mutex.unlock(e.io);
```

The `lockUncancelable` variant prevents the lock from being interrupted by POSIX signals.

### `std.Thread.Mutex` disappeared (0.17.0-dev.1422+e863bf3be)

Blocking mutexes moved under the IO engine: `std.Io.Mutex`. Its `lock`/`unlock`/`lockUncancelable` all take an `Io` parameter (see the "Mutex pattern with IO" example above) — fine when the struct already carries an `io: std.Io` field (like `TTSEngine` does), but a real cost if it doesn't: every caller now needs an `Io` threaded in just to take a lock.

For `src/bible_db.zig`, none of the public functions carry an `Io` (they're plain `db: *sqlite3` + params), and threading one through every signature (plus every call site in `main.zig`/`llm_engine.zig`) wasn't worth it just for a lock. `std.atomic.Mutex` still exists and needs no `Io` — but it's lock-free-primitive-only (`tryLock`/`unlock`, no blocking `lock`). The fix is a two-line blocking wrapper:

```zig
var db_mutex: std.atomic.Mutex = .unlocked;

fn lockDb() void {
    while (!db_mutex.tryLock()) std.Thread.yield() catch {};
}
fn unlockDb() void {
    db_mutex.unlock();
}
```

A yield-spin loop is fine here specifically because the critical sections are a handful of `sqlite3_prepare_v2`/`step`/`finalize` calls — microseconds, not something worth a park/wake futex for. Don't reach for this pattern for anything longer-held; use `std.Io.Mutex` (thread the `Io` through) once a critical section does real work.

**Why this mutex needed to exist at all:** the system libsqlite3 linked on this project (both Homebrew macOS and apt Linux commonly) is compiled `-DSQLITE_THREADSAFE=2` ("multi-thread" mode — verified via `sqlite3_threadsafe()`), which explicitly forbids using *the same connection* from more than one OS thread concurrently. `llm_engine.zig` fires background work on detached GTK threads (`g_thread_new`) against the single `state.db` connection opened once in `main()` — before this mutex, a `zig build test` regression test that fired 8 concurrent writers at a shared in-memory connection reliably **SEGV'd**. This is a real crash-risk race condition in the shipped app whenever two background operations touch the db at once, not just a test artifact.

### `std.json.parseFromSlice` for a canonical data file

```zig
const Entry = struct { name: []const u8, testament: Testament }; // Testament: enum { Old, New, ... }
const parsed = try std.json.parseFromSlice([]const Entry, allocator, json_bytes, .{});
defer parsed.deinit();
// parsed.value is []const Entry — enum fields parse straight from matching string tags.
```

Reading the file itself needs the `std.Io.Dir` pattern from above, not `std.fs` (`std.fs.zig` in this nightly has no `cwd()` at all anymore — filesystem access is fully IO-engine-mediated now):

```zig
var threaded_io = std.Io.Threaded.init(allocator, .{});
defer threaded_io.deinit();
const contents = try std.Io.Dir.cwd().readFileAlloc(threaded_io.io(), "path.json", allocator, std.Io.Limit.limited(1024 * 1024));
```

Used in `src/bible_db.zig`'s `"BIBLE_BOOKS testament data matches tools/bible_books.json"` test — a regression guard that fails the build if the Zig-side canonical book/testament list and the JSON copy Python reads ever drift again (this is exactly how the original Hebrew/Greek mis-tagging bug happened).

### Thread join sequence

The ordering of shutdown operations matters:

```zig
pub fn stop(self: *TTSEngine) void {
    self.stop_requested.store(true, .release);
    if (self.task_thread) |th| {
        self.task_thread = null;
        _ = gtk.g_thread_join(th);  // Blocks until thread exits
    }
    // Safe to clean up after join
    if (self.current_process) |p| { ... }
}
```

**Order matters:** set the stop flag **first**, then join. The thread sees the flag, exits its loop, and the join returns. Reversing the order causes a deadlock or unsafe cleanup.
