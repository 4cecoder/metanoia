//! Spotlight-style search window with generic callback interface.
//!
//! The component provides the window, entry, results list, and keyboard
//! handling. Search logic is injected via `SearchCallbacks`, which contains
//! a `performSearch` callback. This decouples the component from any
//! specific database or search implementation.

const std = @import("std");
const ffi = @import("../ffi.zig");
const text = @import("../util/text.zig");
const Signal = @import("../signal.zig").Signal;

/// A single search result to display.
pub const SearchResult = struct {
    book: [64]u8 = @splat(0),
    chapter: i32 = 0,
    verse: i32 = 0,
    title: ?[:0]const u8 = null,
    highlighted: ?[:0]const u8 = null,
};

/// Callback interface for the search window.
pub const SearchCallbacks = struct {
    /// Called when the user selects a result. Receives the book name,
    /// chapter, and verse from the selected `SearchResult`.
    onNavigate: *const fn (book: []const u8, chapter: i32, verse: i32) void,

    /// Called to update the status bar. `msg` is the message string;
    /// `is_error` indicates whether it's an error message.
    onStatus: *const fn (msg: []const u8, is_error: bool) void,

    /// Called to perform the actual search. `query` is the search text.
    /// The callback should append results to `results` and return the
    /// number of matches found. Return 0 for no matches.
    performSearch: *const fn (
        allocator: std.mem.Allocator,
        query: []const u8,
        results: *std.ArrayListUnmanaged(SearchResult),
    ) usize,
};

const ResultData = struct {
    search: *Search,
    result: SearchResult,
};

pub const Search = struct {
    window: ?*ffi.GtkWindow,
    entry: ?*ffi.GtkWidget,
    results_list: ?*ffi.GtkWidget,
    allocator: std.mem.Allocator,
    callbacks: SearchCallbacks,
    parent_window: ?*ffi.GtkWindow,

    pub fn init(
        allocator: std.mem.Allocator,
        parent_window: ?*ffi.GtkWindow,
        callbacks: SearchCallbacks,
    ) *Search {
        const self = allocator.create(Search) catch unreachable;
        self.* = .{
            .window = null,
            .entry = null,
            .results_list = null,
            .allocator = allocator,
            .callbacks = callbacks,
            .parent_window = parent_window,
        };

        const window: ?*ffi.GtkWindow = @ptrCast(ffi.gtk_window_new());
        ffi.gtk_window_set_transient_for(window, parent_window);
        ffi.gtk_window_set_modal(window, false);
        ffi.gtk_window_set_decorated(window, false);
        ffi.gtk_window_set_resizable(window, false);
        ffi.gtk_window_set_default_size(window, 700, 500);
        ffi.gtk_widget_add_css_class(@ptrCast(window), "spotlight-window");
        self.window = window;

        _ = Signal.connect(window, "close-request", @ptrCast(&on_close_request), self, null);
        _ = Signal.connect(window, "notify::is-active", @ptrCast(&on_window_active_changed), self, null);

        const vbox = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 0);
        ffi.gtk_window_set_child(window, vbox);

        const entry = ffi.gtk_search_entry_new();
        ffi.gtk_widget_add_css_class(entry, "spotlight-entry");
        ffi.gtk_box_append(@ptrCast(vbox), entry);
        self.entry = entry;

        _ = Signal.connect(entry, "activate", @ptrCast(&on_activated), self, null);
        _ = Signal.connect(entry, "search-changed", @ptrCast(&on_changed), self, null);

        const scroll = ffi.gtk_scrolled_window_new();
        ffi.gtk_widget_set_vexpand(scroll, true);
        ffi.gtk_box_append(@ptrCast(vbox), scroll);

        const list = ffi.gtk_list_box_new();
        ffi.gtk_widget_add_css_class(list, "spotlight-results");
        ffi.gtk_list_box_set_selection_mode(list, 0);
        ffi.gtk_scrolled_window_set_child(@ptrCast(scroll), list);
        self.results_list = list;

        const key_ctrl = ffi.gtk_event_controller_key_new();
        _ = Signal.connect(key_ctrl, "key-pressed", @ptrCast(&on_key_pressed), self, null);
        ffi.gtk_widget_add_controller(@ptrCast(window), key_ctrl);

        return self;
    }

    pub fn deinit(self: *Search) void {
        self.allocator.destroy(self);
    }

    pub fn show(self: *Search) void {
        if (self.window) |win| {
            ffi.gtk_window_present(win);
            if (self.entry) |e| {
                ffi.gtk_editable_set_text(e, "");
                _ = ffi.gtk_widget_grab_focus(e);
            }
            if (self.results_list) |list| {
                ffi.gtk_list_box_remove_all(list);
            }
        }
    }

    pub fn handleKeyPress(keyval: u32, search: *Search) bool {
        const GDK_KEY_k = 107;
        const GDK_KEY_K = 75;
        const GDK_KEY_f = 102;
        const GDK_KEY_F = 70;

        if (keyval == GDK_KEY_k or keyval == GDK_KEY_K or keyval == GDK_KEY_f or keyval == GDK_KEY_F) {
            search.show();
            return true;
        }
        return false;
    }

    fn performSearch(self: *Search, span: []const u8) void {
        if (span.len < 2) return;

        {
            const msg = std.fmt.allocPrint(self.allocator, "Searching for '{s}'...", .{span}) catch "Searching...";
            self.callbacks.onStatus(msg, false);
            if (!std.mem.eql(u8, msg, "Searching...")) self.allocator.free(msg);
        }

        if (self.results_list) |list| ffi.gtk_list_box_remove_all(list);

        var results = std.ArrayListUnmanaged(SearchResult).empty;
        defer {
            for (results.items) |r| {
                if (r.title) |t| self.allocator.free(t);
                if (r.highlighted) |h| self.allocator.free(h);
            }
            results.deinit(self.allocator);
        }

        const total_results = self.callbacks.performSearch(self.allocator, span, &results);

        for (results.items) |*result| {
            const rd = self.allocator.create(ResultData) catch continue;
            // Transfer ownership — null out originals so defer doesn't double-free
            const owned_title = result.title orelse null;
            const owned_hl = result.highlighted orelse null;
            result.title = null;
            result.highlighted = null;
            rd.* = .{
                .search = self,
                .result = .{ .book = result.book, .chapter = result.chapter, .verse = result.verse, .title = owned_title, .highlighted = owned_hl },
            };

            const row_btn = ffi.gtk_button_new_with_label("");
            const lbl = ffi.gtk_label_new(null);
            if (owned_hl) |hl| {
                ffi.gtk_label_set_markup(@ptrCast(lbl), hl);
            } else if (owned_title) |t| {
                ffi.gtk_label_set_markup(@ptrCast(lbl), t);
            }
            ffi.gtk_label_set_xalign(@ptrCast(lbl), 0.0);
            ffi.gtk_label_set_wrap(@ptrCast(lbl), true);
            ffi.gtk_button_set_child(@ptrCast(row_btn), lbl);

            const DestroyRD = struct {
                fn destroy(data: ffi.gpointer, _: ?*anyopaque) callconv(.c) void {
                    const ctx: *ResultData = @ptrCast(@alignCast(data));
                    if (ctx.result.title) |t| ctx.search.allocator.free(t);
                    if (ctx.result.highlighted) |h| ctx.search.allocator.free(h);
                    ctx.search.allocator.destroy(ctx);
                }
            };
            _ = Signal.connect(row_btn, "clicked", @ptrCast(&on_result_clicked), rd, DestroyRD.destroy);
            ffi.gtk_list_box_append(self.results_list, row_btn);
        }

        if (total_results > 0) {
            const found_msg = std.fmt.allocPrint(self.allocator, "Found {d} results", .{total_results}) catch "Found results";
            self.callbacks.onStatus(found_msg, false);
            if (!std.mem.eql(u8, found_msg, "Found results")) self.allocator.free(found_msg);
        } else {
            self.callbacks.onStatus("No results found", false);
        }
    }

    fn on_changed(entry: ?*anyopaque, user_data: ffi.gpointer) callconv(.c) void {
        const self: *Search = @ptrCast(@alignCast(user_data));
        const text_val = ffi.gtk_editable_get_text(entry);
        const span = std.mem.span(text_val);
        if (span.len >= 3) {
            self.performSearch(span);
        } else if (span.len == 0) {
            if (self.results_list) |list| ffi.gtk_list_box_remove_all(list);
        }
    }

    fn on_activated(entry: ?*anyopaque, user_data: ffi.gpointer) callconv(.c) void {
        const self: *Search = @ptrCast(@alignCast(user_data));
        const text_val = ffi.gtk_editable_get_text(entry);
        self.performSearch(std.mem.span(text_val));

        if (self.results_list) |list| {
            if (ffi.gtk_widget_get_first_child(@ptrCast(list))) |row| {
                if (ffi.gtk_widget_get_first_child(row)) |btn| {
                    ffi.g_signal_emit_by_name(btn, "clicked");
                }
            }
        }
    }

    fn on_result_clicked(btn: ?*ffi.GtkButton, user_data: ffi.gpointer) callconv(.c) void {
        _ = btn;
        const data: *ResultData = @ptrCast(@alignCast(user_data));
        const book = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&data.result.book)), 0);
        data.search.callbacks.onNavigate(book, data.result.chapter, data.result.verse);
        if (data.search.window) |w| ffi.gtk_widget_set_visible(@ptrCast(w), false);
    }

    fn on_close_request(win: ?*anyopaque, user_data: ffi.gpointer) callconv(.c) bool {
        _ = win;
        const self: *Search = @ptrCast(@alignCast(user_data));
        if (self.window) |w| ffi.gtk_widget_set_visible(@ptrCast(w), false);
        return true;
    }

    fn on_key_pressed(ctrl: ?*anyopaque, keyval: u32, keycode: u32, state: u32, user_data: ffi.gpointer) callconv(.c) bool {
        _ = ctrl;
        _ = keycode;
        _ = state;
        const self: *Search = @ptrCast(@alignCast(user_data));
        if (keyval == 0xff1b) {
            if (self.window) |w| ffi.gtk_widget_set_visible(@ptrCast(w), false);
            return true;
        }
        return false;
    }

    fn on_window_active_changed(window: ?*anyopaque, pspec: ?*anyopaque, user_data: ffi.gpointer) callconv(.c) void {
        _ = pspec;
        const self: *Search = @ptrCast(@alignCast(user_data));
        if (self.window) |w| {
            if (!ffi.gtk_window_is_active(w) and ffi.gtk_widget_get_visible(@ptrCast(w))) {
                _ = ffi.g_idle_add(&hide_idle, self);
            }
        }
        _ = window;
    }

    fn hide_idle(data: ffi.gpointer) callconv(.c) bool {
        const self: *Search = @ptrCast(@alignCast(data));
        if (self.window) |w| ffi.gtk_widget_set_visible(@ptrCast(w), false);
        return false;
    }
};
