# Zig 0.16.0-dev Cheatsheet (Metanoia Edition)

This document tracks the breaking changes and new patterns encountered during the transition to Zig `0.16.0-dev.2653+784e89fd4`.

## 1. The New IO Engine (`std.Io`)
Almost all standard library IO now requires an explicit "Engine" (usually `std.Io`).

### Obtaining an Engine
```zig
// Standard debug/threaded engine
const io = std.Options.debug_io; 

// OR manual initialization
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var threaded_io = std.Io.Threaded.init(gpa.allocator(), .{});
const io = threaded_io.ioBasic();
```

### Filesystem Operations
`std.fs.cwd()` is replaced by `std.Io.Dir.cwd()`.
```zig
const dir = std.Io.Dir.cwd();
const file = try dir.createFile(io, "path.txt", .{});
defer file.close(io); // Must pass io to close
```

### Reader & Writer API
Readers and Writers now require a buffer and the IO engine.
```zig
var buf: [1024]u8 = undefined;
var f_writer = file.writer(io, &buf);
try f_writer.interface.writeAll("hello");

var r_buf: [1024]u8 = undefined;
var f_reader = file.reader(io, &r_buf);
const data = try f_reader.interface.allocRemaining(allocator, std.Io.Limit.limited(1024));
```

## 2. Child Processes (`std.process`)
The `ChildProcess.init` pattern is replaced by `std.process.spawn`.

```zig
// Spawning
var child = try std.process.spawn(io, .{
    .argv = &.{ "ls", "-l" },
    .stdout = .pipe,
});

// Waiting
const term = try child.wait(io);
if (term == .exited and term.exited != 0) { ... }

// Killing
child.kill(io);
```

## 3. JSON Handling (`std.json`)
`std.json.stringify` is no longer a top-level function. Use the `Stringify` struct.

```zig
const Req = struct { text: []const u8 };
const data = Req{ .text = "hello" };

var buf: [1024]u8 = undefined;
var json_writer = std.Io.Writer.fixed(&buf);
var stringifier: std.json.Stringify = .{ .writer = &json_writer };
try stringifier.write(data);

const result = buf[0..json_writer.end];
```

## 4. ArrayLists
In some nightly builds, `std.ArrayList(T).init(allocator)` may fail to resolve. `ArrayListUnmanaged` is the robust alternative.

```zig
var list = std.ArrayListUnmanaged(u8).empty;
defer list.deinit(allocator);

try list.append(allocator, 'a');
try list.appendSlice(allocator, "string");
list.clearAndFree(allocator);
```

## 5. Lessons Learned
- **Double Close Panic:** Closing a file manually and then via `defer` causes a `reached unreachable code` panic (`BADF`). Only use `defer`.
- **UI Blocking:** When calling an external API (like the TTS server), always use a background thread (`g_thread_new`) or the application will freeze during the request.
- **Fixed Buffer Writers:** When using `std.Io.Writer.fixed(buf)`, the written length is stored in `writer.end`.

## 6. Qwen3-TTS Research & Optimization
Integration with Alibaba's Qwen3-TTS model for high-fidelity Bible reading.

### Cloning Modes
1.  **Timbre-Only (`x_vector_only_mode=True`):** Focuses purely on the pitch and "color" of the voice. No transcript needed. Fastest but less expressive.
2.  **In-Context Learning (ICL):** (Current Setup) Uses both reference audio and a transcript (`ref_text`). This allows the model to learn the speaker's specific prosody, rhythm, and emotional nuances.

### Quality Requirements
- **Audio Length:** Ideal clip is 5–10 seconds. Maximum effective length is 15 seconds.
- **Transcript Accuracy:** The `ref_text` must match the `reference.wav` exactly. Mismatches lead to stuttering or "hallucinated" pronunciations.
- **Noise Floor:** The model is highly sensitive; background noise in the reference will be cloned as a persistent hiss in the output.

### Performance (Apple Silicon)
- **Engine:** Use `device_map="mps"` to leverage the Metal GPU.
- **Attention:** Use `attn_implementation="sdpa"` (Scaled Dot Product Attention) as the macOS alternative to `flash-attn`.
- **Latency:** With pre-calculated prompts (`create_voice_clone_prompt`), chunked generation (1 verse) typically completes in < 2 seconds on M-series chips.

## 7. Multi-Voice Selection
The application supports multiple voice clones.

### Available Voices
- **`tommy`**: Cloned from `data/tommy.wav`.
- **`lennox`**: Cloned from `data/lennox_ref.wav` (John Lennox).
- **`mari`**: Cloned from `data/mari_ref.wav`.
- **`jordan`**: Cloned from `data/jordan_ref.wav` (Jordan Peterson).
- **`shamoun`**: Cloned from `data/shamoun_ref.wav` (Sam Shamoun).

### Switching Voices
Edit `data/config.json` and change the `selected_voice` field:
## 8. AI-Assisted Development Hints
These hints help AI agents work effectively with the Metanoia repository:
- **Repository Hygiene:** All large binary data (`.db`, `.wav`, `.onnx`, `.bin`) is excluded from Git. Do not attempt to read these unless checking local presence.
- **Auto-Updating Server:** The script `tools/run_tts_server.sh` combines `git fetch/pull` and `uvicorn --reload`. This is preferred for running the TTS server during development.
- **Mobile Pathing:** Model assets for Android belong in `mobile/app/src/main/assets/` but are ignored. If testing mobile features, verify asset presence first.
- **Zig 0.16.0 Migration:** Always cross-reference `src/main.zig` with `std.Io` patterns in section 1 of this document.
