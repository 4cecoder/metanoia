pub const gtk = @import("gtk.zig");
pub const bible = @import("bible_db.zig");
pub const tts = @import("tts_client.zig");
pub const ollama = @import("ollama_client.zig");
pub const llm_client = @import("llm_client.zig");
pub const network_discovery = @import("services/network_discovery.zig");
pub const kit = @import("kit/root.zig");

test {
    _ = bible;
    _ = tts;
    _ = ollama;
    _ = llm_client;
    _ = network_discovery;
}
