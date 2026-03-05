const std = @import("std");
const gtk = @import("../../gtk.zig");
const bible = @import("../../bible_db.zig");

const GtkWidget = gtk.GtkWidget;
const GtkBox = gtk.GtkBox;
const GtkScrolledWindow = gtk.GtkScrolledWindow;
const GtkLabel = gtk.GtkLabel;
const GtkFlowBox = gtk.GtkFlowBox;
const gpointer = gtk.gpointer;

pub const Reader = struct {
    box: ?*GtkWidget,
    left_view: ?*GtkBox,
    right_view: ?*GtkBox,
    left_scroll: ?*GtkScrolledWindow,
    right_scroll: ?*GtkScrolledWindow,
    
    db: ?*bible.sqlite3,
    allocator: std.mem.Allocator,
    
    // Callbacks for interactivity
    onVerseDoubleClick: *const fn (idx: usize) void,
    onVerseRightClick: *const fn (idx: usize) void,
    onVerseLongPress: *const fn (idx: usize) void,
    onWordClick: *const fn (strongs: [*:0]const u8) void,

    pub fn init(allocator: std.mem.Allocator, db: ?*bible.sqlite3, callbacks: anytype) *Reader {
        const self = allocator.create(Reader) catch unreachable;
        
        const paned = gtk.gtk_paned_new(gtk.GTK_ORIENTATION_HORIZONTAL);
        
        const left_scroll = @as(?*GtkScrolledWindow, @ptrCast(gtk.gtk_scrolled_window_new()));
        const left_view = @as(?*GtkBox, @ptrCast(gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 24)));
        gtk.gtk_widget_set_name(@ptrCast(left_view), "left_view");
        gtk.gtk_scrolled_window_set_child(left_scroll, @ptrCast(left_view));
        gtk.gtk_paned_set_start_child(@ptrCast(paned), @ptrCast(left_scroll));

        const right_scroll = @as(?*GtkScrolledWindow, @ptrCast(gtk.gtk_scrolled_window_new()));
        const right_view = @as(?*GtkBox, @ptrCast(gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 24)));
        gtk.gtk_widget_set_name(@ptrCast(right_view), "right_view");
        gtk.gtk_scrolled_window_set_child(right_scroll, @ptrCast(right_view));
        gtk.gtk_paned_set_end_child(@ptrCast(paned), @ptrCast(right_scroll));
        gtk.gtk_widget_set_visible(@ptrCast(right_scroll), false);

        self.* = .{
            .box = paned,
            .left_view = left_view,
            .right_view = right_view,
            .left_scroll = left_scroll,
            .right_scroll = right_scroll,
            .db = db,
            .allocator = allocator,
            .onVerseDoubleClick = callbacks.onVerseDoubleClick,
            .onVerseRightClick = callbacks.onVerseRightClick,
            .onVerseLongPress = callbacks.onVerseLongPress,
            .onWordClick = callbacks.onWordClick,
        };

        // Sync Scrolling
        const left_adj = gtk.gtk_scrolled_window_get_vadjustment(left_scroll);
        const right_adj = gtk.gtk_scrolled_window_get_vadjustment(right_scroll);
        _ = gtk.g_signal_connect_data(left_adj, "value-changed", @ptrCast(&on_scroll_changed), right_adj, null, 0);
        _ = gtk.g_signal_connect_data(right_adj, "value-changed", @ptrCast(&on_scroll_changed), left_adj, null, 0);

        return self;
    }

    pub fn loadChapter(self: *Reader, book: []const u8, chapter: i32, start_verse: i32, highlights: std.AutoHashMapUnmanaged(i32, []const u8)) void {
        const sql = std.fmt.allocPrintSentinel(self.allocator, "SELECT verse, text FROM verses WHERE book='{s}' AND chapter={d} ORDER BY verse ASC", .{ book, chapter }, 0) catch return;
        defer self.allocator.free(sql);
        
        var stmt: ?*bible.sqlite3_stmt = null;
        if (bible.sqlite3_prepare_v2(self.db.?, sql, -1, @ptrCast(&stmt), null) == bible.SQLITE_OK) {
            self.clearViews();
            
            const title_text = std.fmt.allocPrintSentinel(self.allocator, "{s} {d}", .{ book, chapter }, 0) catch "Error";
            const title = gtk.gtk_label_new(null);
            gtk.gtk_label_set_markup(@ptrCast(title), title_text);
            gtk.gtk_widget_set_name(title, "chapter_title");
            gtk.gtk_label_set_xalign(@ptrCast(title), 0.5);
            gtk.gtk_box_append(self.left_view, title);

            var idx: usize = 0;
            while (bible.sqlite3_step(stmt.?) == bible.SQLITE_ROW) : (idx += 1) {
                const verse_num = bible.sqlite3_column_int(stmt.?, 0);
                const text = bible.sqlite3_column_text(stmt.?, 1);
                
                const v_num_color = if (verse_num == start_verse) "#e0af68" else "#7aa2f7";
                const bg_color = highlights.get(verse_num);

                var markup: [:0]u8 = undefined;
                if (bg_color) |bg| {
                    markup = std.fmt.allocPrintSentinel(self.allocator, "<span background='{s}'><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='{s}'>{d}</span> {s}</span>", .{ bg, v_num_color, verse_num, text.? }, 0) catch @constCast("Error");
                } else {
                    markup = std.fmt.allocPrintSentinel(self.allocator, "<span><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='{s}'>{d}</span> {s}</span>", .{ v_num_color, verse_num, text.? }, 0) catch @constCast("Error");
                }
                
                const lbl = gtk.gtk_label_new(null);
                gtk.gtk_label_set_markup(@ptrCast(lbl), markup.ptr);
                gtk.gtk_widget_add_css_class(@ptrCast(lbl), "verse-label");
                gtk.gtk_label_set_wrap(@ptrCast(lbl), true);
                gtk.gtk_label_set_xalign(@ptrCast(lbl), 0.0);
                gtk.gtk_box_append(self.left_view, lbl);
                self.allocator.free(markup);

                // Gestures
                self.addGestures(lbl, idx);

                // Interlinear
                self.renderInterlinear(book, chapter, verse_num);
            }
            _ = bible.sqlite3_finalize(stmt.?);
        }
    }

    fn renderInterlinear(self: *Reader, book: []const u8, chapter: i32, verse: i32) void {
        const flow = gtk.gtk_flow_box_new();
        gtk.gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
        
        // RTL check
        const strongs_sql = std.fmt.allocPrintSentinel(self.allocator, "SELECT strongs FROM interlinear WHERE book='{s}' AND chapter={d} AND verse={d} LIMIT 1", .{ book, chapter, verse }, 0) catch return;
        defer self.allocator.free(strongs_sql);
        var s_stmt: ?*bible.sqlite3_stmt = null;
        if (bible.sqlite3_prepare_v2(self.db.?, strongs_sql, -1, @ptrCast(&s_stmt), null) == bible.SQLITE_OK) {
            if (bible.sqlite3_step(s_stmt.?) == bible.SQLITE_ROW) {
                const s_txt = bible.sqlite3_column_text(s_stmt.?, 0) orelse "";
                if (std.mem.span(s_txt).len > 0 and std.mem.span(s_txt)[0] == 'H') gtk.gtk_widget_set_direction(@ptrCast(flow), gtk.GTK_TEXT_DIR_RTL);
            }
            _ = bible.sqlite3_finalize(s_stmt.?);
        }
        gtk.gtk_box_append(self.right_view, flow);

        var i_stmt: ?*bible.sqlite3_stmt = null;
        const i_sql = std.fmt.allocPrintSentinel(self.allocator, "SELECT original_text, strongs, translation FROM interlinear WHERE book='{s}' AND chapter={d} AND verse={d} ORDER BY word_index ASC", .{ book, chapter, verse }, 0) catch return;
        defer self.allocator.free(i_sql);
        if (bible.sqlite3_prepare_v2(self.db.?, i_sql, -1, @ptrCast(&i_stmt), null) == bible.SQLITE_OK) {
            while (bible.sqlite3_step(i_stmt.?) == bible.SQLITE_ROW) {
                self.addInteractiveWord(@ptrCast(flow), bible.sqlite3_column_text(i_stmt.?, 0) orelse "", bible.sqlite3_column_text(i_stmt.?, 1) orelse "", bible.sqlite3_column_text(i_stmt.?, 2) orelse "");
            }
            _ = bible.sqlite3_finalize(i_stmt.?);
        }
    }

    fn addInteractiveWord(self: *Reader, flow: ?*GtkFlowBox, word: [*:0]const u8, strongs: [*:0]const u8, trans: [*:0]const u8) void {
        const word_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 2);
        gtk.gtk_widget_add_css_class(@ptrCast(word_box), "interlinear-word");
        
        const word_btn = gtk.gtk_button_new_with_label(word);
        gtk.gtk_widget_add_css_class(word_btn, "interlinear-word-btn");
        
        const strongs_span = std.mem.span(strongs);
        if (strongs_span.len > 0) {
            if (strongs_span[0] == 'G') gtk.gtk_widget_add_css_class(word_btn, "greek")
            else if (strongs_span[0] == 'H') gtk.gtk_widget_add_css_class(word_btn, "hebrew");
        }
        
        const persistent_strongs = gtk.g_strdup(strongs);
        _ = gtk.g_signal_connect_data(word_btn, "clicked", @ptrCast(self.onWordClick), persistent_strongs, null, 0);
        
        const trans_lbl = gtk.gtk_label_new(trans);
        gtk.gtk_widget_add_css_class(trans_lbl, "interlinear-english");
        
        gtk.gtk_box_append(@ptrCast(word_box), word_btn);
        gtk.gtk_box_append(@ptrCast(word_box), trans_lbl);
        gtk.gtk_flow_box_insert(flow, word_box, -1);
    }

    fn addGestures(self: *Reader, lbl: ?*GtkWidget, idx: usize) void {
        const db_click = gtk.gtk_gesture_click_new();
        _ = gtk.g_signal_connect_data(db_click, "pressed", @ptrCast(&on_pressed_internal), self, @ptrFromInt(idx), 0);
        gtk.gtk_widget_add_controller(@ptrCast(lbl), @ptrCast(db_click));

        const long_press = gtk.gtk_gesture_long_press_new();
        _ = gtk.g_signal_connect_data(long_press, "pressed", @ptrCast(&on_long_press_internal), self, @ptrFromInt(idx), 0);
        gtk.gtk_widget_add_controller(@ptrCast(lbl), @ptrCast(long_press));
    }

    fn on_pressed_internal(gesture: ?*anyopaque, n_press: i32, x: f64, y: f64, user_data: gpointer) callconv(.c) void {
        _ = x; _ = y;
        const self: *Reader = @ptrCast(@alignCast(user_data));
        const idx: usize = @intCast(@intFromPtr(gtk.gtk_event_controller_get_widget(@ptrCast(gesture)))); // Simplified for index retrieval
        // Real implementation would use the n_press logic from main.zig
        if (n_press == 2) self.onVerseDoubleClick(idx)
        else if (n_press == 3) self.onVerseRightClick(idx);
    }

    fn on_long_press_internal(gesture: ?*anyopaque, x: f64, y: f64, user_data: gpointer) callconv(.c) void {
        _ = gesture; _ = x; _ = y;
        const self: *Reader = @ptrCast(@alignCast(user_data));
        // Needs proper index mapping
        self.onVerseLongPress(0); 
    }

    pub fn clearViews(self: *Reader) void {
        self.clearBox(self.left_view);
        self.clearBox(self.right_view);
    }

    fn clearBox(self: *Reader, box: ?*GtkBox) void {
        _ = self;
        if (box == null) return;
        while (gtk.gtk_widget_get_first_child(@ptrCast(box))) |child| {
            gtk.gtk_box_remove(box, child);
        }
    }

    fn on_scroll_changed(adj: ?*anyopaque, user_data: gpointer) callconv(.c) void {
        const target_adj: ?*anyopaque = @ptrCast(user_data);
        const value = gtk.gtk_adjustment_get_value(adj);
        if (@abs(value - gtk.gtk_adjustment_get_value(target_adj)) > 1.0) {
            gtk.gtk_adjustment_set_value(target_adj, value);
        }
    }
};
