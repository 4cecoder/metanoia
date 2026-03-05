const std = @import("std");
const gtk = @import("../../gtk.zig");

const GtkWidget = gtk.GtkWidget;
const GtkBox = gtk.GtkBox;
const gpointer = gtk.gpointer;

pub const Header = struct {
    box: ?*GtkWidget,
    allocator: std.mem.Allocator,
    
    pub const Callbacks = struct {
        onSearch: *const fn (?*gtk.GtkButton, gpointer) callconv(.c) void,
        onSettings: *const fn (?*gtk.GtkButton, gpointer) callconv(.c) void,
        onPrev: *const fn (?*gtk.GtkButton, gpointer) callconv(.c) void,
        onNext: *const fn (?*gtk.GtkButton, gpointer) callconv(.c) void,
        onParallel: *const fn (?*gtk.GtkButton, gpointer) callconv(.c) void,
        onPassage: *const fn (?*gtk.GtkButton, gpointer) callconv(.c) void,
        onSidebar: *const fn (?*gtk.GtkButton, gpointer) callconv(.c) void,
    };

    pub fn init(allocator: std.mem.Allocator, callbacks: Callbacks) *Header {
        const self = allocator.create(Header) catch unreachable;
        
        const top_bar = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 12);
        gtk.gtk_widget_add_css_class(top_bar, "headerbar");

        self.* = .{
            .box = top_bar,
            .allocator = allocator,
        };

        // 1. Sidebar Toggle
        const toggle = gtk.gtk_button_new_with_label("≡");
        _ = gtk.g_signal_connect_data(toggle, "clicked", @ptrCast(callbacks.onSidebar), null, null, 0);
        gtk.gtk_box_append(@ptrCast(top_bar), toggle);

        // 2. Search Trigger
        const search = gtk.gtk_button_new_with_label("Search Scripture... (⌘K)");
        gtk.gtk_widget_set_hexpand(search, true);
        gtk.gtk_widget_add_css_class(search, "search-trigger-btn");
        _ = gtk.g_signal_connect_data(search, "clicked", @ptrCast(callbacks.onSearch), null, null, 0);
        gtk.gtk_box_append(@ptrCast(top_bar), search);

        // 3. Navigation
        const prev = gtk.gtk_button_new_with_label("<");
        _ = gtk.g_signal_connect_data(prev, "clicked", @ptrCast(callbacks.onPrev), null, null, 0);
        gtk.gtk_box_append(@ptrCast(top_bar), prev);

        const next = gtk.gtk_button_new_with_label(">");
        _ = gtk.g_signal_connect_data(next, "clicked", @ptrCast(callbacks.onNext), null, null, 0);
        gtk.gtk_box_append(@ptrCast(top_bar), next);

        // 4. Tools
        const parallel = gtk.gtk_button_new_with_label("Parallel");
        _ = gtk.g_signal_connect_data(parallel, "clicked", @ptrCast(callbacks.onParallel), null, null, 0);
        gtk.gtk_box_append(@ptrCast(top_bar), parallel);

        const passage = gtk.gtk_button_new_with_label("Passage");
        gtk.gtk_widget_add_css_class(passage, "suggested-action");
        _ = gtk.g_signal_connect_data(passage, "clicked", @ptrCast(callbacks.onPassage), null, null, 0);
        gtk.gtk_box_append(@ptrCast(top_bar), passage);

        const settings = gtk.gtk_button_new_with_label("⚙️");
        _ = gtk.g_signal_connect_data(settings, "clicked", @ptrCast(callbacks.onSettings), null, null, 0);
        gtk.gtk_box_append(@ptrCast(top_bar), settings);

        return self;
    }
};
