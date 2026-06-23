const std = @import("std");
const gtk = @import("../gtk.zig");

pub const GtkCssProvider = gtk.GtkCssProvider;

pub const Theme = struct {
    provider: ?*GtkCssProvider,
    font_provider: ?*GtkCssProvider,

    pub fn init(path: [:0]const u8) Theme {
        const self = Theme{
            .provider = gtk.gtk_css_provider_new(),
            .font_provider = gtk.gtk_css_provider_new(),
        };

        gtk.gtk_css_provider_load_from_path(self.provider.?, path);
        gtk.gtk_style_context_add_provider_for_display(
            gtk.gdk_display_get_default(),
            @ptrCast(self.provider),
            gtk.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
        );

        gtk.gtk_style_context_add_provider_for_display(
            gtk.gdk_display_get_default(),
            @ptrCast(self.font_provider),
            gtk.GTK_STYLE_PROVIDER_PRIORITY_USER,
        );

        return self;
    }

    pub fn loadFromFile(path: [:0]const u8, priority: u32) void {
        const provider = gtk.gtk_css_provider_new();
        gtk.gtk_css_provider_load_from_path(provider, path);
        gtk.gtk_style_context_add_provider_for_display(
            gtk.gdk_display_get_default(),
            @ptrCast(provider),
            priority,
        );
    }

    pub fn loadFromString(css: [:0]const u8, priority: u32) void {
        const provider = gtk.gtk_css_provider_new();
        gtk.gtk_css_provider_load_from_data(provider, css, -1);
        gtk.gtk_style_context_add_provider_for_display(
            gtk.gdk_display_get_default(),
            @ptrCast(provider),
            priority,
        );
    }

    pub fn updateFontSizes(self: *Theme, english_size: i32, interlinear_size: i32) void {
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
        gtk.gtk_css_provider_load_from_data(self.font_provider, css, -1);
    }
};
