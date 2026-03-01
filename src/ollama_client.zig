const std = @import("std");

pub const OllamaRequest = struct {
    model: []const u8 = "granite4:350m",
    prompt: []const u8,
    stream: bool = false,
};

pub const OllamaResponse = struct {
    response: []const u8,
};

pub fn generate_response(allocator: std.mem.Allocator, engine: std.Io, prompt: []const u8) ![]const u8 {
    const ollama_json_path = "data/ollama_req.json";
    const out_json_path = "cache/ollama_res.json";

    // 1. Prepare Request JSON
    const req = OllamaRequest{ .prompt = prompt };
    
    var json_buf: [16384]u8 = undefined;
    var json_writer = std.Io.Writer.fixed(&json_buf);
    var stringifier: std.json.Stringify = .{ .writer = &json_writer };
    try stringifier.write(req);
    const json_str = json_buf[0..json_writer.end];

    // 2. Save Request to File
    const f = try std.Io.Dir.cwd().createFile(engine, ollama_json_path, .{});
    // Use empty buffer to force immediate IO dispatch
    var fw = f.writer(engine, &.{});
    try fw.interface.writeAll(json_str);
    f.close(engine);

    // 3. Spawn Curl
    const data_arg = try std.fmt.allocPrint(allocator, "@{s}", .{ollama_json_path});
    defer allocator.free(data_arg);

    var child = try std.process.spawn(engine, .{
        .argv = &.{ "curl", "-s", "-X", "POST", "http://127.0.0.1:11434/api/generate", "-H", "Content-Type: application/json", "--data-binary", data_arg, "-o", out_json_path },
    });
    _ = try child.wait(engine);

    // 4. Read and Parse Response
    const res_file = try std.Io.Dir.cwd().openFile(engine, out_json_path, .{});
    defer res_file.close(engine);
    
    var r_buf: [1024]u8 = undefined;
    var fr = res_file.reader(engine, &r_buf);
    const content = try fr.interface.allocRemaining(allocator, std.Io.Limit.limited(1024 * 1024));
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(OllamaResponse, allocator, content, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    return allocator.dupe(u8, parsed.value.response);
}

test "ollama request json" {
    const req = OllamaRequest{ .prompt = "test prompt" };
    var buf: [256]u8 = undefined;
    var f_writer = std.Io.Writer.fixed(&buf);
    var stringifier: std.json.Stringify = .{ .writer = &f_writer };
    try stringifier.write(req);
    
    const result = buf[0..f_writer.end];
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"model\":\"granite4:350m\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"prompt\":\"test prompt\""));
}
