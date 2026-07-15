# Kit Module (`src/kit/`)

Decoupled, reusable GTK4 UI component library for Zig.

- [Module structure](#module-structure)
- [Usage](#usage)
- [Component callback pattern](#component-callback-pattern)
- [Signal connections](#signal-connections)

## Module structure

```text
src/kit/
├── ffi.zig           # Raw GTK4/GLib C FFI declarations (301 lines, 25 labeled sections)
├── widget.zig        # Type-safe widget wrappers (20 types)
├── theme.zig         # Theme/CSS loader
├── signal.zig        # Type-safe signal connections with compile-time DestroyNotify validation
├── root.zig          # Public entry point — re-exports all sub-modules
├── util/
│   ├── text.zig      # Pango markup: escape, span, bold, colored (+ 13 tests)
│   ├── threading.zig # GLib thread/idle helpers: idleAdd, threadSpawn, postToMain
│   └── tracker.zig   # Leak-detecting allocator wrapper for TDD
└── components/
    ├── status_bar.zig       # System status + progress bar + telemetry
    ├── sidebar.zig          # Collapsible expander sections + highlights + TTS
    ├── search_window.zig    # Spotlight-style search with injectable search callback
    ├── dialog.zig           # Modal dialog builder with configurable button rows
    ├── flow_picker.zig      # Multi-level grid picker with dynamic level loading
    └── settings_panel.zig   # Settings dialog from section/field descriptors
```

## Usage

```zig
const kit = @import("kit");

// Widget wrappers
const box = kit.widget.Box.vertical(0);
box.append(child_widget);
box.widget().addCssClass("my-class");

// Components
const status = kit.components.StatusBar.init(allocator);
const sidebar = kit.components.Sidebar.init(allocator, .{
    .onColorClicked = myColorHandler,
});
```

## Component callback pattern

Every component accepts typed callbacks instead of importing app state directly:

```zig
pub const SearchCallbacks = struct {
    onNavigate: *const fn (book: []const u8, chapter: i32, verse: i32) void,
    onStatus: *const fn (msg: []const u8, is_error: bool) void,
    performSearch: *const fn (allocator, query, *ArrayList(SearchResult)) usize,
};
```

## Signal connections

Always use `kit.signal.Signal.connect` instead of raw `g_signal_connect_data`:

```zig
// Destroy callback validated at compile time
const d = struct {
    fn onClick(_: ?*GtkButton, data: gpointer) callconv(.c) void { ... }
    fn destroy(data: gpointer, _: ?*anyopaque) callconv(.c) void {
        // Must have EXACTLY 2 params — compiler enforces this
    }
};
Signal.connect(button, "clicked", @ptrCast(&d.onClick), ctx, d.destroy);
```

For the full explanation of compile-time DestroyNotify validation and the C ABI pitfalls it prevents, see [SIGNAL_SAFETY.md](SIGNAL_SAFETY.md).

For Zig versioning advice, GTK FFI gotchas, and memory management patterns (including DebugAllocator false positives and the allocator wrapping pattern used by `util/tracker.zig`), see [ZIG_DISCOVERIES.md](ZIG_DISCOVERIES.md).
