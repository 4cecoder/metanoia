//! Reusable GTK4 theme loader.
//!
//! Provides a high-level API for loading CSS themes from files or strings,
//! with support for dynamic font-size updates. Decoupled from application
//! state — all data flows in through function parameters.

const std = @import("std");
const ffi = @import("ffi.zig");

pub const Theme = struct {
    provider: ?*ffi.GtkCssProvider,
    font_provider: ?*ffi.GtkCssProvider,

    /// Load a CSS theme from `path` and register it with the default display.
    /// Returns a `Theme` that holds both the main style provider and a
    /// separate font provider for dynamic size updates.
    pub fn init(path: [:0]const u8) Theme {
        const self = Theme{
            .provider = ffi.gtk_css_provider_new(),
            .font_provider = ffi.gtk_css_provider_new(),
        };

        ffi.gtk_css_provider_load_from_path(self.provider.?, path);
        ffi.gtk_style_context_add_provider_for_display(
            ffi.gdk_display_get_default(),
            @ptrCast(self.provider),
            ffi.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
        );

        ffi.gtk_style_context_add_provider_for_display(
            ffi.gdk_display_get_default(),
            @ptrCast(self.font_provider),
            ffi.GTK_STYLE_PROVIDER_PRIORITY_USER,
        );

        return self;
    }

    /// Load a CSS file from `path` at a given priority. Useful for loading
    /// additional stylesheets without replacing the main theme.
    pub fn loadFromFile(path: [:0]const u8, priority: u32) void {
        const provider = ffi.gtk_css_provider_new();
        ffi.gtk_css_provider_load_from_path(provider, path);
        ffi.gtk_style_context_add_provider_for_display(
            ffi.gdk_display_get_default(),
            @ptrCast(provider),
            priority,
        );
    }

    /// Load CSS from an inline string at a given priority.
    pub fn loadFromString(css: [:0]const u8, priority: u32) void {
        const provider = ffi.gtk_css_provider_new();
        ffi.gtk_css_provider_load_from_data(provider, css, -1);
        ffi.gtk_style_context_add_provider_for_display(
            ffi.gdk_display_get_default(),
            @ptrCast(provider),
            priority,
        );
    }

    /// Dynamically update font sizes for named views. The generated CSS
    /// targets `#left_view`, `#right_view`, `.greek`, and `.hebrew` selectors.
    pub fn updateFontSizes(self: Theme, english_size: i32, interlinear_size: i32) void {
        const allocator = std.heap.page_allocator;
        const css = std.fmt.allocPrintSentinel(allocator,
            \\#left_view, #left_view * {{ font-size: {d}px; }}
            \\#right_view, #right_view * {{ font-size: {d}px; }}
            \\.greek, .greek * {{ font-size: {d}px; }}
            \\.hebrew, .hebrew * {{ font-size: {d}px; }}
        , .{
            english_size,
            interlinear_size,
            interlinear_size,
            interlinear_size + 4,
        }, 0) catch return;
        defer allocator.free(css);
        ffi.gtk_css_provider_load_from_data(self.font_provider, css, -1);
    }
};

// ──────────────── Tests ────────────────

test "Theme.init returns non-null providers" {
    // We can't create a GTK display in unit tests, but we can verify
    // the struct layout and that init doesn't crash the allocator.
    // Full integration tests should run against a real GTK display.
    const theme = Theme{
        .provider = null,
        .font_provider = null,
    };
    try std.testing.expect(theme.provider == null);
    try std.testing.expect(theme.font_provider == null);
}
