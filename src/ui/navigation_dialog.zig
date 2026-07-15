const std = @import("std");
const gtk = @import("../gtk.zig");
const bible = @import("../bible_db.zig");

const gpointer = gtk.gpointer;
const GtkWindow = gtk.GtkWindow;
const GtkWidget = gtk.GtkWidget;
const GtkBox = gtk.GtkBox;
const GtkLabel = gtk.GtkLabel;
const GtkButton = gtk.GtkButton;
const GtkStack = gtk.GtkStack;
const GtkFlowBox = gtk.GtkFlowBox;
const GtkScrolledWindow = gtk.GtkScrolledWindow;
const sqlite3 = bible.sqlite3;
const sqlite3_stmt = bible.sqlite3_stmt;
const BIBLE_BOOKS = bible.BIBLE_BOOKS;
const Testament = bible.Testament;
const sqlite3_prepare_v2 = bible.sqlite3_prepare_v2;
const sqlite3_step = bible.sqlite3_step;
const sqlite3_column_text = bible.sqlite3_column_text;
const sqlite3_column_int = bible.sqlite3_column_int;
const sqlite3_finalize = bible.sqlite3_finalize;
const SQLITE_ROW = bible.SQLITE_ROW;
const SQLITE_OK = bible.SQLITE_OK;

var current_dialog: ?*NavigationDialog = null;

pub const NavigationDialog = struct {
    allocator: std.mem.Allocator,
    dialog: ?*GtkWindow,
    modal_stack: ?*GtkStack,
    modal_title: ?*GtkLabel,
    cur_book_name: [64]u8,
    cur_chapter: i32,
    persistent_book_names: [150][64]u8,
    db: ?*sqlite3,
    on_navigate: *const fn (book: []const u8, chapter: i32, verse: i32) void,

    pub fn init(
        allocator: std.mem.Allocator,
        db: ?*sqlite3,
        on_navigate: *const fn (book: []const u8, chapter: i32, verse: i32) void,
    ) *NavigationDialog {
        const self = allocator.create(NavigationDialog) catch unreachable;
        self.* = .{
            .allocator = allocator,
            .dialog = null,
            .modal_stack = null,
            .modal_title = null,
            .cur_book_name = @splat(0),
            .cur_chapter = 1,
            .persistent_book_names = undefined,
            .db = db,
            .on_navigate = on_navigate,
        };
        return self;
    }

    pub fn deinit(self: *NavigationDialog) void {
        self.allocator.destroy(self);
    }

    pub fn show(self: *NavigationDialog, parent: ?*GtkWindow) void {
        if (self.dialog != null) return;
        current_dialog = self;

        self.dialog = @ptrCast(gtk.gtk_window_new());
        gtk.gtk_window_set_title(self.dialog, "Go to Passage");
        gtk.gtk_window_set_default_size(self.dialog, 900, 750);
        gtk.gtk_window_set_modal(self.dialog, true);
        gtk.gtk_window_set_transient_for(self.dialog, parent);

        const root_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 0);
        gtk.gtk_window_set_child(self.dialog, root_box);

        const header = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 15);
        gtk.gtk_widget_add_css_class(header, "nav-header");
        gtk.gtk_box_append(@ptrCast(root_box), header);

        const back_btn = gtk.gtk_button_new_with_label("Back");
        _ = gtk.g_signal_connect_data(back_btn, "clicked", @ptrCast(&NavigationDialog.onModalBackClicked), null, null, 0);
        gtk.gtk_box_append(@ptrCast(header), back_btn);

        self.modal_title = @ptrCast(gtk.gtk_label_new("<b>Select Book</b>"));
        gtk.gtk_label_set_markup(self.modal_title, "<b>Select Book</b>");
        gtk.gtk_box_append(@ptrCast(header), @ptrCast(self.modal_title));

        self.modal_stack = @ptrCast(gtk.gtk_stack_new());
        gtk.gtk_stack_set_transition_type(self.modal_stack, gtk.GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT);
        gtk.gtk_widget_set_vexpand(@ptrCast(self.modal_stack), true);
        gtk.gtk_box_append(@ptrCast(root_box), @ptrCast(self.modal_stack));

        const book_scroll = gtk.gtk_scrolled_window_new();
        gtk.gtk_widget_set_vexpand(book_scroll, true);
        const book_vbox = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 15);
        gtk.gtk_widget_add_css_class(book_vbox, "selection-grid");
        gtk.gtk_scrolled_window_set_child(@ptrCast(book_scroll), book_vbox);

        var available_books = std.StringHashMap(void).init(std.heap.page_allocator);
        defer {
            var it = available_books.keyIterator();
            while (it.next()) |key| std.heap.page_allocator.free(key.*);
            available_books.deinit();
        }
        if (self.db) |db| {
            var stmt: ?*sqlite3_stmt = null;
            if (sqlite3_prepare_v2(db, "SELECT DISTINCT book FROM verses", -1, @ptrCast(&stmt), null) == SQLITE_OK) {
                while (sqlite3_step(stmt.?) == SQLITE_ROW) {
                    const name = sqlite3_column_text(stmt.?, 0);
                    if (name) |n| {
                        const span = std.mem.span(n);
                        if (!available_books.contains(span)) {
                            const pk = std.heap.page_allocator.dupe(u8, span) catch continue;
                            available_books.put(pk, {}) catch {};
                        }
                    }
                }
                _ = sqlite3_finalize(stmt.?);
            }
        }

        const sections = [_]struct { label: [*:0]const u8, testament: Testament }{
            .{ .label = "Old Testament", .testament = .Old },
            .{ .label = "New Testament", .testament = .New },
            .{ .label = "Ethiopian Church Order", .testament = .EthiopiaExpanded },
        };

        var p_idx: usize = 0;
        for (sections) |sec| {
            const lbl = gtk.gtk_label_new(null);
            gtk.gtk_label_set_markup(@ptrCast(lbl), std.fmt.allocPrintSentinel(
                std.heap.page_allocator,
                "<span size='large' weight='bold' color='#7aa2f7'>{s}</span>",
                .{sec.label},
                0,
            ) catch "Err");
            gtk.gtk_label_set_xalign(@ptrCast(lbl), 0.0);
            gtk.gtk_box_append(@ptrCast(book_vbox), lbl);

            const flow = gtk.gtk_flow_box_new();
            gtk.gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
            gtk.gtk_box_append(@ptrCast(book_vbox), flow);

            for (BIBLE_BOOKS) |book| {
                if (book.testament != sec.testament) continue;
                const len = std.mem.len(book.name);
                @memcpy(self.persistent_book_names[p_idx][0..len], book.name[0..len]);
                self.persistent_book_names[p_idx][len] = 0;
                const p_ptr = @as(gpointer, @ptrCast(&self.persistent_book_names[p_idx]));

                const book_btn = gtk.gtk_button_new_with_label(book.name);
                if (available_books.contains(std.mem.span(book.name))) {
                    gtk.gtk_widget_add_css_class(book_btn, "cached");
                    gtk.gtk_widget_set_sensitive(book_btn, true);
                } else {
                    gtk.gtk_widget_add_css_class(book_btn, "uncached");
                    gtk.gtk_widget_set_sensitive(book_btn, false);
                }
                _ = gtk.g_signal_connect_data(book_btn, "clicked", @ptrCast(&NavigationDialog.onBookClicked), p_ptr, null, 0);
                gtk.gtk_flow_box_insert(@ptrCast(flow), book_btn, -1);
                p_idx += 1;
            }
        }

        gtk.gtk_stack_add_named(self.modal_stack, book_scroll, "books");
        gtk.gtk_window_present(self.dialog);
    }

    fn onBookClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
        _ = btn;
        const self = current_dialog orelse return;
        const book_name: [*:0]const u8 = @ptrCast(user_data);
        @memcpy(self.cur_book_name[0 .. std.mem.len(book_name) + 1], book_name[0 .. std.mem.len(book_name) + 1]);

        const allocator = std.heap.page_allocator;
        const title = std.fmt.allocPrintSentinel(allocator, "<b>{s}</b> - Select Chapter", .{book_name}, 0) catch "Select Chapter";
        defer allocator.free(title);
        gtk.gtk_label_set_markup(self.modal_title, title);

        const flow = gtk.gtk_flow_box_new();
        gtk.gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
        gtk.gtk_flow_box_set_min_children_per_line(@ptrCast(flow), 5);
        gtk.gtk_widget_add_css_class(flow, "selection-grid");
        gtk.gtk_widget_add_css_class(flow, "compact-grid");

        if (self.db) |db| {
            var stmt: ?*sqlite3_stmt = null;
            const sql = std.fmt.allocPrintSentinel(allocator, "SELECT DISTINCT chapter FROM verses WHERE book='{s}' ORDER BY chapter ASC", .{book_name}, 0) catch return;
            defer allocator.free(sql);
            if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
                while (sqlite3_step(stmt.?) == SQLITE_ROW) {
                    const ch = sqlite3_column_int(stmt.?, 0);
                    const ch_str = std.fmt.allocPrintSentinel(allocator, "{d}", .{ch}, 0) catch "1";
                    defer allocator.free(ch_str);
                    const ch_btn = gtk.gtk_button_new_with_label(ch_str);
                    _ = gtk.g_signal_connect_data(ch_btn, "clicked", @ptrCast(&NavigationDialog.onChapterClicked), @ptrFromInt(@as(usize, @intCast(ch))), null, 0);
                    gtk.gtk_flow_box_insert(@ptrCast(flow), ch_btn, -1);
                }
                _ = sqlite3_finalize(stmt.?);
            }
        }

        const scroll = gtk.gtk_scrolled_window_new();
        gtk.gtk_widget_set_vexpand(scroll, true);
        gtk.gtk_scrolled_window_set_child(@ptrCast(scroll), flow);
        if (gtk.gtk_stack_get_child_by_name(self.modal_stack, "chapters")) |old| gtk.gtk_stack_remove(self.modal_stack, old);
        gtk.gtk_stack_add_named(self.modal_stack, scroll, "chapters");
        gtk.gtk_stack_set_visible_child_name(self.modal_stack, "chapters");
    }

    fn onChapterClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
        _ = btn;
        const self = current_dialog orelse return;
        const chapter: i32 = @intCast(@intFromPtr(user_data));
        self.cur_chapter = chapter;

        const book_name = std.mem.span(@as([*:0]u8, @ptrCast(&self.cur_book_name)));
        const allocator = std.heap.page_allocator;
        const title = std.fmt.allocPrintSentinel(allocator, "<b>{s} {d}</b> - Select Verse", .{ book_name, chapter }, 0) catch "Select Verse";
        defer allocator.free(title);
        gtk.gtk_label_set_markup(self.modal_title, title);

        const flow = gtk.gtk_flow_box_new();
        gtk.gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
        gtk.gtk_flow_box_set_min_children_per_line(@ptrCast(flow), 5);
        gtk.gtk_widget_add_css_class(flow, "selection-grid");
        gtk.gtk_widget_add_css_class(flow, "compact-grid");

        if (self.db) |db| {
            var stmt: ?*sqlite3_stmt = null;
            const sql = std.fmt.allocPrintSentinel(allocator, "SELECT DISTINCT verse FROM verses WHERE book='{s}' AND chapter={d} ORDER BY verse ASC", .{ book_name, chapter }, 0) catch return;
            defer allocator.free(sql);
            if (sqlite3_prepare_v2(db, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
                while (sqlite3_step(stmt.?) == SQLITE_ROW) {
                    const v = sqlite3_column_int(stmt.?, 0);
                    const v_str = std.fmt.allocPrintSentinel(allocator, "{d}", .{v}, 0) catch "1";
                    defer allocator.free(v_str);
                    const v_btn = gtk.gtk_button_new_with_label(v_str);
                    _ = gtk.g_signal_connect_data(v_btn, "clicked", @ptrCast(&NavigationDialog.onVerseClicked), @ptrFromInt(@as(usize, @intCast(v))), null, 0);
                    gtk.gtk_flow_box_insert(@ptrCast(flow), v_btn, -1);
                }
                _ = sqlite3_finalize(stmt.?);
            }
        }

        const scroll = gtk.gtk_scrolled_window_new();
        gtk.gtk_widget_set_vexpand(scroll, true);
        gtk.gtk_scrolled_window_set_child(@ptrCast(scroll), flow);
        if (gtk.gtk_stack_get_child_by_name(self.modal_stack, "verses")) |old| gtk.gtk_stack_remove(self.modal_stack, old);
        gtk.gtk_stack_add_named(self.modal_stack, scroll, "verses");
        gtk.gtk_stack_set_visible_child_name(self.modal_stack, "verses");
    }

    fn onVerseClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
        _ = btn;
        const self = current_dialog orelse return;
        const book_name = std.mem.span(@as([*:0]u8, @ptrCast(&self.cur_book_name)));
        self.on_navigate(book_name, self.cur_chapter, @intCast(@intFromPtr(user_data)));
        gtk.gtk_window_destroy(self.dialog);
        self.dialog = null;
        current_dialog = null;
    }

    fn onModalBackClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
        _ = btn;
        _ = user_data;
        const self = current_dialog orelse return;
        const current = gtk.gtk_stack_get_visible_child_name(self.modal_stack);
        if (current == null) return;
        const allocator = std.heap.page_allocator;
        if (std.mem.orderZ(u8, current.?, "verses") == .eq) {
            gtk.gtk_stack_set_visible_child_name(self.modal_stack, "chapters");
            const book_name = std.mem.span(@as([*:0]u8, @ptrCast(&self.cur_book_name)));
            const title = std.fmt.allocPrintSentinel(allocator, "<b>{s}</b> - Select Chapter", .{book_name}, 0) catch "Select Chapter";
            defer allocator.free(title);
            gtk.gtk_label_set_markup(self.modal_title, title);
        } else if (std.mem.orderZ(u8, current.?, "chapters") == .eq) {
            gtk.gtk_stack_set_visible_child_name(self.modal_stack, "books");
            gtk.gtk_label_set_markup(self.modal_title, "<b>Select Book</b>");
        }
    }
};
