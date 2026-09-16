//! Service adapters shared by the GTK application.
//!
//! This top-level barrel lets service implementation files retain access to
//! sibling application sources while exposing a separate `services` build
//! module to the app root.

pub const tts_engine = @import("services/tts_engine.zig");
pub const llm_engine = @import("services/llm_engine.zig");
pub const network_discovery = @import("services/network_discovery.zig");
pub const update_checker = @import("services/update_checker.zig");

test {
    _ = tts_engine;
    _ = llm_engine;
    _ = network_discovery;
    _ = update_checker;
}
