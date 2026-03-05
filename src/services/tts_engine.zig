const std = @import("std");
const tts = @import("../tts_client.zig");
const gtk = @import("../gtk.zig");

const gpointer = gtk.gpointer;

pub const TTSEngine = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    
    // State
    stop_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    playing: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    
    current_process: ?*std.process.Child = null,
    lock: std.Thread.Mutex = .{},
    
    // Pipeline
    pipeline_paths: [2000]?[]const u8 = [_]?[]const u8{null} ** 2000,
    pipeline_inflight: [2000]bool = [_]bool{false} ** 2000,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) *TTSEngine {
        const self = allocator.create(TTSEngine) catch unreachable;
        self.* = .{
            .allocator = allocator,
            .io = io,
        };
        return self;
    }

    pub fn stop(self: *TTSEngine) void {
        self.stop_requested.store(true, .release);
        self.lock.lock();
        defer self.lock.unlock();
        if (self.current_process) |p| {
            if (p.id != 0) std.posix.kill(p.id, std.posix.SIG.TERM) catch {};
        }
    }

    pub fn playSequential(self: *TTSEngine, verses: []const []const u8, start_idx: usize, config: anytype) void {
        self.stop(); // Ensure previous is stopped
        
        const Task = struct {
            engine: *TTSEngine,
            verses: []const []const u8,
            start_idx: usize,
            voice: []const u8,
            speed: f32,
            emotion: []const u8,

            fn run(p: gpointer) callconv(.c) gpointer {
                const s: *@This() = @ptrCast(@alignCast(p));
                s.engine.playing.store(true, .release);
                s.engine.stop_requested.store(false, .release);
                
                defer {
                    s.engine.playing.store(false, .release);
                    s.engine.cleanupPipeline();
                }

                var curr = s.start_idx;
                while (curr < s.verses.len) : (curr += 1) {
                    if (s.engine.stop_requested.load(.acquire)) break;
                    
                    // 1. Fill Lookahead
                    s.engine.fillPipeline(s.verses, curr, s.voice, s.speed, s.emotion);
                    
                    // 2. Wait for current
                    const path = s.engine.waitForVerse(curr) orelse break;
                    
                    // 3. Play
                    s.engine.playFile(path);
                }
                return null;
            }
        };

        const task = self.allocator.create(Task) catch return;
        task.* = .{
            .engine = self,
            .verses = verses,
            .start_idx = start_idx,
            .voice = config.voice,
            .speed = config.speed,
            .emotion = config.emotion,
        };
        _ = gtk.g_thread_new("tts-sequential", &Task.run, task);
    }

    fn fillPipeline(self: *TTSEngine, verses: []const []const u8, current: usize, voice: []const u8, speed: f32, emotion: []const u8) void {
        var lookahead: usize = 0;
        while (lookahead < 4) : (lookahead += 1) {
            const idx = current + lookahead;
            if (idx >= verses.len or idx >= 2000) break;

            self.lock.lock();
            const trigger = (self.pipeline_paths[idx] == null and !self.pipeline_inflight[idx]);
            if (trigger) self.pipeline_inflight[idx] = true;
            self.lock.unlock();

            if (trigger) {
                // Spawn generation thread
                // (Simplified: in real app we'd use a worker pool)
            }
        }
    }

    fn waitForVerse(self: *TTSEngine, idx: usize) ?[]const u8 {
        while (true) {
            if (self.stop_requested.load(.acquire)) return null;
            self.lock.lock();
            const p = self.pipeline_paths[idx];
            self.lock.unlock();
            if (p != null) return p;
            gtk.g_usleep(10 * 1000);
        }
    }

    fn playFile(self: *TTSEngine, path: []const u8) void {
        var child = std.process.spawn(self.io, .{ .argv = &.{ "afplay", path } }) catch return;
        self.lock.lock();
        self.current_process = &child;
        self.lock.unlock();
        
        _ = child.wait(self.io) catch {};
        
        self.lock.lock();
        if (self.current_process == &child) self.current_process = null;
        self.lock.unlock();
    }

    fn cleanupPipeline(self: *TTSEngine) void {
        self.lock.lock();
        defer self.lock.unlock();
        for (&self.pipeline_paths) |*p| {
            if (p.*) |path| {
                self.allocator.free(path);
                p.* = null;
            }
        }
        @memset(&self.pipeline_inflight, false);
    }
};
