# Metanoia Docs

Architecture and reference documentation for the Metanoia Bible study app.

## Index

| Doc | Subagent | Scope |
|-----|----------|-------|
| [KIT.md](KIT.md) | `ui-designer` | Kit module API, component refs, usage patterns |
| [SIGNAL_SAFETY.md](SIGNAL_SAFETY.md) | `code-reviewer` | Signal type-safe layer, DestroyNotify pattern, GTK FFI rules |
| [SETTINGS_IMPLEMENTATION.md](SETTINGS_IMPLEMENTATION.md) | `test-automator` | Settings panel TDD coverage, network discovery |
| [GEMINI.md](GEMINI.md) | `build-engineer` | Zig 0.16+ IO/stdlib migration cheatsheet |
| [WINDOWS_SETUP.md](WINDOWS_SETUP.md) | `deployment-engineer` | MSYS2 + Zig + GTK4 Windows build instructions |
| [PACKAGING.md](PACKAGING.md) | `deployment-engineer` | macOS/Linux/Android release packaging, Homebrew formula |
| [MAINTENANCE.md](MAINTENANCE.md) | — | Caching architecture, testing strategy, quick-wins backlog |
| [ZIG_DISCOVERIES.md](ZIG_DISCOVERIES.md) | `llm-architect` | Zig versioning, memory management, GTK FFI gotchas |
| [AGENTS.md](AGENTS.md) | `task-distributor` | Subagent task definitions for doc maintenance |

## Notes from this session

### UI/UX Kit (`src/kit/`)
Extracted all UI components from `src/ui/` into a reusable, decoupled library:

- **12 new files** under `src/kit/` — `ffi.zig`, `widget.zig`, `theme.zig`, `signal.zig`, `root.zig`, and 7 component/util files
- **Zero `@import("ui/...")` calls** remain in `main.zig` — all routing through `@import("kit")`
- **Callback pattern** replaces `app_state` god-struct coupling: every component takes typed callbacks (`SidebarCallbacks`, `SearchCallbacks`, `FlowPickerCallbacks`) instead of importing application state
- **Widget wrappers** (`kit/widget.zig`): 20 type-safe wrappers (Box, Label, Button, Window, Paned, Stack, etc.) with `pub fn widget(self)` returning the base `Widget` type

### Signal Type Safety (`src/kit/signal.zig`)
Prevents memory corruption from wrong `GClosureNotify` signatures at **compile time**:

- `DestroyNotify = *const fn (gpointer, ?*anyopaque) callconv(.c) void`
- `Signal.connect()` and `Signal.connectFlags()` wrap `g_signal_connect_data`
- Passing a 1-parameter destroy function is now a **compile error**
- `G_CONNECT_AFTER` flag available via `connectFlags` for safe self-freeing
- All 6 kit components refactored to use `Signal.connect()` — eliminated ~20 raw `g_signal_connect_data` calls

### Crash & Leak Fixes
- **`@memcpy` overlap → `@memmove`** in `load_chapter_into_study` (main.zig:500)
- **SettingsPanel self-free**: window's `destroy` signal with `G_CONNECT_AFTER` frees the panel struct after GTK cleanup
- **`onSaveClicked` use-after-free**: capture allocator before `close()` frees panel
- **Settings initial value strings**: freed after GTK copies them via `gtk_editable_set_text`
- **TTS engine thread races**: `g_thread_join` in `stop()` joins running task thread before cleanup, preventing segfault on mutex access after engine freed
- **TTS pipeline sub-threads**: removed `PipeGen` async sub-threading — synchronous lookahead eliminates orphaned thread allocations
