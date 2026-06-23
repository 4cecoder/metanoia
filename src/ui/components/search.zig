const std = @import("std");
const gtk = @import("../../gtk.zig");
const bible = @import("../../bible_db.zig");

const GtkWidget = gtk.GtkWidget;
const GtkWindow = gtk.GtkWindow;
const gpointer = gtk.gpointer;

pub const SearchCallbacks = struct {
    onNavigate: *const fn (book: []const u8, chapter: i32, verse: i32) void,
    onStatus: *const fn (msg: []const u8, is_error: bool) void,
};

const ResultData = struct {
    search: *Search,
    book: [64]u8,
    chapter: i32,
    verse: i32,
};

pub const Search = struct {
    window: ?*GtkWindow,
    entry: ?*GtkWidget,
    results_list: ?*GtkWidget,
    allocator: std.mem.Allocator,
    db: ?*bible.sqlite3,
    callbacks: SearchCallbacks,
    parent_window: ?*GtkWindow,

    pub fn init(allocator: std.mem.Allocator, parent_window: ?*GtkWindow, db: ?*bible.sqlite3, callbacks: SearchCallbacks) *Search {
        const self = allocator.create(Search) catch unreachable;
        self.* = .{
            .window = null,
            .entry = null,
            .results_list = null,
            .allocator = allocator,
            .db = db,
            .callbacks = callbacks,
            .parent_window = parent_window,
        };

        const window = @as(?*GtkWindow, @ptrCast(gtk.gtk_window_new()));
        gtk.gtk_window_set_transient_for(window, parent_window);
        gtk.gtk_window_set_modal(window, false);
        gtk.gtk_window_set_decorated(window, false);
        gtk.gtk_window_set_resizable(window, false);
        gtk.gtk_window_set_default_size(window, 700, 500);
        gtk.gtk_widget_add_css_class(@ptrCast(window), "spotlight-window");
        self.window = window;

        _ = gtk.g_signal_connect_data(window, "close-request", @ptrCast(&on_close_request), self, null, 0);
        _ = gtk.g_signal_connect_data(window, "notify::is-active", @ptrCast(&on_window_active_changed), self, null, 0);

        const vbox = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 0);
        gtk.gtk_window_set_child(window, vbox);

        const entry = gtk.gtk_search_entry_new();
        gtk.gtk_widget_add_css_class(entry, "spotlight-entry");
        gtk.gtk_box_append(@ptrCast(vbox), entry);
        self.entry = entry;

        _ = gtk.g_signal_connect_data(entry, "activate", @ptrCast(&on_activated), self, null, 0);
        _ = gtk.g_signal_connect_data(entry, "search-changed", @ptrCast(&on_changed), self, null, 0);

        const scroll = gtk.gtk_scrolled_window_new();
        gtk.gtk_widget_set_vexpand(scroll, true);
        gtk.gtk_box_append(@ptrCast(vbox), scroll);

        const list = gtk.gtk_list_box_new();
        gtk.gtk_widget_add_css_class(list, "spotlight-results");
        gtk.gtk_list_box_set_selection_mode(list, 0);
        gtk.gtk_scrolled_window_set_child(@ptrCast(scroll), list);
        self.results_list = list;

        const key_ctrl = gtk.gtk_event_controller_key_new();
        _ = gtk.g_signal_connect_data(key_ctrl, "key-pressed", @ptrCast(&on_key_pressed), self, null, 0);
        gtk.gtk_widget_add_controller(@ptrCast(window), key_ctrl);

        return self;
    }

    pub fn show(self: *Search) void {
        if (self.window) |win| {
            gtk.gtk_window_present(win);
            if (self.entry) |e| {
                gtk.gtk_editable_set_text(e, "");
                _ = gtk.gtk_widget_grab_focus(e);
            }
            if (self.results_list) |list| {
                gtk.gtk_list_box_remove_all(list);
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
        const allocator = self.allocator;

        {
            const msg = std.fmt.allocPrint(allocator, "Searching for '{s}'...", .{span}) catch "Searching...";
            self.callbacks.onStatus(msg, false);
            if (!std.mem.eql(u8, msg, "Searching...")) allocator.free(msg);
        }

        if (self.results_list) |list| gtk.gtk_list_box_remove_all(list);
        var total_results: usize = 0;

        // 1. Try Reference Parsing (e.g. "John 3:16", "Gen 1:1")
        var it = std.mem.tokenizeAny(u8, span, " :");
        var parts = std.ArrayListUnmanaged([]const u8).empty;
        defer parts.deinit(allocator);
        while (it.next()) |p| parts.append(allocator, p) catch {};

        if (parts.items.len >= 2) {
            var book_end_idx: usize = 0;
            var chapter: ?i32 = null;
            var verse: ?i32 = null;

            for (parts.items, 0..) |part, i| {
                const val = std.fmt.parseInt(i32, part, 10) catch {
                    if (chapter == null) book_end_idx = i + 1;
                    continue;
                };
                if (i == 0 and (val >= 1 and val <= 3)) {
                    book_end_idx = 1;
                    continue;
                }
                if (chapter == null) {
                    chapter = val;
                } else if (verse == null) {
                    verse = val;
                }
            }

            if (book_end_idx > 0 and chapter != null) {
                const book_query = std.mem.join(allocator, "", parts.items[0..book_end_idx]) catch "";
                defer allocator.free(book_query);

                var resolved_book: ?[]const u8 = null;
                for (bible.BIBLE_ABBREVIATIONS) |abbr| {
                    if (std.ascii.eqlIgnoreCase(abbr.abbr, book_query)) {
                        resolved_book = abbr.full;
                        break;
                    }
                }
                if (resolved_book == null) {
                    for (bible.BIBLE_BOOKS) |b| {
                        const b_name = std.mem.span(b.name);
                        var clean_b = std.ArrayListUnmanaged(u8).empty;
                        defer clean_b.deinit(allocator);
                        for (b_name) |c| if (c != ' ') clean_b.append(allocator, c) catch {};
                        if (std.ascii.eqlIgnoreCase(clean_b.items, book_query)) {
                            resolved_book = b_name;
                            break;
                        }
                    }
                }

                if (resolved_book) |rb| {
                    const label_text = std.fmt.allocPrintSentinel(allocator, "<b>Go to: {s} {d}:{d}</b>", .{ rb, chapter.?, verse orelse 1 }, 0) catch "Err";
                    defer allocator.free(label_text);

                    const rd = allocator.create(ResultData) catch null;
                    if (rd) |data| {
                        @memset(&data.book, 0);
                        @memcpy(data.book[0..rb.len], rb);
                        data.chapter = chapter.?;
                        data.verse = verse orelse 1;
                        data.search = self;

                        const row_btn = gtk.gtk_button_new_with_label("");
                        const lbl = gtk.gtk_label_new(null);
                        gtk.gtk_label_set_markup(@ptrCast(lbl), label_text);
                        gtk.gtk_button_set_child(@ptrCast(row_btn), lbl);
                        _ = gtk.g_signal_connect_data(row_btn, "clicked", @ptrCast(&on_result_clicked), data, null, 0);
                        gtk.gtk_list_box_append(self.results_list, row_btn);
                        total_results += 1;
                    }
                }
            }
        }

        // 2. Keyword Search via SQL LIKE
        const sql = std.fmt.allocPrintSentinel(allocator, "SELECT book, chapter, verse, text FROM verses WHERE text LIKE '%{s}%' LIMIT 40", .{span}, 0) catch {
            self.callbacks.onStatus("Search failed", true);
            return;
        };
        defer allocator.free(sql);

        var stmt: ?*bible.sqlite3_stmt = null;
        if (bible.sqlite3_prepare_v2(self.db.?, sql, -1, @ptrCast(&stmt), null) == bible.SQLITE_OK) {
            var count: usize = 0;
            while (bible.sqlite3_step(stmt.?) == bible.SQLITE_ROW and count < 40) {
                const b = bible.sqlite3_column_text(stmt.?, 0);
                const c = bible.sqlite3_column_int(stmt.?, 1);
                const v = bible.sqlite3_column_int(stmt.?, 2);
                const t = bible.sqlite3_column_text(stmt.?, 3);

                const b_span = std.mem.span(b.?);
                const text_span = std.mem.span(t.?);

                // Highlight matches with <span> tags
                var highlighted = std.ArrayListUnmanaged(u8).empty;
                defer highlighted.deinit(allocator);
                var last: usize = 0;
                var search_idx: usize = 0;
                while (std.ascii.findIgnoreCase(text_span[search_idx..], span)) |match_idx| {
                    const start = search_idx + match_idx;
                    highlighted.appendSlice(allocator, text_span[last..start]) catch {};
                    highlighted.appendSlice(allocator, "<span color='#7dcfff' weight='bold'>") catch {};
                    highlighted.appendSlice(allocator, text_span[start..start + span.len]) catch {};
                    highlighted.appendSlice(allocator, "</span>") catch {};
                    last = start + span.len;
                    search_idx = last;
                    if (search_idx >= text_span.len) break;
                }
                highlighted.appendSlice(allocator, text_span[last..]) catch {};

                const label_text = std.fmt.allocPrintSentinel(allocator, "<b>{s} {d}:{d}</b> - {s}", .{ b.?, c, v, highlighted.items }, 0) catch "Err";
                defer allocator.free(label_text);

                const rd = allocator.create(ResultData) catch null;
                if (rd) |data| {
                    @memset(&data.book, 0);
                    @memcpy(data.book[0..b_span.len], b_span);
                    data.chapter = c;
                    data.verse = v;
                    data.search = self;

                    const row_btn = gtk.gtk_button_new_with_label("");
                    const lbl = gtk.gtk_label_new(null);
                    gtk.gtk_label_set_markup(@ptrCast(lbl), label_text);
                    gtk.gtk_label_set_xalign(@ptrCast(lbl), 0.0);
                    gtk.gtk_label_set_wrap(@ptrCast(lbl), true);
                    gtk.gtk_button_set_child(@ptrCast(row_btn), lbl);

                    _ = gtk.g_signal_connect_data(row_btn, "clicked", @ptrCast(&on_result_clicked), data, null, 0);
                    gtk.gtk_list_box_append(self.results_list, row_btn);
                    count += 1;
                    total_results += 1;
                }
            }
            _ = bible.sqlite3_finalize(stmt.?);
        }

        {
            if (total_results > 0) {
                const found_msg = std.fmt.allocPrint(allocator, "Found {d} results", .{total_results}) catch "Found results";
                self.callbacks.onStatus(found_msg, false);
                if (!std.mem.eql(u8, found_msg, "Found results")) allocator.free(found_msg);
            } else {
                self.callbacks.onStatus("No results found", false);
            }
        }
    }

    fn on_changed(entry: ?*anyopaque, user_data: gpointer) callconv(.c) void {
        const self: *Search = @ptrCast(@alignCast(user_data));
        const text = gtk.gtk_editable_get_text(entry);
        const span = std.mem.span(text);
        if (span.len >= 3) {
            self.performSearch(span);
        } else if (span.len == 0) {
            if (self.results_list) |list| gtk.gtk_list_box_remove_all(list);
        }
    }

    fn on_activated(entry: ?*anyopaque, user_data: gpointer) callconv(.c) void {
        const self: *Search = @ptrCast(@alignCast(user_data));
        const text = gtk.gtk_editable_get_text(entry);
        self.performSearch(std.mem.span(text));

        if (self.results_list) |list| {
            if (gtk.gtk_widget_get_first_child(@ptrCast(list))) |row| {
                if (gtk.gtk_widget_get_first_child(row)) |btn| {
                    gtk.g_signal_emit_by_name(btn, "clicked");
                }
            }
        }
    }

    fn on_result_clicked(btn: ?*gtk.GtkButton, user_data: gpointer) callconv(.c) void {
        _ = btn;
        const data: *ResultData = @ptrCast(@alignCast(user_data));
        const book = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&data.book)), 0);
        data.search.callbacks.onNavigate(book, data.chapter, data.verse);
        if (data.search.window) |w| gtk.gtk_widget_set_visible(@ptrCast(w), false);
    }

    fn on_close_request(win: ?*anyopaque, user_data: gpointer) callconv(.c) bool {
        _ = win;
        const self: *Search = @ptrCast(@alignCast(user_data));
        if (self.window) |w| gtk.gtk_widget_set_visible(@ptrCast(w), false);
        return true;
    }

    fn on_key_pressed(ctrl: ?*anyopaque, keyval: u32, keycode: u32, state: u32, user_data: gpointer) callconv(.c) bool {
        _ = ctrl;
        _ = keycode;
        _ = state;
        const self: *Search = @ptrCast(@alignCast(user_data));
        if (keyval == 0xff1b) {
            if (self.window) |w| gtk.gtk_widget_set_visible(@ptrCast(w), false);
            return true;
        }
        return false;
    }

    fn on_window_active_changed(window: ?*anyopaque, pspec: ?*anyopaque, user_data: gpointer) callconv(.c) void {
        _ = pspec;
        const self: *Search = @ptrCast(@alignCast(user_data));
        if (self.window) |w| {
            if (!gtk.gtk_window_is_active(w) and gtk.gtk_widget_get_visible(@ptrCast(w))) {
                _ = gtk.g_idle_add(&hide_idle, self);
            }
        }
        _ = window;
    }

    fn hide_idle(data: gpointer) callconv(.c) bool {
        const self: *Search = @ptrCast(@alignCast(data));
        if (self.window) |w| gtk.gtk_widget_set_visible(@ptrCast(w), false);
        return false;
    }
};
