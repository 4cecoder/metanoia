const std = @import("std");
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
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.current_process) |p| {
            if (p.id) |pid| {
                if (pid != 0) std.posix.kill(pid, std.posix.SIG.TERM) catch {};
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
                    const PipeGen = struct {
                        engine: *TTSEngine,
                        verse_idx: usize,
                        text: []const u8,
                        voice: []const u8,
                        speed: f32,
                        emotion: []const u8,
                        mode: []const u8,

                        fn run(raw: gpointer) callconv(.c) gpointer {
                            const ctx: *@This() = @ptrCast(@alignCast(raw));
                            const a = ctx.engine.allocator;

                            const path = tts.generate_speech(
                                ctx.engine.io,
                                ctx.text,
                                ctx.voice,
                                ctx.speed,
                                ctx.emotion,
                                ctx.mode,
                                false,
                            ) catch null;

                            ctx.engine.mutex.lockUncancelable(ctx.engine.io);
                            if (ctx.verse_idx < 2000) {
                                ctx.engine.pipeline_paths[ctx.verse_idx] = path;
                                ctx.engine.pipeline_inflight[ctx.verse_idx] = false;
                            }
                            ctx.engine.mutex.unlock(ctx.engine.io);

                            a.free(ctx.text);
                            a.destroy(ctx);
                            return null;
                        }
                    };

                    var la: usize = 0;
                    while (la < 4) : (la += 1) {
                        const idx = curr + la;
                        if (idx >= t.verses.len) break;

                        e.mutex.lockUncancelable(e.io);
                        const needs = e.pipeline_paths[idx] == null and !e.pipeline_inflight[idx];
                        if (needs) e.pipeline_inflight[idx] = true;
                        e.mutex.unlock(e.io);

                        if (needs) {
                            const ctx = allocator.create(PipeGen) catch continue;
                            const text_dupe = allocator.dupe(u8, t.verses[idx]) catch {
                                allocator.destroy(ctx);
                                continue;
                            };
                            ctx.* = .{
                                .engine = e,
                                .verse_idx = idx,
                                .text = text_dupe,
                                .voice = t.config.voice,
                                .speed = t.config.speed,
                                .emotion = t.config.emotion,
                                .mode = "speedy",
                            };
                            _ = gtk.g_thread_new("tts_pipe", &PipeGen.run, ctx);
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

                    // 4. Play audio via afplay
                    if (audio_path) |ap| {
                        var child = std.process.spawn(e.io, .{ .argv = &.{ "afplay", ap } }) catch break;
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
        _ = gtk.g_thread_new("tts_seq", &Task.run, task);
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

                var child = std.process.spawn(e.io, .{ .argv = &.{ "afplay", path } }) catch {
                    allocator.free(path);
                    return null;
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
        _ = gtk.g_thread_new("tts_chapter", &Task.run, task);
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
        for (&self.pipeline_paths) |*p| {
            if (p.*) |path| {
                self.allocator.free(path);
                p.* = null;
            }
        }
        @memset(&self.pipeline_inflight, false);
    }
};
