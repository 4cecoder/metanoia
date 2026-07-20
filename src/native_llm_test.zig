const std = @import("std");
const llm_client = @import("llm_client.zig");

// Real end-to-end verification of the native LLM backend through the
// actual app integration point (`llm_client.generate_response`) — the
// exact function both of `services/llm_engine.zig`'s `analyzeVerse` call
// sites invoke — not just aikit's own standalone `run-llm-generate`
// example. Requires the ~265MB MLX checkpoint at
// vendor/llm/qwen2.5-0.5b-instruct-4bit/ (see llm_client.zig's
// native_model_dir) — not shipped in git and won't be present in normal
// CI, so this lives behind a dedicated `zig build test-native-llm` step
// rather than the default `test` step. Still degrades gracefully via
// SkipZigTest if run somewhere the weights happen to be absent.
//
// Deliberately exercises `llm_client.generate_response` directly rather
// than driving `llm_engine.LLMEngine.analyzeVerse`'s full GTK-threaded
// flow (which also touches sqlite lexicon/summary lookups and live
// BibleHub network scraping): `generate_response` *is* the real,
// production `llm_client.zig` code both `analyzeVerse` call sites call —
// the LLM-backend-selection logic this task is actually verifying — and
// testing it directly keeps this test deterministic and independent of
// unrelated network/scraper flakiness, the same reasoning
// `native_tts_test.zig` didn't need to apply (TTS has no such
// network-dependent call sites in its path).
test "llm_client.generate_response native backend produces a real generated response" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    std.Io.Dir.cwd().access(io, "vendor/llm/qwen2.5-0.5b-instruct-4bit/tokenizer.json", .{}) catch return error.SkipZigTest;
    std.Io.Dir.cwd().access(io, "vendor/llm/qwen2.5-0.5b-instruct-4bit/model.safetensors", .{}) catch return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // Unlike the real app (which keeps the native model resident for its
    // whole lifetime — see llm_client.zig's native_llm doc comment), this
    // test process exits right after one call. Release the MLX/Metal
    // resources explicitly, same reasoning as native_tts_test.zig's
    // shutdownNativeBackendForTesting.
    defer llm_client.shutdownNativeLLMBackendForTesting();

    // generate_response reads llm_backend from data/config.json by path
    // (not a param), so force the native backend on for this call by
    // swapping in a temp config — save/restore the real file so this test
    // doesn't leave the working tree dirty either on success or failure.
    const config_path = "data/config.json";
    const original = std.Io.Dir.cwd().readFileAlloc(io, config_path, allocator, std.Io.Limit.limited(1 << 20)) catch
        try allocator.dupe(u8, "");
    defer allocator.free(original);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = config_path, .data = "{\"llm_backend\": \"native\"}" });
    defer std.Io.Dir.cwd().writeFile(io, .{ .sub_path = config_path, .data = original }) catch {};

    // Same prompt shape as llm_engine.zig's chapter-summary call site
    // (see `analyzeVerse`'s `summary_prompt`), applied to a real verse
    // text so this exercises the actual production prompt format, not a
    // synthetic one.
    const prompt = "Summarize the following Bible chapter in one concise sentence: John 3 - " ++
        "\"For God so loved the world, that he gave his only begotten Son, " ++
        "that whosoever believeth in him should not perish, but have everlasting life.\"";

    const response = try llm_client.generate_response(allocator, io, prompt);
    defer allocator.free(response);

    std.debug.print("[native_llm_test] prompt: \"{s}\"\n", .{prompt});
    std.debug.print("[native_llm_test] native response ({d} bytes): \"{s}\"\n", .{ response.len, response });

    try std.testing.expect(response.len > 0);
}
