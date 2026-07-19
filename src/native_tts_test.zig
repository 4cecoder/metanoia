const std = @import("std");
const tts_client = @import("tts_client.zig");

// Real end-to-end verification of the native TTS backend through the
// actual app integration point (`tts_client.generate_speech`), not just
// aikit's own standalone `run-example`. Requires the ~1.3GB GGUF weights
// at vendor/qwentts.cpp/models/ (see tts_client.zig's native_model_path /
// native_codec_path) — those aren't shipped in git and won't be present in
// normal CI, so this lives behind a dedicated `zig build test-native-tts`
// step rather than the default `test` step (which every contributor and
// CI run pays for). Still degrades gracefully via SkipZigTest if run
// somewhere the weights happen to be absent.
test "generate_speech native backend produces real cloned-voice audio (tommy)" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    std.Io.Dir.cwd().access(io, "vendor/qwentts.cpp/models/qwen-talker-0.6b-base-Q8_0.gguf", .{}) catch return error.SkipZigTest;
    std.Io.Dir.cwd().access(io, "vendor/qwentts.cpp/models/qwen-tokenizer-12hz-Q8_0.gguf", .{}) catch return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // Unlike the real app (which keeps the native model resident for its
    // whole lifetime — see tts_client.zig's native_synth doc comment), this
    // test process exits right after one call. Release the Metal/GGML
    // context explicitly so ggml-metal's own global device-registry
    // destructor doesn't assert on unreleased residency sets at exit.
    defer tts_client.shutdownNativeBackendForTesting();

    // generate_speech reads tts_backend from data/config.json by path (not
    // a param), so force the native backend on for this call by swapping
    // in a temp config — save/restore the real file so this test doesn't
    // leave the working tree dirty either on success or failure.
    const config_path = "data/config.json";
    const original = std.Io.Dir.cwd().readFileAlloc(io, config_path, allocator, std.Io.Limit.limited(1 << 20)) catch
        try allocator.dupe(u8, "");
    defer allocator.free(original);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = config_path, .data = "{\"tts_backend\": \"native\"}" });
    defer std.Io.Dir.cwd().writeFile(io, .{ .sub_path = config_path, .data = original }) catch {};

    const path = try tts_client.generate_speech(
        io,
        "Hello from the native backend end to end test.",
        "tommy",
        1.0,
        "",
        "speedy",
        true, // force_refresh: guarantee this actually exercises synthesis, not a cache hit
    );
    defer std.heap.page_allocator.free(path);
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

    try std.testing.expect(std.mem.startsWith(u8, path, "cache/tts_"));
    try std.testing.expect(std.mem.endsWith(u8, path, ".wav"));

    const wav_bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, std.Io.Limit.limited(64 << 20));
    defer allocator.free(wav_bytes);

    try std.testing.expect(wav_bytes.len > 44);
    try std.testing.expectEqualStrings("RIFF", wav_bytes[0..4]);
    try std.testing.expectEqualStrings("WAVE", wav_bytes[8..12]);

    // Non-silent check, same spirit as aikit/examples/tommy_test.zig's own
    // sanity check on the Phase 1 spike.
    const data = wav_bytes[44..];
    var sum_abs: u64 = 0;
    var i: usize = 0;
    while (i + 1 < data.len) : (i += 2) {
        const s: i16 = std.mem.readInt(i16, data[i..][0..2], .little);
        sum_abs += @abs(@as(i32, s));
    }
    const n_samples = data.len / 2;
    const mean_abs = if (n_samples > 0) sum_abs / n_samples else 0;
    std.debug.print(
        "[native_tts_test] wrote {s}: {d} bytes, mean|sample|={d} (non-silent={})\n",
        .{ path, wav_bytes.len, mean_abs, mean_abs > 50 },
    );
    try std.testing.expect(mean_abs > 50);
}
