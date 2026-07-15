# Signal Type-Safe Layer

Prevents GTK signal destroy callback signature mismatches at **compile time**, catching a class of bugs that would otherwise cause silent memory corruption at runtime.

## Why This Matters

C ABI mismatches are among the hardest bugs to find in Zig GTK4 applications. A destroy callback with the wrong number of parameters compiles without warning — the `@ptrCast` silences the type system — but at runtime the C ABI reads garbage off the stack for the missing argument. This corrupts memory, produces non-deterministic crashes, and can take hours to diagnose.

The `DestroyNotify` type alias in `signal.zig` eliminates this entire category of bug by enforcing the correct signature **at compile time**. If a callback doesn't match, the code won't build.

## The Problem

GTK's `g_signal_connect_data` takes a `GClosureNotify` destroy callback with this C signature:

```c
void (*GClosureNotify)(gpointer data, GClosure *closure);
```

The project's FFI declarations in `ffi.zig` originally declared this parameter as `?*const anyopaque`. Passing a one-parameter function:

```zig
fn badDestroy(data: gpointer) callconv(.c) void { ... }
```

...compiles silently via `@ptrCast`, but at runtime the C ABI reads a second argument off the stack, causing memory corruption.

## The Fix: `DestroyNotify`

```zig
pub const DestroyNotify = *const fn (data: gpointer, closure: ?*anyopaque) callconv(.c) void;
```

`Signal.connect()` accepts `destroy: ?DestroyNotify`. If you pass a one-parameter function, the compiler rejects it:

```text
error: expected type '*const fn (gpointer, ?*anyopaque) callconv(.c) void',
       found '*const fn (gpointer) callconv(.c) void'
```

## API

```zig
// Basic connect (flags = 0)
Signal.connect(instance, "signal-name", @ptrCast(&handler), context, destroyFn);

// With G_CONNECT_AFTER for safe self-freeing
Signal.connectFlags(instance, "signal-name", @ptrCast(&handler), context, null, 1);
```

## Rules

1. **Handler**: any `callconv(.c)` function pointer — cast with `@ptrCast(&fn)`
2. **Destroy**: must match `fn (gpointer, ?*anyopaque) callconv(.c) void` or be `null`
3. **Flags**: 0 = normal, 1 = `G_CONNECT_AFTER` (handler runs after default)
4. **Never** call `ffi.g_signal_connect_data` directly — always use `Signal.connect`

## Components refactored

| Component | Raw calls removed | Destroy callbacks validated |
|-----------|-------------------|----------------------------|
| sidebar.zig | 2 | ColorBridge.destroy, VoiceBridge.destroy |
| search_window.zig | 6 | DestroyRD.destroy |
| dialog.zig | 2 | BtnCtx.destroy, CloseCtx.destroy |
| flow_picker.zig | 2 | ClickCtx.destroy |
| settings_panel.zig | 3 | DestroySelf.callback (G_CONNECT_AFTER) |

## Related Documentation

- **[KIT.md](./KIT.md)** — module structure showing `signal.zig` in context, plus `Signal.connect` usage examples in components
- **[ZIG_DISCOVERIES.md](./ZIG_DISCOVERIES.md)** — narrative discovery of the `DestroyNotify` bug, GTK FFI signal signature table, and `G_CONNECT_AFTER` self-freeing pattern
