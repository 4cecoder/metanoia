//! Semi-stable reader foundations.
//!
//! This top-level barrel keeps all core sources inside the root `src/` module
//! path. Zig deliberately rejects `../` imports from a module root, so the
//! build graph uses this file rather than a nested `src/core/root.zig` while
//! retaining the same public `core` module boundary.

pub const bible = @import("bible_db.zig");
pub const config = @import("models/config.zig");
pub const gtk = @import("gtk.zig");

test {
    _ = bible;
    _ = config;
}
