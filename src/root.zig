pub const gtk = @import("gtk.zig");
pub const bible = @import("bible_db.zig");
pub const tts = @import("tts_client.zig");
pub const ollama = @import("ollama_client.zig");

test {
    _ = bible;
    _ = tts;
    _ = ollama;
}
