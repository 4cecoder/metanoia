pub const gtk = @import("gtk.zig");
pub const bible = @import("bible_db.zig");
pub const tts = @import("tts_client.zig");
pub const ollama = @import("ollama_client.zig");
pub const network_discovery = @import("services/network_discovery.zig");
pub const app_state = @import("models/app_state.zig");
pub const settings_dialog = @import("ui/settings_dialog.zig");

test {
    _ = bible;
    _ = tts;
    _ = ollama;
    _ = network_discovery;
    _ = app_state;
}
