const std = @import("std");
const builtin = @import("builtin");
const tts = @import("../tts_client.zig");
const gtk = @import("../gtk.zig");

const gpointer = gtk.gpointer;

pub const TTSEngineConfig = struct {
    voice: []const u8,
    speed: f32,
    emotion: []const u8,
    mode: []const u8,
};

pub const PlaybackCallbacks = struct {
    onStatusUpdate: *const fn (msg: []const u8) void,
    onVerseHighlight: *const fn (idx: usize) void,
    onPlayStateChanged: *const fn (playing: bool) void,
};

pub const TTSEngine = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    stop_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    playing: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    task_thread: ?*anyopaque = null,

    current_process: ?*std.process.Child = null,
    mutex: std.Io.Mutex = .init,

    pipeline_paths: [2000]?[]const u8 = @splat(null),
    pipeline_inflight: [2000]bool = @splat(false),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) *TTSEngine {
        const self = allocator.create(TTSEngine) catch unreachable;
        self.* = .{
            .allocator = allocator,
            .io = io,
        };
        return self;
    }

    pub fn deinit(self: *TTSEngine) void {
        self.stop();
        self.cleanupPipeline();
        self.allocator.destroy(self);
    }

    pub fn isPlaying(self: *TTSEngine) bool {
        return self.playing.load(.acquire);
    }

    pub fn stop(self: *TTSEngine) void {
        self.stop_requested.store(true, .release);
        // Join the running task thread so it doesn't access freed memory
        if (self.task_thread) |th| {
            self.task_thread = null;
            _ = gtk.g_thread_join(th);
        }
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.current_process) |p| {
            if (p.id) |pid| {
                // std.process.Child.Id is std.posix.pid_t (an integer) on
                // POSIX but std.os.windows.HANDLE (*anyopaque) on Windows —
                // std.posix.kill only exists/applies to the former. Using
                // the higher-level Child.kill() instead isn't safe here: it
                // blocks until the process exits and reaps/finalizes the
                // same Child struct that the spawning thread is
                // concurrently blocked inside child.wait(e.io) on (see
                // playSequential/playChapter below) — two threads racing to
                // finalize the same Child. So on Windows this calls the
                // same raw termination primitive Child.kill() itself uses
                // internally (std.os.windows.ntdll.NtTerminateProcess),
                // without its blocking wait-and-cleanup, matching the old
                // POSIX code's "just signal, let the spawning thread's own
                // wait() reap it" semantics exactly.
                switch (builtin.os.tag) {
                    .windows => _ = std.os.windows.ntdll.NtTerminateProcess(pid, @enumFromInt(1)),
                    else => if (pid != 0) std.posix.kill(pid, std.posix.SIG.TERM) catch {},
                }
            }
        }
    }

    pub fn playSequential(self: *TTSEngine, verses: []const []const u8, start_idx: usize, config: TTSEngineConfig, callbacks: PlaybackCallbacks) void {
        self.stop();

        const Task = struct {
            engine: *TTSEngine,
            verses: []const []const u8,
            start_idx: usize,
            config: TTSEngineConfig,
            callbacks: PlaybackCallbacks,

            fn run(p: gpointer) callconv(.c) gpointer {
                const t: *@This() = @ptrCast(@alignCast(p));
                const e = t.engine;
                const allocator = e.allocator;

                e.playing.store(true, .release);
                t.callbacks.onPlayStateChanged(true);
                e.stop_requested.store(false, .release);

                defer {
                    e.playing.store(false, .release);
                    t.callbacks.onPlayStateChanged(false);
                    e.cleanupPipeline();
                    allocator.destroy(t);
                }

                var curr = t.start_idx;

                while (true) {
                    if (e.stop_requested.load(.acquire)) break;
                    if (curr >= t.verses.len) break;

                    // 1. Fill pipeline lookahead (4 verses ahead)

                    var la: usize = 0;
                    while (la < 4) : (la += 1) {
                        const idx = curr + la;
                        if (idx >= t.verses.len) break;

                        e.mutex.lockUncancelable(e.io);
                        const needs = e.pipeline_paths[idx] == null and !e.pipeline_inflight[idx];
                        if (needs) e.pipeline_inflight[idx] = true;
                        e.mutex.unlock(e.io);

                        if (needs) {
                            const path = tts.generate_speech(
                                e.io,
                                t.verses[idx],
                                t.config.voice,
                                t.config.speed,
                                t.config.emotion,
                                "speedy",
                                false,
                            ) catch null;
                            e.mutex.lockUncancelable(e.io);
                            if (idx < 2000) {
                                e.pipeline_paths[idx] = path;
                                e.pipeline_inflight[idx] = false;
                            }
                            e.mutex.unlock(e.io);
                        }
                    }

                    // 2. Wait for current verse audio
                    var audio_path: ?[]const u8 = null;
                    while (true) {
                        if (e.stop_requested.load(.acquire)) break;
                        e.mutex.lockUncancelable(e.io);
                        audio_path = e.pipeline_paths[curr];
                        e.mutex.unlock(e.io);
                        if (audio_path != null) break;
                        gtk.g_usleep(10 * 1000);
                    }
                    if (e.stop_requested.load(.acquire)) break;

                    // 3. Highlight current verse
                    t.callbacks.onVerseHighlight(curr);

                    // 4. Play audio
                    if (audio_path) |ap| {
                        var child = switch (builtin.os.tag) {
                            .macos => std.process.spawn(e.io, .{ .argv = &.{ "afplay", ap } }) catch break,
                            .windows => blk: {
                                const ps_cmd = std.fmt.allocPrint(e.allocator, "(New-Object Media.SoundPlayer '{s}').PlaySync()", .{ap}) catch break;
                                defer e.allocator.free(ps_cmd);
                                break :blk std.process.spawn(e.io, .{ .argv = &.{ "powershell", "-NoLogo", "-Command", ps_cmd } }) catch break;
                            },
                            else => break,
                        };
                        e.mutex.lockUncancelable(e.io);
                        e.current_process = &child;
                        e.mutex.unlock(e.io);

                        _ = child.wait(e.io) catch {};

                        e.mutex.lockUncancelable(e.io);
                        if (e.current_process == &child) e.current_process = null;
                        e.mutex.unlock(e.io);
                    }

                    if (e.stop_requested.load(.acquire)) break;
                    curr += 1;
                }
                return null;
            }
        };

        const task = self.allocator.create(Task) catch return;
        task.* = .{
            .engine = self,
            .verses = verses,
            .start_idx = start_idx,
            .config = config,
            .callbacks = callbacks,
        };
        self.task_thread = gtk.g_thread_new("tts_seq", &Task.run, task);
    }

    pub fn playChapter(self: *TTSEngine, full_text: []const u8, config: TTSEngineConfig, callbacks: PlaybackCallbacks) void {
        self.stop();

        const Task = struct {
            engine: *TTSEngine,
            text: []const u8,
            config: TTSEngineConfig,
            callbacks: PlaybackCallbacks,

            fn run(p: gpointer) callconv(.c) gpointer {
                const t: *@This() = @ptrCast(@alignCast(p));
                const e = t.engine;
                const allocator = e.allocator;

                e.playing.store(true, .release);
                t.callbacks.onPlayStateChanged(true);

                defer {
                    e.playing.store(false, .release);
                    t.callbacks.onPlayStateChanged(false);
                    allocator.free(t.text);
                    allocator.destroy(t);
                }

                t.callbacks.onStatusUpdate("Preparing Full Chapter Audio...");

                const path = tts.generate_speech(
                    e.io,
                    t.text,
                    t.config.voice,
                    t.config.speed,
                    t.config.emotion,
                    t.config.mode,
                    false,
                ) catch {
                    t.callbacks.onStatusUpdate("TTS generation failed.");
                    return null;
                };

                var child = switch (builtin.os.tag) {
                    .macos => std.process.spawn(e.io, .{ .argv = &.{ "afplay", path } }) catch {
                        allocator.free(path);
                        return null;
                    },
                    .windows => blk: {
                        const ps_cmd = std.fmt.allocPrint(e.allocator, "(New-Object Media.SoundPlayer '{s}').PlaySync()", .{path}) catch {
                            allocator.free(path);
                            return null;
                        };
                        defer e.allocator.free(ps_cmd);
                        break :blk std.process.spawn(e.io, .{ .argv = &.{ "powershell", "-NoLogo", "-Command", ps_cmd } }) catch {
                            allocator.free(path);
                            return null;
                        };
                    },
                    else => {
                        allocator.free(path);
                        return null;
                    },
                };

                e.mutex.lockUncancelable(e.io);
                e.current_process = &child;
                e.mutex.unlock(e.io);

                _ = child.wait(e.io) catch {};

                e.mutex.lockUncancelable(e.io);
                if (e.current_process == &child) e.current_process = null;
                e.mutex.unlock(e.io);

                allocator.free(path);
                t.callbacks.onStatusUpdate("Full Chapter Playback Finished.");
                return null;
            }
        };

        const text_dupe = self.allocator.dupe(u8, full_text) catch return;
        const task = self.allocator.create(Task) catch {
            self.allocator.free(text_dupe);
            return;
        };
        task.* = .{
            .engine = self,
            .text = text_dupe,
            .config = config,
            .callbacks = callbacks,
        };
        self.task_thread = gtk.g_thread_new("tts_chapter", &Task.run, task);
    }

    pub fn regenerateVerse(self: *TTSEngine, text: []const u8, config: TTSEngineConfig, onDone: *const fn () void) void {
        const Task = struct {
            engine: *TTSEngine,
            text: []const u8,
            config: TTSEngineConfig,
            onDone: *const fn () void,

            fn run(p: gpointer) callconv(.c) gpointer {
                const t: *@This() = @ptrCast(@alignCast(p));
                const e = t.engine;
                const allocator = e.allocator;
                defer {
                    allocator.free(t.text);
                    allocator.destroy(t);
                }

                const path = tts.generate_speech(
                    e.io,
                    t.text,
                    t.config.voice,
                    t.config.speed,
                    t.config.emotion,
                    t.config.mode,
                    true,
                ) catch null;
                if (path) |pa| allocator.free(pa);

                t.onDone();
                return null;
            }
        };

        const text_dupe = self.allocator.dupe(u8, text) catch return;
        const task = self.allocator.create(Task) catch {
            self.allocator.free(text_dupe);
            return;
        };
        task.* = .{
            .engine = self,
            .text = text_dupe,
            .config = config,
            .onDone = onDone,
        };
        _ = gtk.g_thread_new("tts_reg", &Task.run, task);
    }

    fn cleanupPipeline(self: *TTSEngine) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const page_allocator = std.heap.page_allocator;
        for (&self.pipeline_paths) |*p| {
            if (p.*) |path| {
                page_allocator.free(path);
                p.* = null;
            }
        }
        @memset(&self.pipeline_inflight, false);
    }
};
