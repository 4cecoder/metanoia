const std = @import("std");
const gtk = @import("gtk.zig");
const sidebar_cmp = @import("ui/components/sidebar.zig");
const status_bar_cmp = @import("ui/components/status_bar.zig");
const bible = @import("bible_db.zig");
const tts = @import("tts_client.zig");
const ollama = @import("ollama_client.zig");
const scraper = @import("scraper_client.zig");

// Use shortcuts for common types
const gpointer = gtk.gpointer;
const GtkApplication = gtk.GtkApplication;
const GApplication = gtk.GApplication;
const GtkWindow = gtk.GtkWindow;
const GtkWidget = gtk.GtkWidget;
const GtkBox = gtk.GtkBox;
const GtkPaned = gtk.GtkPaned;
const GtkLabel = gtk.GtkLabel;
const GtkScrolledWindow = gtk.GtkScrolledWindow;
const GtkCssProvider = gtk.GtkCssProvider;
const GdkDisplay = gtk.GdkDisplay;
const GtkButton = gtk.GtkButton;
const GtkNotebook = gtk.GtkNotebook;
const GtkFlowBox = gtk.GtkFlowBox;
const GtkStack = gtk.GtkStack;
const GtkAdjustment = gtk.GtkAdjustment;
const GtkExpander = gtk.GtkExpander;

// Re-export constants for local use
const GTK_ORIENTATION_HORIZONTAL = gtk.GTK_ORIENTATION_HORIZONTAL;
const GTK_ORIENTATION_VERTICAL = gtk.GTK_ORIENTATION_VERTICAL;
const GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = gtk.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION;
const GTK_STYLE_PROVIDER_PRIORITY_USER = gtk.GTK_STYLE_PROVIDER_PRIORITY_USER;
const GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT = gtk.GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT;

// Common GTK functions we use everywhere
const gtk_box_append = gtk.gtk_box_append;
const gtk_label_new = gtk.gtk_label_new;
const gtk_button_new_with_label = gtk.gtk_button_new_with_label;
const g_signal_connect_data = gtk.g_signal_connect_data;
const gtk_widget_set_visible = gtk.gtk_widget_set_visible;
const gtk_widget_add_css_class = gtk.gtk_widget_add_css_class;
const gtk_widget_remove_css_class = gtk.gtk_widget_remove_css_class;
const g_timeout_add = gtk.g_timeout_add;
const gtk_widget_set_hexpand = gtk.gtk_widget_set_hexpand;
const gtk_widget_set_vexpand = gtk.gtk_widget_set_vexpand;
const gtk_widget_set_halign = gtk.gtk_widget_set_halign;
const gtk_window_present = gtk.gtk_window_present;
const gtk_window_close = gtk.gtk_window_close;
const gtk_window_set_child = gtk.gtk_window_set_child;
const gtk_window_set_default_size = gtk.gtk_window_set_default_size;
const gtk_window_set_title = gtk.gtk_window_set_title;
const gtk_window_new = gtk.gtk_window_new;
const gtk_application_window_new = gtk.gtk_application_window_new;
const gtk_application_new = gtk.gtk_application_new;
const g_application_run = gtk.g_application_run;
const g_object_unref = gtk.g_object_unref;
const g_idle_add = gtk.g_idle_add;
const g_thread_new = gtk.g_thread_new;
const gtk_widget_grab_focus = gtk.gtk_widget_grab_focus;
const gtk_editable_set_text = gtk.gtk_editable_set_text;
const gtk_editable_get_text = gtk.gtk_editable_get_text;
const gtk_list_box_remove_all = gtk.gtk_list_box_remove_all;
const gtk_list_box_append = gtk.gtk_list_box_append;
const gtk_list_box_new = gtk.gtk_list_box_new;
const gtk_list_box_set_selection_mode = gtk.gtk_list_box_set_selection_mode;
const gtk_scrolled_window_new = gtk.gtk_scrolled_window_new;
const gtk_scrolled_window_set_child = gtk.gtk_scrolled_window_set_child;
const gtk_scrolled_window_get_vadjustment = gtk.gtk_scrolled_window_get_vadjustment;
const gtk_adjustment_set_value = gtk.gtk_adjustment_set_value;
const gtk_adjustment_get_value = gtk.gtk_adjustment_get_value;
const gtk_adjustment_get_page_size = gtk.gtk_adjustment_get_page_size;
const gtk_widget_get_first_child = gtk.gtk_widget_get_first_child;
const gtk_widget_get_next_sibling = gtk.gtk_widget_get_next_sibling;
const gtk_widget_get_parent = gtk.gtk_widget_get_parent;
const gtk_widget_add_controller = gtk.gtk_widget_add_controller;
const gtk_widget_set_name = gtk.gtk_widget_set_name;
const gtk_widget_set_size_request = gtk.gtk_widget_set_size_request;
const gtk_popover_new = gtk.gtk_popover_new;
const gtk_popover_set_child = gtk.gtk_popover_set_child;
const gtk_popover_set_has_arrow = gtk.gtk_popover_set_has_arrow;
const gtk_popover_popdown = gtk.gtk_popover_popdown;
const gtk_popover_popup = gtk.gtk_popover_popup;
const gtk_popover_set_autohide = gtk.gtk_popover_set_autohide;
const gtk_popover_set_offset = gtk.gtk_popover_set_offset;
const gtk_popover_menu_new_from_model = gtk.gtk_popover_menu_new_from_model;
const g_menu_new = gtk.g_menu_new;
const g_menu_append = gtk.g_menu_append;
const g_action_map_add_action_entries = gtk.g_action_map_add_action_entries;
const GActionEntry = gtk.GActionEntry;
const gtk_paned_new = gtk.gtk_paned_new;
const gtk_paned_set_start_child = gtk.gtk_paned_set_start_child;
const gtk_paned_set_end_child = gtk.gtk_paned_set_end_child;
const gtk_paned_set_position = gtk.gtk_paned_set_position;
const gtk_paned_get_position = gtk.gtk_paned_get_position;
const gtk_notebook_new = gtk.gtk_notebook_new;
const gtk_notebook_append_page = gtk.gtk_notebook_append_page;
const gtk_notebook_set_current_page = gtk.gtk_notebook_set_current_page;
const gtk_box_new = gtk.gtk_box_new;
const gtk_box_remove = gtk.gtk_box_remove;
const gtk_label_set_markup = gtk.gtk_label_set_markup;
const gtk_label_set_wrap = gtk.gtk_label_set_wrap;
const gtk_label_set_xalign = gtk.gtk_label_set_xalign;
const gtk_css_provider_new = gtk.gtk_css_provider_new;
const gtk_css_provider_load_from_path = gtk.gtk_css_provider_load_from_path;
const gtk_css_provider_load_from_data = gtk.gtk_css_provider_load_from_data;
const gdk_display_get_default = gtk.gdk_display_get_default;
const gtk_style_context_add_provider_for_display = gtk.gtk_style_context_add_provider_for_display;
const gtk_drop_down_new_from_strings = gtk.gtk_drop_down_new_from_strings;
const gtk_drop_down_get_selected = gtk.gtk_drop_down_get_selected;
const gtk_drop_down_set_selected = gtk.gtk_drop_down_set_selected;
const gtk_event_controller_key_new = gtk.gtk_event_controller_key_new;
const gtk_gesture_click_new = gtk.gtk_gesture_click_new;
const gtk_gesture_single_set_button = gtk.gtk_gesture_single_set_button;
const gtk_window_set_modal = gtk.gtk_window_set_modal;
const gtk_window_set_transient_for = gtk.gtk_window_set_transient_for;
const gtk_window_set_decorated = gtk.gtk_window_set_decorated;
const gtk_window_set_resizable = gtk.gtk_window_set_resizable;
const gtk_window_is_active = gtk.gtk_window_is_active;
const g_signal_emit_by_name = gtk.g_signal_emit_by_name;
const gtk_expander_new = gtk.gtk_expander_new;
const gtk_expander_set_child = gtk.gtk_expander_set_child;
const gtk_expander_set_expanded = gtk.gtk_expander_set_expanded;

const gtk_spinner_new = gtk.gtk_spinner_new;
const gtk_spinner_start = gtk.gtk_spinner_start;
const gtk_spinner_stop = gtk.gtk_spinner_stop;

const gtk_gesture_long_press_new = gtk.gtk_gesture_long_press_new;
const gtk_text_view_new = gtk.gtk_text_view_new;
const gtk_text_view_get_buffer = gtk.gtk_text_view_get_buffer;
const gtk_text_buffer_set_text = gtk.gtk_text_buffer_set_text;
const gtk_text_buffer_get_start_iter = gtk.gtk_text_buffer_get_start_iter;
const gtk_text_buffer_get_end_iter = gtk.gtk_text_buffer_get_end_iter;
const gtk_text_buffer_get_text = gtk.gtk_text_buffer_get_text;

// SQLite3
const gtk_button_set_label = gtk.gtk_button_set_label;
const gtk_button_set_child = gtk.gtk_button_set_child;
const gtk_widget_set_parent = gtk.gtk_widget_set_parent;
const g_get_monotonic_time = gtk.g_get_monotonic_time;
const g_usleep = gtk.g_usleep;
const gtk_widget_get_visible = gtk.gtk_widget_get_visible;
const g_strdup = gtk.g_strdup;
const g_free = gtk.g_free;
const gtk_flow_box_new = gtk.gtk_flow_box_new;
const gtk_window_destroy = gtk.gtk_window_destroy;
const gtk_stack_get_visible_child_name = gtk.gtk_stack_get_visible_child_name;
const gtk_stack_new = gtk.gtk_stack_new;
const gtk_widget_compute_bounds = gtk.gtk_widget_compute_bounds;

const gtk_flow_box_insert = gtk.gtk_flow_box_insert;
const gtk_flow_box_set_selection_mode = gtk.gtk_flow_box_set_selection_mode;
const gtk_flow_box_set_min_children_per_line = gtk.gtk_flow_box_set_min_children_per_line;
const gtk_stack_set_visible_child_name = gtk.gtk_stack_set_visible_child_name;
const gtk_stack_set_transition_type = gtk.gtk_stack_set_transition_type;
const gtk_stack_get_child_by_name = gtk.gtk_stack_get_child_by_name;
const gtk_stack_remove = gtk.gtk_stack_remove;
const gtk_search_entry_new = gtk.gtk_search_entry_new;

const gtk_widget_set_direction = gtk.gtk_widget_set_direction;
const gtk_widget_set_sensitive = gtk.gtk_widget_set_sensitive;
const gtk_stack_add_named = gtk.gtk_stack_add_named;
const GTK_TEXT_DIR_RTL = gtk.GTK_TEXT_DIR_RTL;

const sqlite3 = bible.sqlite3;
const sqlite3_stmt = bible.sqlite3_stmt;
const sqlite3_open = bible.sqlite3_open;
const sqlite3_close = bible.sqlite3_close;
const sqlite3_prepare_v2 = bible.sqlite3_prepare_v2;
const sqlite3_step = bible.sqlite3_step;
const sqlite3_column_text = bible.sqlite3_column_text;
const sqlite3_column_int = bible.sqlite3_column_int;
const sqlite3_finalize = bible.sqlite3_finalize;
const SQLITE_ROW = bible.SQLITE_ROW;
const SQLITE_OK = bible.SQLITE_OK;

const SearchResult = bible.SearchResult;
const BIBLE_BOOKS = bible.BIBLE_BOOKS;
const BIBLE_ABBREVIATIONS = bible.BIBLE_ABBREVIATIONS;
const Testament = bible.Testament;

// Application Globals
var db: ?*sqlite3 = null;
var main_notebook: ?*GtkNotebook = null;
var bible_view: ?*GtkBox = null;
var main_window: ?*GtkWindow = null;
var main_sidebar: ?*sidebar_cmp.Sidebar = null;
var main_paned: ?*GtkPaned = null;
var font_provider: ?*GtkCssProvider = null;
var search_entry: ?*GtkWidget = null;
var search_window: ?*GtkWindow = null;
var search_results_list: ?*GtkWidget = null;
var search_results_container: ?*GtkWidget = null;

var persistent_search_results: [50]SearchResult = undefined;
var main_io: std.Io = undefined;

var study_left_view: ?*GtkBox = null;
var study_right_view: ?*GtkBox = null;
var study_left_scroll: ?*GtkWidget = null;
var study_right_scroll: ?*GtkWidget = null;
var right_scroll_pane: ?*GtkWidget = null;
var f_right_plus_btn: ?*GtkWidget = null;
var f_right_minus_btn: ?*GtkWidget = null;
var active_note_verse: ?struct { book: [64]u8, ch: i32, v: i32 } = null;
var chapter_summary_label: ?*GtkLabel = null;
var word_study_label: ?*GtkLabel = null;
var llm_spinner: ?*GtkWidget = null;
var note_view: ?*GtkWidget = null;
var note_buffer: ?*anyopaque = null;
var main_status_bar: ?*status_bar_cmp.StatusBar = null;

var selection_dialog: ?*GtkWindow = null;
var modal_stack: ?*GtkStack = null;
var modal_title: ?*GtkLabel = null;
var cur_book_name: [64]u8 = undefined;
var cur_chapter: i32 = 1;
var current_chapter_verses: ?std.ArrayListUnmanaged([]const u8) = null;
var verse_labels: ?std.ArrayListUnmanaged(?*GtkWidget) = null;
var highlighted_index: ?usize = null;
var rerender_target_index: usize = 0;
var verse_popover: ?*GtkWidget = null;
var tts_lock = std.atomic.Value(bool).init(false);
var tts_proc_lock = std.atomic.Value(bool).init(false);

var tts_process: ?*std.process.Child = null;
var tts_playing = std.atomic.Value(bool).init(false);
var tts_stop_requested = std.atomic.Value(bool).init(false);
var last_speaker_click_time: i64 = 0;

fn on_paned_notify_position(self: ?*anyopaque, pspec: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = pspec; _ = user_data;
    const pos = gtk_paned_get_position(@ptrCast(self));
    if (pos > 0 and pos != app_config.sidebar_width) {
        app_config.sidebar_width = pos;
        save_config();
    }
}

fn on_tts_mode_changed(self: ?*anyopaque, pspec: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = pspec; _ = user_data;
    const selected = gtk_drop_down_get_selected(self);
    const modes = [_][]const u8{ "speedy", "gold" };
    if (selected < modes.len) {
        app_config.tts_mode = modes[selected];
        save_config();
        std.debug.print("TTS Mode changed to: {s}\n", .{app_config.tts_mode});
    }
}

fn on_voice_changed(self: ?*anyopaque, pspec: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = pspec; _ = user_data;
    const selected = gtk_drop_down_get_selected(self);
    const voices = [_][]const u8{ "lennox", "tommy", "mari", "jordan", "shamoun", "roumie" };
    if (selected < voices.len) {
        const voice_name = voices[selected];
        app_config.selected_voice = voice_name;
        save_config();
        
        const msg = std.fmt.allocPrint(std.heap.page_allocator, "Voice changed to {s}", .{voice_name}) catch "Voice changed";
        if (main_status_bar) |sb| sb.updateStatus(msg, false);
        if (!std.mem.eql(u8, msg, "Voice changed")) std.heap.page_allocator.free(msg);

        std.debug.print("Voice changed to: {s}\n", .{app_config.selected_voice});
    }
}

fn on_color_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const color: [*:0]const u8 = @ptrCast(user_data);
    const color_span = std.mem.span(color);
    if (active_note_verse) |av| {
        const book = std.mem.span(@as([*:0]const u8, @ptrCast(&av.book)));
        if (std.mem.eql(u8, color_span, "none")) {
            bible.delete_verse_highlight(db.?, book, av.ch, av.v) catch {};
            if (main_status_bar) |sb| sb.updateStatus("Highlight removed", false);
        } else {
            bible.set_verse_highlight(db.?, book, av.ch, av.v, color_span) catch |err| {
                std.debug.print("Failed to save highlight: {any}\n", .{err});
                if (main_status_bar) |sb| sb.updateStatus("Failed to save highlight", true);
            };
            if (main_status_bar) |sb| sb.updateStatus("Verse highlighted", false);
        }
        // Immediate full re-render to show highlights correctly
        load_chapter_into_study(book, av.ch, av.v);
    }
}

fn on_verse_long_press(gesture: ?*anyopaque, x: f64, y: f64, user_data: gpointer) callconv(.c) void {
    _ = gesture; _ = x; _ = y;
    const index: usize = @intCast(@intFromPtr(user_data));
    const allocator = std.heap.page_allocator;
    
    // Highlight this verse
    highlighted_index = index;
    // We need to re-render to show highlight? 
    // For now let's just trigger the UI update
    _ = g_idle_add(&update_highlight_and_scroll, @ptrFromInt(index));

    const book = std.mem.span(@as([*:0]u8, @ptrCast(&cur_book_name)));
    const v_num = @as(i32, @intCast(index)) + 1;
    
    active_note_verse = .{
        .book = cur_book_name,
        .ch = cur_chapter,
        .v = v_num,
    };

    // Open sidebar
    if (main_sidebar) |sb| gtk_widget_set_visible(sb.box.?, true);

    // Load note from DB
    const existing = bible.get_verse_note(allocator, db.?, book, cur_chapter, v_num) catch "";
    defer allocator.free(existing);
    
    const existing_z = allocator.dupeZ(u8, existing) catch "";
    defer allocator.free(existing_z);
    
    gtk_text_buffer_set_text(note_buffer, existing_z, -1);
}

fn reset_save_button_idle(data: gpointer) callconv(.c) bool {
    const btn: ?*GtkButton = @ptrCast(@alignCast(data));
    if (btn) |b| {
        gtk_button_set_label(b, "Save Note");
        gtk_widget_remove_css_class(@ptrCast(b), "save-success");
    }
    return false;
}

fn on_save_note_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = user_data;
    if (active_note_verse) |av| {
        var start_iter: [128]u8 = undefined;
        var end_iter: [128]u8 = undefined;
        
        gtk_text_buffer_get_start_iter(note_buffer, &start_iter);
        gtk_text_buffer_get_end_iter(note_buffer, &end_iter);
        
        const text = gtk_text_buffer_get_text(note_buffer, &start_iter, &end_iter, false);
        defer g_free(text);
        
        const book = std.mem.span(@as([*:0]const u8, @ptrCast(&av.book)));
        bible.save_verse_note(db.?, book, av.ch, av.v, std.mem.span(text)) catch |err| {
            std.debug.print("Failed to save note: {any}\n", .{err});
            if (main_status_bar) |sb| sb.updateStatus("Failed to save note", true);
            return;
        };

        if (main_status_bar) |sb| sb.updateStatus("Note saved successfully", false);

        // Provide feedback
        if (btn) |b| {
            gtk_button_set_label(b, "✅ Saved!");
            gtk_widget_add_css_class(@ptrCast(b), "save-success");
            _ = g_timeout_add(1500, &reset_save_button_idle, b);
        }
    }
}

fn on_regenerate_tts_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = user_data;
    const allocator = std.heap.page_allocator;
    const av = active_note_verse orelse return;
    const book = std.mem.span(@as([*:0]const u8, @ptrCast(&av.book)));

    // Fetch the verse text from DB
    const sql = std.fmt.allocPrintSentinel(allocator, "SELECT text FROM verses WHERE book='{s}' AND chapter={d} AND verse={d} LIMIT 1", .{ book, av.ch, av.v }, 0) catch return;
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db.?, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        if (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const text_raw = sqlite3_column_text(stmt.?, 0) orelse "";
            const text = allocator.dupe(u8, std.mem.span(text_raw)) catch {
                _ = sqlite3_finalize(stmt.?);
                return;
            };
            
            if (btn) |b| {
                gtk_button_set_label(b, "Generating...");
                gtk_widget_set_sensitive(@ptrCast(b), false);
            }

            const msg = std.fmt.allocPrint(allocator, "Generating TTS for {s} {d}:{d}...", .{ book, av.ch, av.v }) catch "Generating TTS...";
            if (main_status_bar) |sb| sb.updateStatus(msg, false);
            if (!std.mem.eql(u8, msg, "Generating TTS...")) allocator.free(msg);

            const Wrapper = struct {
                btn: ?*GtkButton,
                text: []const u8,
                engine: std.Io,
                fn thread(p: gpointer) callconv(.c) gpointer {
                    const self: *@This() = @ptrCast(@alignCast(p));
                    const inner_allocator = std.heap.page_allocator;
                    
                    const path = tts.generate_speech(self.engine, self.text, app_config.selected_voice, app_config.speed, app_config.emotion, app_config.mode, true) catch null;
                    if (path) |pa| inner_allocator.free(pa);

                    _ = g_idle_add(&reset_tts_btn_idle, self.btn);
                    if (main_status_bar) |sb| sb.updateStatus("TTS Generated", false);
                    
                    inner_allocator.free(self.text);
                    inner_allocator.destroy(self);
                    return null;
                }
            };

            const w = allocator.create(Wrapper) catch {
                allocator.free(text);
                _ = sqlite3_finalize(stmt.?);
                return;
            };
            w.* = .{ .btn = btn, .text = text, .engine = main_io };
            _ = g_thread_new("single_tts_gen", &Wrapper.thread, w);
        }
        _ = sqlite3_finalize(stmt.?);
    }
}

fn reset_tts_btn_idle(data: gpointer) callconv(.c) bool {
    const btn: ?*GtkButton = @ptrCast(@alignCast(data));
    if (btn) |b| {
        gtk_button_set_label(b, "Regenerate Verse TTS");
        gtk_widget_set_sensitive(@ptrCast(b), true);
    }
    return false;
}

const MasterPlayContext = struct {
    path: []const u8,
    engine: std.Io,
    fn run(p: gpointer) callconv(.c) gpointer {
        const self: *@This() = @ptrCast(@alignCast(p));
        const allocator = std.heap.page_allocator;
        
        var play_child = std.process.spawn(self.engine, .{ .argv = &.{ "afplay", self.path } }) catch {
            allocator.free(self.path);
            allocator.destroy(self);
            return null;
        };

        {
            while (tts_proc_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
            defer tts_proc_lock.store(false, .release);
            tts_process = &play_child;
        }

        _ = play_child.wait(self.engine) catch {};

        {
            while (tts_proc_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
            defer tts_proc_lock.store(false, .release);
            if (tts_process == &play_child) tts_process = null;
        }

        const s = allocator.dupeZ(u8, "Full Chapter Playback Finished.");
        if (s) |str| {
            _ = g_idle_add(&status_update_idle, @ptrCast(@constCast(str.ptr)));
        } else |_| {}

        allocator.free(self.path);
        allocator.destroy(self);
        return null;
    }
};

fn on_full_chapter_tts_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const allocator = std.heap.page_allocator;
    const io = main_io;
    
    const verses = current_chapter_verses orelse return;
    if (verses.items.len == 0) return;

    var full_text = std.ArrayListUnmanaged(u8).empty;
    defer full_text.deinit(allocator);
    for (verses.items) |v| {
        full_text.appendSlice(allocator, v) catch {};
        full_text.append(allocator, ' ') catch {};
    }

    // Stop any existing verse-by-verse playback
    tts_stop_requested.store(true, .release);
    if (tts_process) |p| {
        if (p.id) |pid| std.posix.kill(pid, std.posix.SIG.TERM) catch {};
    }

    const Wrapper = struct {
        text: []const u8,
        engine: std.Io,
        fn thread(p: gpointer) callconv(.c) gpointer {
            const self: *@This() = @ptrCast(@alignCast(p));
            const inner_allocator = std.heap.page_allocator;
            
            const path = tts.generate_speech(self.engine, self.text, app_config.selected_voice, app_config.speed, app_config.emotion, app_config.tts_mode, false) catch null;
            
            if (path) |pa| {
                const ctx = inner_allocator.create(MasterPlayContext) catch {
                    inner_allocator.free(pa);
                    inner_allocator.free(self.text);
                    inner_allocator.destroy(self);
                    return null;
                };
                ctx.* = .{ .path = pa, .engine = self.engine };
                _ = g_thread_new("master_play", &MasterPlayContext.run, ctx);
            }

            inner_allocator.free(self.text);
            inner_allocator.destroy(self);
            return null;
        }
    };

    const s = allocator.dupeZ(u8, "Preparing Full Chapter Audio...");
    if (s) |str| {
        _ = g_idle_add(&status_update_idle, @ptrCast(@constCast(str.ptr)));
    } else |_| {}
    if (main_sidebar) |sb| gtk_widget_set_visible(sb.box.?, true);

    const w = allocator.create(Wrapper) catch return;
    const text_dupe = allocator.dupe(u8, full_text.items) catch {
        allocator.destroy(w);
        return;
    };
    w.* = .{ .text = text_dupe, .engine = io };
    _ = g_thread_new("full_chapter_gen", &Wrapper.thread, w);
}

fn on_llm_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const allocator = std.heap.page_allocator;
    const verses = current_chapter_verses orelse return;
    const index = highlighted_index orelse 0;
    if (index >= verses.items.len) return;

    const verse_text = verses.items[index];
    const book_name = std.mem.span(@as([*:0]const u8, @ptrCast(&cur_book_name)));
    
    // Update sidebar to show loading
    gtk_label_set_markup(word_study_label, "<span color='#7aa2f7'>Consulting Granite 4 LLM...</span>");
    if (llm_spinner) |s| {
        gtk_widget_set_visible(s, true);
        gtk_spinner_start(s);
    }
    
    // Ensure sidebar is visible
    if (main_sidebar) |sb| gtk_widget_set_visible(sb.box.?, true);

    const Context = struct {
        text: []const u8,
        book: []const u8,
        ch: i32,
        v: i32,
        engine: std.Io,
        fn run(p: gpointer) callconv(.c) gpointer {
            const self: *@This() = @ptrCast(@alignCast(p));
            const inner_allocator = std.heap.page_allocator;
            
            if (inner_allocator.dupeZ(u8, "<span color='#7aa2f7'>Step 0/4: Checking for factual data...</span>")) |s0| {
                _ = g_idle_add(&status_update_idle, @ptrCast(@constCast(s0.ptr)));
            } else |_| {}

            // 1. Check if we have lexicon data, if not, try to scrape it
            {
                const test_lex = bible.get_verse_lexicon_context(inner_allocator, db.?, self.book, self.ch, self.v + 1) catch "";
                defer if (test_lex.len > 0) inner_allocator.free(test_lex);
                if (test_lex.len == 0) {
                    if (inner_allocator.dupeZ(u8, "<span color='#e0af68'>Auto-Tooling: Fetching Interlinear Data from BibleHub...</span>")) |s_tool| {
                        _ = g_idle_add(&status_update_idle, @ptrCast(@constCast(s_tool.ptr)));
                    } else |_| {}
                    
                    scraper.scrape_interlinear(self.engine, self.book, self.ch) catch {};
                    scraper.scrape_lexicon(self.engine) catch {};
                }
            }

            if (inner_allocator.dupeZ(u8, "<span color='#7aa2f7'>Step 1/4: Gathering Historical &amp; Lexical Facts...</span>")) |s1| {
                _ = g_idle_add(&status_update_idle, @ptrCast(@constCast(s1.ptr)));
            } else |_| {}

            // Fetch factual context from DB
            const lex_context = bible.get_verse_lexicon_context(inner_allocator, db.?, self.book, self.ch, self.v + 1) catch "";
            defer if (lex_context.len > 0) inner_allocator.free(lex_context);

            const xref_context = bible.get_cross_references(inner_allocator, db.?, self.book, self.ch, self.v + 1) catch "";
            defer if (xref_context.len > 0) inner_allocator.free(xref_context);

            const hist_context = bible.get_book_metadata(inner_allocator, db.?, self.book) catch "";
            defer if (hist_context.len > 0) inner_allocator.free(hist_context);

            var summary_context = bible.get_chapter_summary(inner_allocator, db.?, self.book, self.ch) catch "";
            const summary_was_missing = std.mem.containsAtLeast(u8, summary_context, 1, "No literary summary found");
            
            if (summary_was_missing) {
                if (inner_allocator.dupeZ(u8, "<span color='#7aa2f7'>Step 2/4: Creating Literary Context (Summarizing)...</span>")) |s2| {
                    _ = g_idle_add(&status_update_idle, @ptrCast(@constCast(s2.ptr)));
                } else |_| {}

                inner_allocator.free(summary_context);
                const chapter_verses = bible.get_chapter_verses(inner_allocator, db.?, self.book, self.ch) catch null;
                if (chapter_verses) |cv| {
                    defer {
                        for (cv.items) |v| inner_allocator.free(v);
                        var list = cv;
                        list.deinit(inner_allocator);
                    }
                    var full_text = std.ArrayListUnmanaged(u8).empty;
                    defer full_text.deinit(inner_allocator);
                    for (cv.items) |v| {
                        full_text.appendSlice(inner_allocator, v) catch {};
                        full_text.append(inner_allocator, ' ') catch {};
                    }
                    
                    const summary_prompt = std.fmt.allocPrint(inner_allocator, 
                        "Summarize the following Bible chapter in one concise sentence: {s} {d} - \"{s}\"",
                        .{ self.book, self.ch, full_text.items }
                    ) catch "No summary available.";
                    defer if (!std.mem.eql(u8, summary_prompt, "No summary available.")) inner_allocator.free(summary_prompt);
                    
                    summary_context = ollama.generate_response(inner_allocator, self.engine, summary_prompt) catch (inner_allocator.dupe(u8, "No summary available.") catch "");
                    // Cache it for next time
                    if (summary_context.len > 0 and !std.mem.eql(u8, summary_context, "No summary available.")) {
                        bible.save_chapter_summary(db.?, self.book, self.ch, summary_context) catch {};
                    }
                } else {
                    summary_context = inner_allocator.dupe(u8, "No summary available.") catch "";
                }
            }
            defer if (summary_context.len > 0) inner_allocator.free(summary_context);

            // Update the Summary UI label
            if (inner_allocator.dupeZ(u8, summary_context)) |final_summary| {
                _ = g_idle_add(&update_summary_idle, @ptrCast(@constCast(final_summary.ptr)));
            } else |_| {}

            if (inner_allocator.dupeZ(u8, "<span color='#7aa2f7'>Step 3/4: Synthesizing Scholarly Insight...</span>")) |s3| {
                _ = g_idle_add(&status_update_idle, @ptrCast(@constCast(s3.ptr)));
            } else |_| {}

            const prompt = std.fmt.allocPrint(inner_allocator, 
                "System: You are a precise biblical scholar. Use ONLY the provided data to explain the verse.\n\n" ++
                "Verse: {s} {d}:{d}\n" ++
                "Text: \"{s}\"\n\n" ++
                "Historical Context: {s}\n\n" ++
                "Chapter Summary: {s}\n\n" ++
                "Lexicon &amp; Morphology:\n{s}\n\n" ++
                "Cross References:\n{s}\n\n" ++
                "Instruction: Provide a concise scholarly insight. Explain how the historical setting and chapter summary (literary context) inform the original word meanings to clarify the verse's intent. Connect it to a cross-reference.",
                .{ self.book, self.ch, @as(i32, @intCast(self.v)) + 1, self.text, hist_context, summary_context, lex_context, xref_context }
            ) catch return null;
            defer inner_allocator.free(prompt);

            const response = ollama.generate_response(inner_allocator, self.engine, prompt) catch |err| {
                const err_msg = std.fmt.allocPrint(inner_allocator, "LLM Error: {any}", .{err}) catch return null;
                defer inner_allocator.free(err_msg);
                if (inner_allocator.dupeZ(u8, err_msg)) |final_err| {
                    _ = g_idle_add(&update_sidebar_idle, @ptrCast(@constCast(final_err.ptr)));
                } else |_| {}
                return null;
            };
            defer inner_allocator.free(response);

            // Pass response to UI thread
            if (inner_allocator.dupeZ(u8, response)) |final_res| {
                _ = g_idle_add(&update_sidebar_idle, @ptrCast(@constCast(final_res.ptr)));
            } else |_| {}
            
            inner_allocator.destroy(self);
            return null;
        }
    };

    const ctx = allocator.create(Context) catch return;
    ctx.* = .{
        .text = verse_text,
        .book = book_name,
        .ch = cur_chapter,
        .v = @intCast(index),
        .engine = main_io,
    };
    _ = g_thread_new("llm_thread", &Context.run, ctx);
}

fn status_update_idle(data: gpointer) callconv(.c) bool {
    const text: [*:0]u8 = @ptrCast(@alignCast(data));
    const span = std.mem.span(text);
    defer std.heap.page_allocator.free(span);
    
    if (main_status_bar) |sb| sb.updateStatus(span, false);
    if (main_sidebar) |ms| ms.log(span);
    
    if (word_study_label) |lbl| {
        gtk_label_set_markup(lbl, text);
    }
    return false;
}

fn update_summary_idle(data: gpointer) callconv(.c) bool {
    const text: [*:0]u8 = @ptrCast(@alignCast(data));
    const span = std.mem.span(text);
    defer std.heap.page_allocator.free(span);
    
    if (main_sidebar) |ms| ms.log("Summary updated.");
    
    if (chapter_summary_label) |lbl| {
        gtk_label_set_markup(lbl, text);
    }
    return false;
}

fn update_sidebar_idle(data: gpointer) callconv(.c) bool {
    const text: [*:0]u8 = @ptrCast(@alignCast(data));
    const span = std.mem.span(text);
    defer std.heap.page_allocator.free(span);
    
    if (main_status_bar) |sb| sb.updateStatus("Analysis Complete", false);
    if (main_sidebar) |ms| ms.log("Neural analysis finished.");

    if (word_study_label) |lbl| {
        gtk_label_set_markup(lbl, text);
    }
    if (llm_spinner) |s| {
        gtk_spinner_stop(s);
        gtk_widget_set_visible(s, false);
    }
    return false;
}

fn on_rerender_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    if (verse_popover) |p| gtk_popover_popdown(@ptrCast(p));
    
    const index = rerender_target_index;
    const allocator = std.heap.page_allocator;
    const io = main_io;
    const verses = current_chapter_verses orelse return;
    if (index >= verses.items.len) return;

    // Trigger a single background request with force_refresh
    const t_func = struct {
        fn run(idx: usize, text: []const u8, engine: std.Io) void {
            _ = idx;
            // Regenerate is ALWAYS Gold Standard for maximum accuracy
            const path = tts.generate_speech(engine, text, app_config.selected_voice, app_config.speed, app_config.emotion, "gold", true) catch return;
            std.heap.page_allocator.free(path);
        }
    };
    
    // We could spawn a thread but for a single curl it's fast enough or we just use g_thread_new
    const Wrapper = struct {
        idx: usize,
        text: []const u8,
        engine: std.Io,
        fn thread(p: gpointer) callconv(.c) gpointer {
            const self: *@This() = @ptrCast(@alignCast(p));
            t_func.run(self.idx, self.text, self.engine);
            std.heap.page_allocator.destroy(self);
            return null;
        }
    };
    const w = allocator.create(Wrapper) catch return;
    w.* = .{ .idx = index, .text = verses.items[index], .engine = io };
    _ = g_thread_new("rerender_thread", &Wrapper.thread, w);
}

fn on_rerender_action(action: ?*anyopaque, parameter: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = action; _ = parameter; _ = user_data;
    on_rerender_clicked(null, @ptrFromInt(rerender_target_index));
}

fn on_verse_right_click(gesture: ?*anyopaque, n_press: i32, x: f64, y: f64, user_data: gpointer) callconv(.c) void {
    _ = gesture; _ = n_press; _ = x; _ = y;
    const index: usize = @intCast(@intFromPtr(user_data));
    rerender_target_index = index;

    if (verse_popover) |p| {
        gtk_popover_popup(@ptrCast(p));
    }
}

var tts_button_ref: ?*GtkButton = null;
var tts_start_index: usize = 0;

fn on_verse_double_click(gesture: ?*anyopaque, n_press: i32, x: f64, y: f64, user_data: gpointer) callconv(.c) void {
    _ = gesture; _ = x; _ = y;
    if (n_press == 2) {
        const index: usize = @intCast(@intFromPtr(user_data));
        
        // Stop current TTS if any
        tts_stop_requested.store(true, .release);
        {
            while (tts_proc_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
            defer tts_proc_lock.store(false, .release);
            if (tts_process) |p| {
                if (p.id) |pid| {
                    if (pid != 0) std.posix.kill(pid, std.posix.SIG.TERM) catch {};
                }
            }
        }

        // Wait a bit for the previous thread to potentially exit
        // (Simplified, the thread func loop checks stop_requested)
        
        if (current_chapter_verses == null or current_chapter_verses.?.items.len == 0) return;

        // Set start index and trigger play
        tts_start_index = index;
        
        // Ensure we aren't already starting
        if (tts_playing.load(.acquire)) {
             // If already playing, tts_thread_func will see tts_stop_requested and exit soon.
             // We need to wait for it to actually clear tts_playing.
             // For simplicity, we trigger a small delay before starting new one.
             _ = g_timeout_add(100, struct {
                 fn run(idx: gpointer) callconv(.c) bool {
                    if (tts_playing.load(.acquire)) return true; // keep waiting
                    
                    tts_playing.store(true, .release);
                    tts_stop_requested.store(false, .release);
                    tts_start_index = @intCast(@intFromPtr(idx));
                    _ = g_thread_new("tts_thread_doubleclick", &tts_thread_func, null);
                    return false;
                 }
             }.run, @ptrFromInt(index));
        } else {
            tts_playing.store(true, .release);
            tts_stop_requested.store(false, .release);
            _ = g_thread_new("tts_thread_doubleclick", &tts_thread_func, null);
        }
    }
}

fn update_highlight_and_scroll(data: gpointer) callconv(.c) bool {
    const index: usize = @intCast(@intFromPtr(data));
    const allocator = std.heap.page_allocator;
    const labels = verse_labels orelse return false;
    const verses = current_chapter_verses orelse return false;

    // 1. Reset previous highlight
    if (highlighted_index) |prev| {
        if (prev < labels.items.len) {
            const lbl = labels.items[prev] orelse return false;
            const highlights = bible.get_chapter_highlights(allocator, db.?, std.mem.span(@as([*:0]u8, @ptrCast(&cur_book_name))), cur_chapter) catch std.AutoHashMapUnmanaged(i32, []const u8).empty;
            defer {
                var it = highlights.iterator();
                while (it.next()) |entry| allocator.free(entry.value_ptr.*);
                var h = highlights;
                h.deinit(allocator);
            }

            const v_num = @as(i32, @intCast(prev)) + 1;
            const bg_color = highlights.get(v_num);
            const text = verses.items[prev];

            var markup_slice: [:0]u8 = undefined;
            if (bg_color) |bg| {
                markup_slice = std.fmt.allocPrintSentinel(allocator, "<span background='{s}'><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='#7aa2f7'>{d}</span> {s}</span>", .{ bg, v_num, text }, 0) catch @constCast("Error");
            } else {
                markup_slice = std.fmt.allocPrintSentinel(allocator, "<span><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='#7aa2f7'>{d}</span> {s}</span>", .{ v_num, text }, 0) catch @constCast("Error");
            }
            gtk_label_set_markup(@ptrCast(lbl), markup_slice.ptr);
            if (!std.mem.eql(u8, markup_slice, "Error")) allocator.free(markup_slice);
        }
    }

    // 2. Set new highlight
    if (index < labels.items.len) {
        highlighted_index = index;
        const lbl = labels.items[index] orelse return false;
        const v_num = @as(i32, @intCast(index)) + 1;
        const text = verses.items[index];
        
const markup_slice = std.fmt.allocPrintSentinel(allocator, "<span><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='#e0af68'>{d}</span> {s}</span>", .{ v_num, text }, 0) catch "Error";
        const markup: [*:0]const u8 = if (std.mem.eql(u8, markup_slice, "Error")) @ptrCast(@constCast("Error")) else markup_slice.ptr;
        gtk_label_set_markup(@ptrCast(lbl), markup);
        if (!std.mem.eql(u8, std.mem.span(markup), "Error")) allocator.free(std.mem.span(markup));

        // 3. Auto-scroll
        var bounds: [4]f32 = undefined;
        if (study_left_scroll) |sc| {
            if (gtk_widget_compute_bounds(@ptrCast(lbl), @ptrCast(study_left_view), &bounds)) {
                const left_adj = gtk_scrolled_window_get_vadjustment(@ptrCast(sc));
                const page_size = gtk_adjustment_get_page_size(left_adj);
                gtk_adjustment_set_value(left_adj, @max(0, bounds[1] - (page_size / 3.0)));
            }
        }

        // Scroll Right View
        if (study_right_scroll) |sc| {
            var current = gtk_widget_get_first_child(@ptrCast(study_right_view));
            var count: usize = 0;
            while (count < index) : (count += 1) {
                if (current) |c| { current = gtk_widget_get_next_sibling(c); } else break;
            }
            if (current) |right_widget| {
                if (gtk_widget_compute_bounds(right_widget, @ptrCast(study_right_view), &bounds)) {
                    const right_adj = gtk_scrolled_window_get_vadjustment(@ptrCast(sc));
                    const page_size = gtk_adjustment_get_page_size(right_adj);
                    gtk_adjustment_set_value(right_adj, @max(0, bounds[1] - (page_size / 3.0)));
                }
            }
        }
    }
    return false;
}

const PipelineContext = struct {
    verse_idx: usize,
    text: []const u8,
    voice: []const u8,
    speed: f32,
    emotion: []const u8,
    mode: []const u8,
    engine: std.Io,
    
    fn run(p: gpointer) callconv(.c) gpointer {
        const self: *@This() = @ptrCast(@alignCast(p));
        const allocator = std.heap.page_allocator;
        
        const path = tts.generate_speech(self.engine, self.text, self.voice, self.speed, self.emotion, self.mode, false) catch null;
        
        while (tts_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
        if (self.verse_idx < 2000) {
            pipeline_paths[self.verse_idx] = path;
            pipeline_inflight[self.verse_idx] = false;
        }
        tts_lock.store(false, .release);

        allocator.free(self.text);
        allocator.destroy(self);
        return null;
    }
};

var pipeline_paths: [2000]?[]const u8 = [_]?[]const u8{null} ** 2000;
var pipeline_inflight: [2000]bool = [_]bool{false} ** 2000;

fn tts_thread_func(data: gpointer) callconv(.c) gpointer {
    _ = data;
    const allocator = std.heap.page_allocator;
    const io = main_io;
    
    defer {
        tts_playing.store(false, .release);
        if (tts_button_ref) |b| gtk_button_set_label(b, "🔈");
        tts_start_index = 0;
        // Cleanup pipeline
        for (&pipeline_paths) |*p| {
            if (p.*) |path| {
                allocator.free(path);
                p.* = null;
            }
        }
        @memset(&pipeline_inflight, false);
    }

    var current_verse_idx: usize = tts_start_index;

    while (true) {
        if (tts_stop_requested.load(.acquire)) break;
        
        const verses = blk: {
            while (tts_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
            defer tts_lock.store(false, .release);
            if (current_chapter_verses) |v| break :blk v;
            break :blk null;
        };
        if (verses == null or current_verse_idx >= verses.?.items.len) break;

        // 1. Keep the pipeline full (Lookahead 4 verses)
        var lookahead: usize = 0;
        while (lookahead < 4) : (lookahead += 1) {
            const target_idx = current_verse_idx + lookahead;
            if (target_idx >= verses.?.items.len) break;

            while (tts_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
            const needs_trigger = (pipeline_paths[target_idx] == null and !pipeline_inflight[target_idx]);
            if (needs_trigger) pipeline_inflight[target_idx] = true;
            tts_lock.store(false, .release);

            if (needs_trigger) {
                const ctx = allocator.create(PipelineContext) catch continue;
                ctx.* = .{
                    .verse_idx = target_idx,
                    .text = allocator.dupe(u8, verses.?.items[target_idx]) catch "",
                    .voice = app_config.selected_voice,
                    .speed = app_config.speed,
                    .emotion = app_config.emotion,
                    .mode = "speedy", // Default to speedy for sequential flow
                    .engine = io,
                };
                _ = g_thread_new("tts_pipe", &PipelineContext.run, ctx);
            }
        }

        // 2. Wait for current verse audio
        var audio_path: ?[]const u8 = null;
        while (true) {
            if (tts_stop_requested.load(.acquire)) break;
            while (tts_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
            audio_path = pipeline_paths[current_verse_idx];
            tts_lock.store(false, .release);
            
            if (audio_path != null) break;
            g_usleep(10 * 1000); // 10ms poll
        }
        if (tts_stop_requested.load(.acquire)) break;

        // 3. Play current
        _ = g_idle_add(&update_highlight_and_scroll, @ptrFromInt(current_verse_idx));

        if (audio_path) |ap| {
            var play_child = std.process.spawn(io, .{ .argv = &.{ "afplay", ap } }) catch break;
            {
                while (tts_proc_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
                defer tts_proc_lock.store(false, .release);
                if (tts_stop_requested.load(.acquire)) {
                    if (play_child.id) |pid| std.posix.kill(pid, std.posix.SIG.TERM) catch {};
                }
                tts_process = &play_child;
            }
            _ = play_child.wait(io) catch {};
            {
                while (tts_proc_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
                defer tts_proc_lock.store(false, .release);
                if (tts_process == &play_child) tts_process = null;
            }
        }

        if (tts_stop_requested.load(.acquire)) break;
        current_verse_idx += 1;
    }
    return null;
}

// Persistent Config
const Config = struct {
    english_font_size: i32 = 24,
    interlinear_font_size: i32 = 26,
    last_book: [64]u8 = "John".* ++ ([_]u8{0} ** 60),
    last_chapter: i32 = 3,
    last_verse: i32 = 1,
    selected_voice: []const u8 = "lennox",
    speed: f32 = 1.0,
    emotion: []const u8 = "Neutral, clear narration",
    mode: []const u8 = "base",
    tts_mode: []const u8 = "speedy",
    sidebar_width: i32 = 300,
    tts_server_url: []const u8 = "http://127.0.0.1:8000",
    llm_server_url: []const u8 = "http://127.0.0.1:11434",
    tts_timeout_ms: u32 = 5000,
    tts_retry_count: u32 = 3,
};

var app_config = Config{};

fn save_config() void {
    const io = main_io;
    const file = std.Io.Dir.cwd().createFile(io, "data/config.json", .{}) catch return;
    defer file.close(io);
    var buf: [2048]u8 = undefined;
    var f_writer = file.writer(io, &buf);
    
    // Create a temporary struct for stringification to keep JSON clean
    const SaveData = struct {
        english_font_size: i32,
        interlinear_font_size: i32,
        last_book: []const u8,
        last_chapter: i32,
        last_verse: i32,
        selected_voice: []const u8,
        speed: f32,
        emotion: []const u8,
        mode: []const u8,
        tts_mode: []const u8,
        sidebar_width: i32,
    };
    
    const data = SaveData{
        .english_font_size = app_config.english_font_size,
        .interlinear_font_size = app_config.interlinear_font_size,
        .last_book = std.mem.span(@as([*:0]const u8, @ptrCast(&app_config.last_book))),
        .last_chapter = app_config.last_chapter,
        .last_verse = app_config.last_verse,
        .selected_voice = app_config.selected_voice,
        .speed = app_config.speed,
        .emotion = app_config.emotion,
        .mode = app_config.mode,
        .tts_mode = app_config.tts_mode,
        .sidebar_width = app_config.sidebar_width,
    };

    var write_stream: std.json.Stringify = .{ .writer = &f_writer.interface };
    write_stream.write(data) catch return;
}

fn load_config() void {
    const io = main_io;
    const file = std.Io.Dir.cwd().openFile(io, "data/config.json", .{}) catch return;
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var f_reader = file.reader(io, &buf);
    const content = f_reader.interface.allocRemaining(std.heap.page_allocator, std.Io.Limit.limited(4096)) catch return;
    
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, std.heap.page_allocator, content, .{}) catch return;
    if (parsed != .object) return;

    if (parsed.object.get("english_font_size")) |v| app_config.english_font_size = @intCast(v.integer);
    if (parsed.object.get("interlinear_font_size")) |v| app_config.interlinear_font_size = @intCast(v.integer);
    if (parsed.object.get("last_chapter")) |v| app_config.last_chapter = @intCast(v.integer);
    if (parsed.object.get("last_verse")) |v| app_config.last_verse = @intCast(v.integer);
    if (parsed.object.get("last_book")) |v| {
        const name = v.string;
        @memset(&app_config.last_book, 0);
        @memcpy(app_config.last_book[0..@min(name.len, 63)], name[0..@min(name.len, 63)]);
    }
    if (parsed.object.get("speed")) |v| {
        app_config.speed = switch (v) {
            .float => |f| @floatCast(f),
            .integer => |i| @floatFromInt(i),
            else => 1.0,
        };
    }
    if (parsed.object.get("emotion")) |v| {
        app_config.emotion = std.heap.page_allocator.dupe(u8, v.string) catch "";
    }
    if (parsed.object.get("mode")) |v| {
        app_config.mode = std.heap.page_allocator.dupe(u8, v.string) catch "base";
    }
    if (parsed.object.get("tts_mode")) |v| {
        app_config.tts_mode = std.heap.page_allocator.dupe(u8, v.string) catch "speedy";
    }
    if (parsed.object.get("sidebar_width")) |v| {
        app_config.sidebar_width = @intCast(v.integer);
    }
    if (parsed.object.get("selected_voice")) |v| {
        const voice = v.string;
        const voices = [_][]const u8{ "lennox", "tommy", "mari", "jordan", "shamoun", "roumie" };
        for (voices) |v_id| {
            if (std.mem.eql(u8, voice, v_id)) {
                app_config.selected_voice = v_id;
                break;
            }
        }
    }
}

fn update_font_styles() void {
    const allocator = std.heap.page_allocator;
    const css = std.fmt.allocPrintSentinel(allocator,
        \\#left_view, #left_view * {{ 
        \\    font-family: "Iowan Old Style", "Georgia", serif;
        \\    font-size: {d}px; 
        \\    line-height: 1.6;
        \\}}
        \\#left_view {{ padding: 40px 80px; }}
        \\#right_view, #right_view * {{ 
        \\    font-family: "Iowan Old Style", "Georgia", serif;
        \\    font-size: {d}px; 
        \\    line-height: 1.6;
        \\}}
        \\#right_view {{ padding: 40px 80px; }}
        \\.greek, .greek * {{ 
        \\    font-family: "SBL Greek", "Cardo", "Times New Roman", serif;
        \\    font-size: {d}px; 
        \\}}
        \\.hebrew, .hebrew * {{ 
        \\    font-family: "SBL Hebrew", "Cardo", "Times New Roman", serif;
        \\    font-size: {d}px; 
        \\}}
        \\
        \\/* Typography Enhancements */
        \\#chapter_title {{
        \\    font-family: "Baskerville", "Hoefler Text", "Times New Roman", serif;
        \\    font-style: italic;
        \\    font-weight: bold;
        \\    font-size: 42px;
        \\    color: #7aa2f7;
        \\    margin-top: 24px;
        \\    margin-bottom: 48px;
        \\    padding-bottom: 12px;
        \\    border-bottom: 1px solid #2f334d;
        \\    letter-spacing: 1px;
        \\}}
        \\
        \\.verse-label {{
        \\    margin-bottom: 16px;
        \\    margin-left: 20px;
        \\}}
        \\
        \\.verse-num {{
        \\    font-family: "SF Pro Text", sans-serif;
        \\    font-weight: 600;
        \\    color: #565f89;
        \\    margin-right: 4px;
        \\}}
        \\
        \\/* Sidebar & Expander Styling - M3 Liquid Glass */
        \\.sidebar {{
        \\    background: linear-gradient(135deg, rgba(22, 22, 30, 0.9), rgba(26, 27, 38, 0.8));
        \\    border-right: 1px solid rgba(255, 255, 255, 0.1);
        \\    padding: 12px;
        \\}}
        \\
        \\.sidebar-expander {{
        \\    font-family: "SF Pro Display", sans-serif;
        \\    font-weight: 700;
        \\    color: #bb9af7;
        \\    background: rgba(255, 255, 255, 0.03);
        \\    border-radius: 10px;
        \\    margin-bottom: 8px;
        \\    padding: 2px;
        \\}}
        \\
        \\.sidebar-label {{
        \\    font-family: "SF Pro Text", sans-serif;
        \\    font-size: 13px;
        \\    color: #cfc9c2;
        \\    background: rgba(255, 255, 255, 0.05);
        \\    border: 1px solid rgba(255, 255, 255, 0.08);
        \\    border-radius: 12px;
        \\    padding: 12px;
        \\    margin: 6px 2px;
        \\    box-shadow: 0 4px 15px rgba(0,0,0,0.2), inset 0 0 10px rgba(255,255,255,0.02);
        \\    line-height: 1.5;
        \\}}
        \\
        \\.note-editor {{
        \\    background: rgba(0, 0, 0, 0.3);
        \\    color: #c0caf5;
        \\    border: 1px solid rgba(255, 255, 255, 0.1);
        \\    border-radius: 12px;
        \\    padding: 12px;
        \\    font-family: "SF Pro Text", sans-serif;
        \\    font-size: 13px;
        \\    margin: 4px 2px;
        \\}}
        \\
        \\.m3-button {{
        \\    background: linear-gradient(to bottom, rgba(122, 162, 247, 0.2), rgba(122, 162, 247, 0.1));
        \\    color: #7aa2f7;
        \\    border: 1px solid rgba(122, 162, 247, 0.4);
        \\    border-radius: 24px;
        \\    padding: 10px 20px;
        \\    font-weight: 600;
        \\    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        \\    text-shadow: 0 1px 2px rgba(0,0,0,0.5);
        \\}}
        \\.m3-button:hover {{
        \\    background: linear-gradient(to bottom, rgba(122, 162, 247, 0.3), rgba(122, 162, 247, 0.2));
        \\    border-color: #7aa2f7;
        \\    box-shadow: 0 0 15px rgba(122, 162, 247, 0.3);
        \\    transform: translateY(-1px);
        \\}}
        \\
        \\/* Pastel Candy Highlight Buttons */
        \\.candy-btn {{
        \\    border-radius: 50%;
        \\    border: none;
        \\    min-width: 32px;
        \\    min-height: 32px;
        \\    margin: 4px;
        \\    transition: all 0.2s cubic-bezier(0.175, 0.885, 0.32, 1.275);
        \\    box-shadow: 0 2px 4px rgba(0,0,0,0.3);
        \\}}
        \\.candy-btn:hover {{
        \\    transform: scale(1.15) rotate(5deg);
        \\    box-shadow: 0 4px 12px rgba(0,0,0,0.4);
        \\}}
        \\.h-yellow {{ background-color: #ffdfa3; }}
        \\.h-green  {{ background-color: #b9f27c; }}
        \\.h-blue   {{ background-color: #7da6ff; }}
        \\.h-red    {{ background-color: #ff7a93; }}
        \\.h-purple {{ background-color: #d0b3ff; }}
        \\.h-cyan   {{ background-color: #89ddff; }}
        \\.h-orange {{ background-color: #ffc0b9; }}
        \\.h-clear  {{ 
        \\    background-color: #2f334d; 
        \\    color: #c0caf5; 
        \\    font-size: 10px; 
        \\    border-radius: 10px; 
        \\    min-width: 50px;
        \\}}
        \\
        \\.save-success {{
        \\    background-color: #9ece6a;
        \\    color: #1a1b26;
        \\    transition: all 0.3s ease;
        \\}}
        \\
        \\.status-bar {{
        \\    background-color: #16161e;
        \\    border-top: 1px solid #2f334d;
        \\    padding: 4px 12px;
        \\}}
        \\
        \\.status-bar-label {{
        \\    font-family: "SF Pro Text", monospace;
        \\    font-size: 11px;
        \\    color: #565f89;
        \\}}
        \\
        \\/* Spotlight Search Window */
        \\.spotlight-window {{
        \\    background-color: #24283b;
        \\    border-radius: 12px;
        \\    border: 1px solid #414868;
        \\    box-shadow: 0 20px 50px rgba(0,0,0,0.6);
        \\}}
        \\
        \\.spotlight-entry {{
        \\    background: #1a1b26;
        \\    border: none;
        \\    border-bottom: 1px solid #414868;
        \\    font-family: "SF Pro Display", sans-serif;
        \\    font-size: 20px;
        \\    padding: 16px;
        \\    color: #c0caf5;
        \\}}
        \\.spotlight-entry:focus {{
        \\    box-shadow: none;
        \\}}
        \\
        \\.spotlight-results {{
        \\    background: transparent;
        \\}}
        \\
        \\.spotlight-results row {{
        \\    padding: 12px 16px;
        \\    border-bottom: 1px solid #2f334d;
        \\    transition: background 0.1s;
        \\}}
        \\
        \\.spotlight-results row:hover {{
        \\    background: #2f334d;
        \\}}
        \\
        \\.spotlight-results row label {{
        \\    font-size: 16px;
        \\    color: #c0caf5;
        \\}}
        \\
        \\.search-trigger-btn {{
        \\    background: #1a1b26;
        \\    color: #565f89;
        \\    border: 1px solid #414868;
        \\    border-radius: 6px;
        \\    padding: 6px 12px;
        \\    font-size: 14px;
        \\}}
        \\
        \\.search-trigger-btn:hover {{
        \\    border-color: #7aa2f7;
        \\    color: #c0caf5;
        \\}}
    , .{
        app_config.english_font_size,
        app_config.interlinear_font_size,
        app_config.interlinear_font_size,
        app_config.interlinear_font_size + 4,
    }, 0) catch return;
    defer allocator.free(css);
    gtk_css_provider_load_from_data(font_provider, css, -1);
}

fn on_font_adjust(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const adjust: i32 = @intCast(@intFromPtr(user_data));
    switch (adjust) {
        1 => app_config.english_font_size += 2,
        2 => app_config.english_font_size -= 2,
        3 => app_config.interlinear_font_size += 2,
        4 => app_config.interlinear_font_size -= 2,
        else => {},
    }
    update_font_styles();
    save_config();
    if (main_status_bar) |sb| sb.updateStatus("Font size adjusted", false);
}

fn clear_box(box: ?*GtkBox) void {
    if (box == null) return;
    while (gtk_widget_get_first_child(@ptrCast(box))) |child| {
        gtk_box_remove(box, child);
    }
}

fn on_scroll_changed(adj: ?*GtkAdjustment, user_data: gpointer) callconv(.c) void {
    const target_adj: ?*GtkAdjustment = @ptrCast(user_data);
    const value = gtk_adjustment_get_value(adj);
    if (@abs(value - gtk_adjustment_get_value(target_adj)) > 1.0) {
        gtk_adjustment_set_value(target_adj, value);
    }
}

fn on_speaker_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = user_data;
    const now = g_get_monotonic_time();
    const diff = now - last_speaker_click_time;
    last_speaker_click_time = now;
    tts_button_ref = btn;

    // Double click (within 300ms) - Stop everything
    if (diff < 300000) {
        tts_stop_requested.store(true, .release);
        {
            while (tts_proc_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
            defer tts_proc_lock.store(false, .release);
            if (tts_process) |p| {
                if (p.id) |pid| {
                    if (pid != 0) std.posix.kill(pid, std.posix.SIG.TERM) catch {};
                }
            }
        }
        // Don't set tts_playing = false yet; the thread will do it when it actually stops.
        return;
    }

    if (tts_playing.load(.acquire)) {
        // Stop current
        tts_stop_requested.store(true, .release);
        {
            while (tts_proc_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
            defer tts_proc_lock.store(false, .release);
            if (tts_process) |p| {
                if (p.id) |pid| {
                    if (pid != 0) std.posix.kill(pid, std.posix.SIG.TERM) catch {};
                }
            }
        }
        // Again, don't set tts_playing = false; the thread will handle it.
        // We can however update the UI to show we're waiting for it to stop.
        gtk_button_set_label(btn.?, "🔈");
    } else {
        if (current_chapter_verses == null or current_chapter_verses.?.items.len == 0) return;
        
        // Ensure we don't start multiple threads if called quickly
        if (tts_playing.swap(true, .acquire)) return;
        
        tts_stop_requested.store(false, .release);
        gtk_button_set_label(btn.?, "⏳");
        _ = g_thread_new("tts_thread", &tts_thread_func, null);
    }
}

fn on_parallel_toggled(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const is_visible = gtk_widget_get_visible(right_scroll_pane);
    const new_visibility = !is_visible;
    gtk_widget_set_visible(right_scroll_pane, new_visibility);
    if (f_right_plus_btn) |b| gtk_widget_set_visible(b, new_visibility);
    if (f_right_minus_btn) |b| gtk_widget_set_visible(b, new_visibility);
}

fn on_sidebar_toggled(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    if (main_sidebar) |sb| {
        const is_visible = gtk_widget_get_visible(sb.box);
        gtk_widget_set_visible(sb.box, !is_visible);
    }
}

fn on_interlinear_word_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const strongs_raw: [*:0]const u8 = @ptrCast(user_data);
    const allocator = std.heap.page_allocator;
    
    if (bible.get_lexicon_detail(allocator, db.?, std.mem.span(strongs_raw)) catch null) |detail| {
        defer {
            allocator.free(detail.strongs);
            allocator.free(detail.lemma);
            allocator.free(detail.transliteration);
            allocator.free(detail.definition);
            allocator.free(detail.language);
        }
        const info = std.fmt.allocPrintSentinel(allocator, 
            "<span size='xx-large' color='#7aa2f7'><b>{s}</b></span> (<span color='#bb9af7'>{s}</span>)\n" ++
            "<span size='large' color='#e0af68'><i>{s}</i></span>\n\n" ++
            "<span color='#c0caf5'>{s}</span>",
            .{ detail.strongs, detail.lemma, detail.transliteration, detail.definition }, 0) catch "Error";
        defer allocator.free(info);
        gtk_label_set_markup(word_study_label, info);
    } else {
        const info = std.fmt.allocPrintSentinel(allocator, "<span size='xx-large' color='#7aa2f7'><b>{s}</b></span>\n\n<span color='#565f89'>[Definition not cached]</span>", .{strongs_raw}, 0) catch "Error";
        defer allocator.free(info);
        gtk_label_set_markup(word_study_label, info);
    }
}

fn add_interactive_word(flow: ?*GtkFlowBox, word: [*:0]const u8, strongs: [*:0]const u8, trans: [*:0]const u8) void {
    const word_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_add_css_class(@ptrCast(word_box), "interlinear-word");
    const word_btn = gtk_button_new_with_label(word);
    gtk_widget_add_css_class(word_btn, "interlinear-word-btn");
    const strongs_span = std.mem.span(strongs);
    if (strongs_span.len > 0) {
        if (strongs_span[0] == 'G') gtk_widget_add_css_class(word_btn, "greek")
        else if (strongs_span[0] == 'H') gtk_widget_add_css_class(word_btn, "hebrew");
    }
    const persistent_strongs = g_strdup(strongs);
    _ = g_signal_connect_data(word_btn, "clicked", @ptrCast(&on_interlinear_word_clicked), persistent_strongs, null, 0);
    const trans_lbl = gtk_label_new(trans);
    gtk_widget_add_css_class(trans_lbl, "interlinear-english");
    gtk_box_append(@ptrCast(word_box), word_btn);
    gtk_box_append(@ptrCast(word_box), trans_lbl);
    gtk_flow_box_insert(flow, word_box, -1);
}

fn load_chapter_into_study(book: []const u8, chapter: i32, start_verse: i32) void {
    const allocator = std.heap.page_allocator;

    const loading_msg = std.fmt.allocPrint(allocator, "Loading {s} {d}...", .{ book, chapter }) catch "Loading...";
    if (main_status_bar) |sb| sb.updateStatus(loading_msg, false);
    if (!std.mem.eql(u8, loading_msg, "Loading...")) allocator.free(loading_msg);

    const sql = std.fmt.allocPrintSentinel(allocator, "SELECT verse, text FROM verses WHERE book='{s}' AND chapter={d} ORDER BY verse ASC", .{ book, chapter }, 0) catch return;
    defer allocator.free(sql);
    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db.?, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        clear_box(study_left_view);
        clear_box(study_right_view);
        
        {
            while (tts_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {}
            defer tts_lock.store(false, .release);
            if (current_chapter_verses) |*list| {
                for (list.items) |v| allocator.free(v);
                list.clearAndFree(allocator);
            } else {
                current_chapter_verses = std.ArrayListUnmanaged([]const u8).empty;
            }
        }

        if (verse_labels) |*list| {
            list.clearAndFree(allocator);
        } else {
            verse_labels = std.ArrayListUnmanaged(?*GtkWidget).empty;
        }
        highlighted_index = null;

        // Fetch permanent highlights for this chapter
        var highlights = bible.get_chapter_highlights(allocator, db.?, book, chapter) catch std.AutoHashMapUnmanaged(i32, []const u8).empty;
        defer {
            var it = highlights.iterator();
            while (it.next()) |entry| allocator.free(entry.value_ptr.*);
            highlights.deinit(allocator);
        }

        const title_text = std.fmt.allocPrintSentinel(allocator, "{s} {d}", .{ book, chapter }, 0) catch "Error";
        const title = gtk_label_new(null);
        gtk_label_set_markup(@ptrCast(title), title_text);
        gtk_widget_set_name(title, "chapter_title");
        gtk_label_set_xalign(@ptrCast(title), 0.5); // Center the title
        gtk_box_append(study_left_view, title);
        while (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const verse_num = sqlite3_column_int(stmt.?, 0);
            const text = sqlite3_column_text(stmt.?, 1);
            
            const v_text = std.mem.span(text.?);
            current_chapter_verses.?.append(allocator, allocator.dupe(u8, v_text) catch "") catch {};

            // Priority: Active selection highlight for the number, background for the text
            const v_num_color = if (verse_num == start_verse) "#e0af68" else "#7aa2f7";
            const bg_color = highlights.get(verse_num);

            var verse_markup_slice: [:0]u8 = undefined;
            if (bg_color) |bg| {
                verse_markup_slice = std.fmt.allocPrintSentinel(allocator, "<span background='{s}'><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='{s}'>{d}</span> {s}</span>", .{ bg, v_num_color, verse_num, text.? }, 0) catch @constCast("Error");
            } else {
                verse_markup_slice = std.fmt.allocPrintSentinel(allocator, "<span><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='{s}'>{d}</span> {s}</span>", .{ v_num_color, verse_num, text.? }, 0) catch @constCast("Error");
            }
            defer if (!std.mem.eql(u8, verse_markup_slice, "Error")) allocator.free(verse_markup_slice);
            const lbl = gtk_label_new(null);
            gtk_label_set_markup(@ptrCast(lbl), verse_markup_slice.ptr);
            gtk_widget_add_css_class(@ptrCast(lbl), "verse-label");
            gtk_label_set_wrap(@ptrCast(lbl), true);
            gtk_label_set_xalign(@ptrCast(lbl), 0.0);
            gtk_box_append(study_left_view, lbl);
            verse_labels.?.append(allocator, @ptrCast(lbl)) catch {};

            // Add Double-Click Gesture for TTS
            const db_click = gtk_gesture_click_new();
            gtk_gesture_single_set_button(db_click, 1); // Left button
            _ = g_signal_connect_data(db_click, "pressed", @ptrCast(&on_verse_double_click), @ptrFromInt(current_chapter_verses.?.items.len - 1), null, 0);
            gtk_widget_add_controller(@ptrCast(lbl), @ptrCast(db_click));

            // Add Right-Click Gesture for Re-rendering
            const gesture = gtk_gesture_click_new();
            gtk_gesture_single_set_button(gesture, 3); // Right button
            _ = g_signal_connect_data(gesture, "pressed", @ptrCast(&on_verse_right_click), @ptrFromInt(current_chapter_verses.?.items.len - 1), null, 0);
            gtk_widget_add_controller(@ptrCast(lbl), @ptrCast(gesture));

            // Add Long-Press Gesture for Notes
            const long_press = gtk_gesture_long_press_new();
            _ = g_signal_connect_data(long_press, "pressed", @ptrCast(&on_verse_long_press), @ptrFromInt(current_chapter_verses.?.items.len - 1), null, 0);
            gtk_widget_add_controller(@ptrCast(lbl), @ptrCast(long_press));

            const flow = gtk_flow_box_new();
            gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
            const strongs_sql = std.fmt.allocPrintSentinel(allocator, "SELECT strongs FROM interlinear WHERE book='{s}' AND chapter={d} AND verse={d} LIMIT 1", .{ book, chapter, verse_num }, 0) catch continue;
            defer allocator.free(strongs_sql);
            var s_stmt: ?*sqlite3_stmt = null;
            if (sqlite3_prepare_v2(db.?, strongs_sql, -1, @ptrCast(&s_stmt), null) == SQLITE_OK) {
                if (sqlite3_step(s_stmt.?) == SQLITE_ROW) {
                    const s_txt = sqlite3_column_text(s_stmt.?, 0) orelse "";
                    if (std.mem.span(s_txt).len > 0 and std.mem.span(s_txt)[0] == 'H') gtk_widget_set_direction(@ptrCast(flow), GTK_TEXT_DIR_RTL);
                }
                _ = sqlite3_finalize(s_stmt.?);
            }
            gtk_box_append(study_right_view, flow);
            var i_stmt: ?*sqlite3_stmt = null;
            const i_sql = std.fmt.allocPrintSentinel(allocator, "SELECT original_text, strongs, translation FROM interlinear WHERE book='{s}' AND chapter={d} AND verse={d} ORDER BY word_index ASC", .{ book, chapter, verse_num }, 0) catch continue;
            defer allocator.free(i_sql);
            if (sqlite3_prepare_v2(db.?, i_sql, -1, @ptrCast(&i_stmt), null) == SQLITE_OK) {
                var found = false;
                while (sqlite3_step(i_stmt.?) == SQLITE_ROW) {
                    found = true;
                    add_interactive_word(@ptrCast(flow), sqlite3_column_text(i_stmt.?, 0) orelse "", sqlite3_column_text(i_stmt.?, 1) orelse "", sqlite3_column_text(i_stmt.?, 2) orelse "");
                }
                _ = sqlite3_finalize(i_stmt.?);
                if (!found) gtk_flow_box_insert(@ptrCast(flow), gtk_label_new("[Interlinear not cached]"), -1);
            }
        }
        _ = sqlite3_finalize(stmt.?);

        const verse_count = if (current_chapter_verses) |v| v.items.len else 0;
        const loaded_msg = std.fmt.allocPrint(allocator, "Loaded {s} {d} ({d} verses)", .{ book, chapter, verse_count }) catch "Loaded.";
        if (main_status_bar) |sb| sb.updateStatus(loaded_msg, false);
        if (!std.mem.eql(u8, loaded_msg, "Loaded.")) allocator.free(loaded_msg);

        if (book.ptr != &cur_book_name) { @memcpy(cur_book_name[0..book.len], book); cur_book_name[book.len] = 0; }
        cur_chapter = chapter;

        // Save to config
        if (book.ptr != &app_config.last_book) {
            @memset(&app_config.last_book, 0);
            @memcpy(app_config.last_book[0..@min(book.len, 63)], book[0..@min(book.len, 63)]);
        }
        app_config.last_chapter = chapter;
        app_config.last_verse = start_verse;
        save_config();

        gtk_notebook_set_current_page(main_notebook, 1);
    } else {
        const failed_msg = std.fmt.allocPrint(allocator, "Failed to load {s} {d}", .{ book, chapter }) catch "Failed to load.";
        if (main_status_bar) |sb| sb.updateStatus(failed_msg, true);
        if (!std.mem.eql(u8, failed_msg, "Failed to load.")) allocator.free(failed_msg);
    }
}

fn on_prev_chapter_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const book = std.mem.span(@as([*:0]u8, @ptrCast(&cur_book_name)));
    if (cur_chapter > 1) load_chapter_into_study(book, cur_chapter - 1, 1)
    else for (BIBLE_BOOKS, 0..) |b, i| if (std.mem.eql(u8, std.mem.span(b.name), book)) {
        if (i > 0) load_chapter_into_study(std.mem.span(BIBLE_BOOKS[i-1].name), BIBLE_BOOKS[i-1].chapters, 1);
        break;
    };
}

fn on_next_chapter_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const book = std.mem.span(@as([*:0]u8, @ptrCast(&cur_book_name)));
    var max: i32 = 21; var found: ?usize = null;
    for (BIBLE_BOOKS, 0..) |b, i| if (std.mem.eql(u8, std.mem.span(b.name), book)) { max = b.chapters; found = i; break; };
    if (cur_chapter < max) load_chapter_into_study(book, cur_chapter + 1, 1)
    else if (found) |idx| if (idx + 1 < BIBLE_BOOKS.len) load_chapter_into_study(std.mem.span(BIBLE_BOOKS[idx+1].name), 1, 1);
}

fn on_verse_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    load_chapter_into_study(std.mem.span(@as([*:0]u8, @ptrCast(&cur_book_name))), cur_chapter, @intCast(@intFromPtr(user_data)));
    gtk_window_destroy(selection_dialog); selection_dialog = null;
}

fn on_chapter_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const chapter: i32 = @intCast(@intFromPtr(user_data));
    cur_chapter = chapter;
    const book_name = std.mem.span(@as([*:0]u8, @ptrCast(&cur_book_name)));
    const allocator = std.heap.page_allocator;
    const title = std.fmt.allocPrintSentinel(allocator, "<b>{s} {d}</b> - Select Verse", .{book_name, chapter}, 0) catch "Select Verse";
    defer allocator.free(title);
    gtk_label_set_markup(modal_title, title);
    const flow = gtk_flow_box_new();
    gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
    gtk_flow_box_set_min_children_per_line(@ptrCast(flow), 5);
    gtk_widget_add_css_class(flow, "selection-grid");
    gtk_widget_add_css_class(flow, "compact-grid");
    var stmt: ?*sqlite3_stmt = null;
    const sql = std.fmt.allocPrintSentinel(allocator, "SELECT DISTINCT verse FROM verses WHERE book='{s}' AND chapter={d} ORDER BY verse ASC", .{ book_name, chapter }, 0) catch return;
    defer allocator.free(sql);
    if (sqlite3_prepare_v2(db.?, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        while (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const v = sqlite3_column_int(stmt.?, 0);
            const v_str = std.fmt.allocPrintSentinel(allocator, "{d}", .{v}, 0) catch "1";
            defer allocator.free(v_str);
            const v_btn = gtk_button_new_with_label(v_str);
            _ = g_signal_connect_data(v_btn, "clicked", @ptrCast(&on_verse_clicked), @ptrFromInt(@as(usize, @intCast(v))), null, 0);
            gtk_flow_box_insert(@ptrCast(flow), v_btn, -1);
        }
        _ = sqlite3_finalize(stmt.?);
    }
    const scroll = gtk_scrolled_window_new();
    gtk_widget_set_vexpand(scroll, true);
    gtk_scrolled_window_set_child(@ptrCast(scroll), flow);
    if (gtk_stack_get_child_by_name(modal_stack, "verses")) |old| gtk_stack_remove(modal_stack, old);
    gtk_stack_add_named(modal_stack, scroll, "verses");
    gtk_stack_set_visible_child_name(modal_stack, "verses");
}

fn on_book_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const book_name: [*:0]const u8 = @ptrCast(user_data);
    @memcpy(cur_book_name[0 .. std.mem.len(book_name) + 1], book_name[0 .. std.mem.len(book_name) + 1]);
    const allocator = std.heap.page_allocator;
    const title = std.fmt.allocPrintSentinel(allocator, "<b>{s}</b> - Select Chapter", .{book_name}, 0) catch "Select Chapter";
    defer allocator.free(title);
    gtk_label_set_markup(modal_title, title);
    const flow = gtk_flow_box_new();
    gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
    gtk_flow_box_set_min_children_per_line(@ptrCast(flow), 5);
    gtk_widget_add_css_class(flow, "selection-grid");
    gtk_widget_add_css_class(flow, "compact-grid");
    var stmt: ?*sqlite3_stmt = null;
    const sql = std.fmt.allocPrintSentinel(allocator, "SELECT DISTINCT chapter FROM verses WHERE book='{s}' ORDER BY chapter ASC", .{ book_name }, 0) catch return;
    defer allocator.free(sql);
    if (sqlite3_prepare_v2(db.?, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        while (sqlite3_step(stmt.?) == SQLITE_ROW) {
            const ch = sqlite3_column_int(stmt.?, 0);
            const ch_str = std.fmt.allocPrintSentinel(allocator, "{d}", .{ch}, 0) catch "1";
            defer allocator.free(ch_str);
            const ch_btn = gtk_button_new_with_label(ch_str);
            _ = g_signal_connect_data(ch_btn, "clicked", @ptrCast(&on_chapter_clicked), @ptrFromInt(@as(usize, @intCast(ch))), null, 0);
            gtk_flow_box_insert(@ptrCast(flow), ch_btn, -1);
        }
        _ = sqlite3_finalize(stmt.?);
    }
    const scroll = gtk_scrolled_window_new();
    gtk_widget_set_vexpand(scroll, true);
    gtk_scrolled_window_set_child(@ptrCast(scroll), flow);
    if (gtk_stack_get_child_by_name(modal_stack, "chapters")) |old| gtk_stack_remove(modal_stack, old);
    gtk_stack_add_named(modal_stack, scroll, "chapters");
    gtk_stack_set_visible_child_name(modal_stack, "chapters");
}

fn on_modal_back_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const current = gtk_stack_get_visible_child_name(modal_stack);
    if (current == null) return;
    const allocator = std.heap.page_allocator;
    if (std.mem.orderZ(u8, current.?, "verses") == .eq) {
        gtk_stack_set_visible_child_name(modal_stack, "chapters");
        const book_name = std.mem.span(@as([*:0]u8, @ptrCast(&cur_book_name)));
        const title = std.fmt.allocPrintSentinel(allocator, "<b>{s}</b> - Select Chapter", .{book_name}, 0) catch "Select Chapter";
        defer allocator.free(title);
        gtk_label_set_markup(modal_title, title);
    } else if (std.mem.orderZ(u8, current.?, "chapters") == .eq) {
        gtk_stack_set_visible_child_name(modal_stack, "books");
        gtk_label_set_markup(modal_title, "<b>Select Book</b>");
    }
}

var persistent_book_names: [150][64]u8 = undefined;

fn on_settings_save(config: gtk.settings_dialog.SettingsConfig) void {
    app_config.tts_server_url = config.tts_url;
    app_config.tts_timeout_ms = config.tts_timeout_ms;
    app_config.tts_retry_count = config.tts_retry_count;
    app_config.llm_server_url = config.llm_url;
    save_config();
    if (main_status_bar) |sb| sb.updateStatus("Settings saved", false);
}

fn on_settings_btn_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    _ = user_data;
    const allocator = std.heap.page_allocator;
    const dialog = gtk.settings_dialog.SettingsDialog.init(
        allocator,
        main_window,
        .{
            .onSave = on_settings_save,
            .allocator = allocator,
        },
        .{
            .tts_url = app_config.tts_server_url,
            .tts_timeout_ms = app_config.tts_timeout_ms,
            .tts_retry_count = @intCast(app_config.tts_retry_count),
            .llm_url = app_config.llm_server_url,
        },
        main_io,
    );
    dialog.show();
}

fn on_passage_btn_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    if (selection_dialog != null) return;
    selection_dialog = @ptrCast(gtk_window_new());
    gtk_window_set_title(selection_dialog, "Go to Passage");
    gtk_window_set_default_size(selection_dialog, 900, 750);
    gtk_window_set_modal(selection_dialog, true);
    gtk_window_set_transient_for(selection_dialog, main_window);
    const root_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_window_set_child(selection_dialog, root_box);
    const header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 15);
    gtk_widget_add_css_class(header, "nav-header");
    gtk_box_append(@ptrCast(root_box), header);
    const back_btn = gtk_button_new_with_label("Back");
    _ = g_signal_connect_data(back_btn, "clicked", @ptrCast(&on_modal_back_clicked), null, null, 0);
    gtk_box_append(@ptrCast(header), back_btn);
    modal_title = @ptrCast(gtk_label_new("<b>Select Book</b>"));
    gtk_label_set_markup(modal_title, "<b>Select Book</b>");
    gtk_box_append(@ptrCast(header), @ptrCast(modal_title));
    modal_stack = @ptrCast(gtk_stack_new());
    gtk_stack_set_transition_type(modal_stack, GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT);
    gtk_widget_set_vexpand(@ptrCast(modal_stack), true);
    gtk_box_append(@ptrCast(root_box), @ptrCast(modal_stack));
    const book_scroll = gtk_scrolled_window_new();
    gtk_widget_set_vexpand(book_scroll, true);
    const book_vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 15);
    gtk_widget_add_css_class(book_vbox, "selection-grid");
    gtk_scrolled_window_set_child(@ptrCast(book_scroll), book_vbox);
    var available_books = std.StringHashMap(void).init(std.heap.page_allocator);
    defer {
        var it = available_books.keyIterator();
        while (it.next()) |key| std.heap.page_allocator.free(key.*);
        available_books.deinit();
    }
    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db.?, "SELECT DISTINCT book FROM verses", -1, @ptrCast(&stmt), null) == SQLITE_OK) {
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
    const sections = [_]struct { label: [*:0]const u8, testament: Testament }{
        .{ .label = "Old Testament", .testament = .Old },
        .{ .label = "New Testament", .testament = .New },
        .{ .label = "Ethiopian Church Order", .testament = .EthiopiaExpanded },
    };
    var p_idx: usize = 0;
    for (sections) |sec| {
        const lbl = gtk_label_new(null);
        gtk_label_set_markup(@ptrCast(lbl), std.fmt.allocPrintSentinel(std.heap.page_allocator, "<span size='large' weight='bold' color='#7aa2f7'>{s}</span>", .{sec.label}, 0) catch "Err");
        gtk_label_set_xalign(@ptrCast(lbl), 0.0);
        gtk_box_append(@ptrCast(book_vbox), lbl);
        const flow = gtk_flow_box_new();
        gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
        gtk_box_append(@ptrCast(book_vbox), flow);
        for (BIBLE_BOOKS) |book| {
            if (book.testament != sec.testament) continue;
            const len = std.mem.len(book.name);
            @memcpy(persistent_book_names[p_idx][0..len], book.name[0..len]);
            persistent_book_names[p_idx][len] = 0;
            const p_ptr = @as(gpointer, @ptrCast(&persistent_book_names[p_idx]));
            const book_btn = gtk_button_new_with_label(book.name);
            if (available_books.contains(std.mem.span(book.name))) {
                gtk_widget_add_css_class(book_btn, "cached");
                gtk_widget_set_sensitive(book_btn, true);
            } else {
                gtk_widget_add_css_class(book_btn, "uncached");
                gtk_widget_set_sensitive(book_btn, false);
            }
            _ = g_signal_connect_data(book_btn, "clicked", @ptrCast(&on_book_clicked), p_ptr, null, 0);
            gtk_flow_box_insert(@ptrCast(flow), book_btn, -1);
            p_idx += 1;
        }
    }
    gtk_stack_add_named(modal_stack, book_scroll, "books");
    gtk_window_present(selection_dialog);
}

fn on_main_window_key(controller: ?*anyopaque, keyval: u32, keycode: u32, state: u32, user_data: gpointer) callconv(.c) bool {
    _ = controller; _ = keycode; _ = user_data;
    const GDK_MOD_COMMAND = 1 << 28; // Usually Cmd on macOS
    const GDK_KEY_k = 107;
    const GDK_KEY_K = 75;
    const GDK_KEY_f = 102;
    const GDK_KEY_F = 70;
    
    if ((state & GDK_MOD_COMMAND) != 0) {
        if (keyval == GDK_KEY_k or keyval == GDK_KEY_K or keyval == GDK_KEY_f or keyval == GDK_KEY_F) {
            on_search_trigger_clicked(null, null);
            return true;
        }
    }
    return false;
}

fn on_search_close_request(window: ?*anyopaque, user_data: gpointer) callconv(.c) bool {
    _ = user_data;
    gtk_widget_set_visible(@ptrCast(window), false);
    return true; // Inhibit destruction
}

fn on_search_result_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const res: *SearchResult = @ptrCast(@alignCast(user_data));
    const book = std.mem.span(@as([*:0]const u8, @ptrCast(&res.book)));
    load_chapter_into_study(book, res.chapter, res.verse);
    if (search_window) |w| gtk_widget_set_visible(@ptrCast(w), false);
}

fn perform_search(span: []const u8) void {
    if (span.len < 2) return;
    const allocator = std.heap.page_allocator;

    const searching_msg = std.fmt.allocPrint(allocator, "Searching for '{s}'...", .{span}) catch "Searching...";
    if (main_status_bar) |sb| sb.updateStatus(searching_msg, false);
    if (!std.mem.eql(u8, searching_msg, "Searching...")) allocator.free(searching_msg);

    gtk_list_box_remove_all(search_results_list);
    var total_results: usize = 0;

    // 1. Try Reference Parsing
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
            for (BIBLE_ABBREVIATIONS) |abbr| {
                if (std.ascii.eqlIgnoreCase(abbr.abbr, book_query)) {
                    resolved_book = abbr.full;
                    break;
                }
            }
            if (resolved_book == null) {
                for (BIBLE_BOOKS) |b| {
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
                const label_text = std.fmt.allocPrintSentinel(allocator, "<b>Go to: {s} {d}:{d}</b>", .{rb, chapter.?, verse orelse 1}, 0) catch "Err";
                defer allocator.free(label_text);

                const res = &persistent_search_results[0];
                @memset(&res.book, 0);
                @memcpy(res.book[0..rb.len], rb);
                res.chapter = chapter.?;
                res.verse = verse orelse 1;

                const row_btn = gtk_button_new_with_label("");
                const lbl = gtk_label_new(null);
                gtk_label_set_markup(@ptrCast(lbl), label_text);
                gtk_button_set_child(@ptrCast(row_btn), lbl);
                _ = g_signal_connect_data(row_btn, "clicked", @ptrCast(&on_search_result_clicked), res, null, 0);
                gtk_list_box_append(search_results_list, row_btn);
                total_results += 1;
            }
        }
    }

    // 2. Keyword Search
    const sql = std.fmt.allocPrintSentinel(allocator, "SELECT book, chapter, verse, text FROM verses WHERE text LIKE '%{s}%' LIMIT 40", .{span}, 0) catch {
        if (main_status_bar) |sb| sb.updateStatus("Search failed", true);
        return;
    };
    defer allocator.free(sql);

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db.?, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        var count: usize = 0;
        while (sqlite3_step(stmt.?) == SQLITE_ROW and count < 40) {
            const b = sqlite3_column_text(stmt.?, 0);
            const c = sqlite3_column_int(stmt.?, 1);
            const v = sqlite3_column_int(stmt.?, 2);
            const t = sqlite3_column_text(stmt.?, 3);

            const res = &persistent_search_results[total_results]; 
            const b_span = std.mem.span(b.?);
            @memset(&res.book, 0);
            @memcpy(res.book[0..b_span.len], b_span);
            res.chapter = c;
            res.verse = v;

            const text_span = std.mem.span(t.?);
            var highlighted = std.ArrayListUnmanaged(u8).empty;
            defer highlighted.deinit(allocator);
            var last: usize = 0;
            var search_idx: usize = 0;
            while (std.ascii.indexOfIgnoreCase(text_span[search_idx..], span)) |match_idx| {
                const start = search_idx + match_idx;
                highlighted.appendSlice(allocator, text_span[last..start]) catch {};
                highlighted.appendSlice(allocator, "<span color='#7dcfff' weight='bold'>") catch {};
                highlighted.appendSlice(allocator, text_span[start..start+span.len]) catch {};
                highlighted.appendSlice(allocator, "</span>") catch {};
                last = start + span.len;
                search_idx = last;
                if (search_idx >= text_span.len) break;
            }
            highlighted.appendSlice(allocator, text_span[last..]) catch {};

            const label_text = std.fmt.allocPrintSentinel(allocator, "<b>{s} {d}:{d}</b> - {s}", .{b.?, c, v, highlighted.items}, 0) catch "Err";
            defer allocator.free(label_text);

            const row_btn = gtk_button_new_with_label("");
            const lbl = gtk_label_new(null);
            gtk_label_set_markup(@ptrCast(lbl), label_text);
            gtk_label_set_xalign(@ptrCast(lbl), 0.0);
            gtk_label_set_wrap(@ptrCast(lbl), true);
            gtk_button_set_child(@ptrCast(row_btn), lbl);

            _ = g_signal_connect_data(row_btn, "clicked", @ptrCast(&on_search_result_clicked), res, null, 0);
            gtk_list_box_append(search_results_list, row_btn);
            count += 1;
            total_results += 1;
        }
        _ = sqlite3_finalize(stmt.?);
    }

    if (total_results > 0) {
        const found_msg = std.fmt.allocPrint(allocator, "Found {d} results", .{total_results}) catch "Found results";
        if (main_status_bar) |sb| sb.updateStatus(found_msg, false);
        if (!std.mem.eql(u8, found_msg, "Found results")) allocator.free(found_msg);
    } else {
        if (main_status_bar) |sb| sb.updateStatus("No results found", false);
    }
}
fn on_search_activated(entry: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = user_data;
    const text = gtk_editable_get_text(entry);
    perform_search(std.mem.span(text));
    
    // If we have at least one result, navigate to the first one
    if (search_results_list) |list| {
        if (gtk_widget_get_first_child(@ptrCast(list))) |row| {
            // The row's child is the button
            if (gtk_widget_get_first_child(row)) |btn| {
                g_signal_emit_by_name(btn, "clicked");
            }
        }
    }
}

fn on_search_changed(entry: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = user_data;
    const text = gtk_editable_get_text(entry);
    const span = std.mem.span(text);
    if (span.len >= 3) {
        perform_search(span);
    } else if (span.len == 0) {
        gtk_list_box_remove_all(search_results_list);
    }
}



fn hide_search_window_idle(data: gpointer) callconv(.c) bool {
    _ = data;
    if (search_window) |w| {
        gtk_widget_set_visible(@ptrCast(w), false);
    }
    return false;
}

fn on_search_window_active_changed(window: ?*anyopaque, pspec: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = pspec; _ = user_data;
    if (!gtk_window_is_active(@ptrCast(window))) {
        if (gtk_widget_get_visible(@ptrCast(window))) {
            _ = g_idle_add(&hide_search_window_idle, null);
        }
    }
}

fn on_search_window_key(controller: ?*anyopaque, keyval: u32, keycode: u32, state: u32, user_data: gpointer) callconv(.c) bool {
    _ = controller; _ = keycode; _ = state; _ = user_data;
    const GDK_KEY_Escape = 0xff1b;
    if (keyval == GDK_KEY_Escape) {
        if (search_window) |w| gtk_widget_set_visible(@ptrCast(w), false);
        return true;
    }
    return false;
}

fn on_search_trigger_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    if (search_window) |w| {
        gtk_window_present(w);
        if (search_entry) |e| {
            gtk_editable_set_text(e, "");
            _ = gtk_widget_grab_focus(e);
        }
        gtk_list_box_remove_all(search_results_list);
    }
}

fn activate(app: ?*GtkApplication, user_data: gpointer) callconv(.c) void {
    _ = user_data;
    main_window = @ptrCast(gtk_application_window_new(app));
    gtk_window_set_title(main_window, "Metanoia - Bible Study");
    gtk_window_set_default_size(main_window, 1280, 800);
    load_config();
    font_provider = gtk_css_provider_new();
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), @ptrCast(font_provider), GTK_STYLE_PROVIDER_PRIORITY_USER);
    update_font_styles();

    const provider = gtk_css_provider_new();
    gtk_css_provider_load_from_path(provider, "assets/themes/tokyo-night.css");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), @ptrCast(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    const main_layout = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_window_set_child(main_window, main_layout);

    // Setup Rerender Action
    const entries = [_]GActionEntry{
        .{ .name = "rerender", .activate = on_rerender_action },
    };
    g_action_map_add_action_entries(@ptrCast(main_window), &entries, entries.len, null);

    // Create Verse Popover Menu
    const menu = g_menu_new();
    g_menu_append(menu, "Re-render Verse", "win.rerender");
    verse_popover = gtk_popover_menu_new_from_model(menu);
    gtk_widget_set_parent(verse_popover, @ptrCast(main_layout));
    gtk_popover_set_has_arrow(@ptrCast(verse_popover), false);

    const top_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    gtk_widget_add_css_class(top_bar, "headerbar");
    gtk_box_append(@ptrCast(main_layout), top_bar);

    const sidebar_toggle = gtk_button_new_with_label("≡");
    _ = g_signal_connect_data(sidebar_toggle, "clicked", @ptrCast(&on_sidebar_toggled), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), sidebar_toggle);

    // Search Trigger Button (Spotlight style)
    const search_btn = gtk_button_new_with_label("Search Scripture...");
    gtk_widget_set_hexpand(search_btn, true);
    gtk_widget_add_css_class(search_btn, "search-trigger-btn");
    _ = g_signal_connect_data(search_btn, "clicked", @ptrCast(&on_search_trigger_clicked), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), search_btn);

    // Spotlight Search Window (floating)
    search_window = @ptrCast(gtk_window_new());
    gtk_window_set_transient_for(search_window, main_window);
    gtk_window_set_modal(search_window, false);
    gtk_window_set_decorated(search_window, false);
    gtk_window_set_resizable(search_window, false);
    gtk_window_set_default_size(search_window, 700, 500);
    gtk_widget_add_css_class(@ptrCast(search_window), "spotlight-window");
    _ = g_signal_connect_data(search_window, "close-request", @ptrCast(&on_search_close_request), null, null, 0);
    _ = g_signal_connect_data(search_window, "notify::is-active", @ptrCast(&on_search_window_active_changed), null, null, 0);

    const spotlight_vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_window_set_child(search_window, spotlight_vbox);

    search_entry = gtk_search_entry_new();
    gtk_widget_add_css_class(search_entry, "spotlight-entry");
    _ = g_signal_connect_data(search_entry, "activate", @ptrCast(&on_search_activated), null, null, 0);
    _ = g_signal_connect_data(search_entry, "search-changed", @ptrCast(&on_search_changed), null, null, 0);
    gtk_box_append(@ptrCast(spotlight_vbox), search_entry);

    const results_scroll = gtk_scrolled_window_new();
    gtk_widget_set_vexpand(results_scroll, true);
    gtk_box_append(@ptrCast(spotlight_vbox), results_scroll);

    search_results_list = gtk_list_box_new();
    gtk_widget_add_css_class(search_results_list, "spotlight-results");
    gtk_list_box_set_selection_mode(@ptrCast(search_results_list), 0);
    gtk_scrolled_window_set_child(@ptrCast(results_scroll), search_results_list);

    const sw_key_controller = gtk_event_controller_key_new();
    _ = g_signal_connect_data(sw_key_controller, "key-pressed", @ptrCast(&on_search_window_key), null, null, 0);
    gtk_widget_add_controller(@ptrCast(search_window), sw_key_controller);

    const prev_btn = gtk_button_new_with_label("<");
    _ = g_signal_connect_data(prev_btn, "clicked", @ptrCast(&on_prev_chapter_clicked), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), prev_btn);

    const next_btn = gtk_button_new_with_label(">");
    _ = g_signal_connect_data(next_btn, "clicked", @ptrCast(&on_next_chapter_clicked), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), next_btn);

    const f_left_plus = gtk_button_new_with_label("L+"); _ = g_signal_connect_data(f_left_plus, "clicked", @ptrCast(&on_font_adjust), @ptrFromInt(1), null, 0);
    const f_left_minus = gtk_button_new_with_label("L-"); _ = g_signal_connect_data(f_left_minus, "clicked", @ptrCast(&on_font_adjust), @ptrFromInt(2), null, 0);
    const f_right_plus = gtk_button_new_with_label("R+"); _ = g_signal_connect_data(f_right_plus, "clicked", @ptrCast(&on_font_adjust), @ptrFromInt(3), null, 0);
    const f_right_minus = gtk_button_new_with_label("R-"); _ = g_signal_connect_data(f_right_minus, "clicked", @ptrCast(&on_font_adjust), @ptrFromInt(4), null, 0);
    f_right_plus_btn = f_right_plus;
    f_right_minus_btn = f_right_minus;
    gtk_widget_set_visible(f_right_plus, false);
    gtk_widget_set_visible(f_right_minus, false);
    gtk_box_append(@ptrCast(top_bar), f_left_plus); gtk_box_append(@ptrCast(top_bar), f_left_minus);
    gtk_box_append(@ptrCast(top_bar), f_right_plus); gtk_box_append(@ptrCast(top_bar), f_right_minus);

    const parallel_btn = gtk_button_new_with_label("Parallel");
    _ = g_signal_connect_data(parallel_btn, "clicked", @ptrCast(&on_parallel_toggled), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), parallel_btn);

    const speaker_btn = gtk_button_new_with_label("🔈");
    _ = g_signal_connect_data(speaker_btn, "clicked", @ptrCast(&on_speaker_clicked), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), speaker_btn);

    const passage_btn = gtk_button_new_with_label("Passage");
    gtk_widget_add_css_class(passage_btn, "suggested-action");
    _ = g_signal_connect_data(passage_btn, "clicked", @ptrCast(&on_passage_btn_clicked), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), passage_btn);

    const settings_btn = gtk_button_new_with_label("⚙️");
    _ = g_signal_connect_data(settings_btn, "clicked", @ptrCast(&on_settings_btn_clicked), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), settings_btn);

    const llm_btn = gtk_button_new_with_label("LLM Study");
    _ = g_signal_connect_data(llm_btn, "clicked", @ptrCast(&on_llm_clicked), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), llm_btn);

    const voices = [_]?[*:0]const u8{ "John Lennox", "Tommy", "Mari", "Jordan Peterson", "Sam Shamoun", "Jonathan Roumie", null };
    const voice_drop = gtk_drop_down_new_from_strings(&voices);
    
    // Set initial selection based on config
    const voice_ids = [_][]const u8{ "lennox", "tommy", "mari", "jordan", "shamoun", "roumie" };
    for (voice_ids, 0..) |id, idx| {
        if (std.mem.eql(u8, app_config.selected_voice, id)) {
            gtk_drop_down_set_selected(voice_drop, @intCast(idx));
            break;
        }
    }
    
    _ = g_signal_connect_data(voice_drop, "notify::selected", @ptrCast(&on_voice_changed), null, null, 0);
    gtk_box_append(@ptrCast(top_bar), voice_drop);

    main_paned = @ptrCast(gtk_paned_new(gtk.GTK_ORIENTATION_HORIZONTAL));
    gtk_box_append(@ptrCast(main_layout), @ptrCast(main_paned));
    _ = g_signal_connect_data(main_paned, "notify::position", @ptrCast(&on_paned_notify_position), null, null, 0);

    main_status_bar = status_bar_cmp.StatusBar.init(std.heap.page_allocator);
    gtk_box_append(@ptrCast(main_layout), main_status_bar.?.box);

    main_sidebar = sidebar_cmp.Sidebar.init(std.heap.page_allocator, main_io, on_color_clicked);
    gtk_widget_set_visible(main_sidebar.?.box.?, false);
    gtk_paned_set_start_child(@ptrCast(main_paned), main_sidebar.?.box);
    
    gtk_paned_set_position(@ptrCast(main_paned), app_config.sidebar_width);

    // Link global pointers to modular component fields
    chapter_summary_label = main_sidebar.?.summary_label;
    word_study_label = main_sidebar.?.word_study_label;
    llm_spinner = main_sidebar.?.llm_spinner;
    note_view = main_sidebar.?.note_view;
    note_buffer = main_sidebar.?.note_buffer;

    main_notebook = @ptrCast(gtk_notebook_new());
    gtk_widget_add_css_class(@ptrCast(main_notebook), "main-content");
    gtk_paned_set_end_child(@ptrCast(main_paned), @ptrCast(main_notebook));

    _ = gtk_notebook_append_page(main_notebook, gtk_label_new("Dashboard Content"), gtk_label_new("Dashboard"));

    const study_paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
    _ = gtk_notebook_append_page(main_notebook, study_paned, gtk_label_new("Study"));
    gtk_paned_set_position(@ptrCast(study_paned), 600);

    const left_scroll = gtk_scrolled_window_new();
    study_left_scroll = @ptrCast(left_scroll);
    gtk_widget_set_vexpand(left_scroll, true);
    study_left_view = @ptrCast(gtk_box_new(GTK_ORIENTATION_VERTICAL, 24));
    gtk_widget_set_name(@ptrCast(study_left_view), "left_view");
    gtk_scrolled_window_set_child(@ptrCast(left_scroll), @ptrCast(study_left_view));
    gtk_paned_set_start_child(@ptrCast(study_paned), left_scroll);

    const right_scroll = gtk_scrolled_window_new();
    study_right_scroll = @ptrCast(right_scroll);
    right_scroll_pane = @ptrCast(right_scroll);
    gtk_widget_set_vexpand(right_scroll, true);
    study_right_view = @ptrCast(gtk_box_new(GTK_ORIENTATION_VERTICAL, 24));
    gtk_widget_set_name(@ptrCast(study_right_view), "right_view");
    gtk_scrolled_window_set_child(@ptrCast(right_scroll), @ptrCast(study_right_view));
    gtk_paned_set_end_child(@ptrCast(study_paned), right_scroll);
    gtk_widget_set_visible(right_scroll_pane, false);

    const left_adj = gtk_scrolled_window_get_vadjustment(@ptrCast(left_scroll));
    const right_adj = gtk_scrolled_window_get_vadjustment(@ptrCast(right_scroll));
    _ = g_signal_connect_data(left_adj, "value-changed", @ptrCast(&on_scroll_changed), right_adj, null, 0);
    _ = g_signal_connect_data(right_adj, "value-changed", @ptrCast(&on_scroll_changed), left_adj, null, 0);

    // Present early to help macOS focus accounting
    gtk_window_present(main_window);

    // Setup Keyboard Shortcut (Cmd+K)
    const key_controller = gtk_event_controller_key_new();
    _ = g_signal_connect_data(key_controller, "key-pressed", @ptrCast(&on_main_window_key), null, null, 0);
    gtk_widget_add_controller(@ptrCast(main_window), key_controller);

    // Initial load
    const last_book = std.mem.span(@as([*:0]const u8, @ptrCast(&app_config.last_book)));
    load_chapter_into_study(last_book, app_config.last_chapter, app_config.last_verse);
}

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var threaded_io = std.Io.Threaded.init(gpa, .{});
    main_io = threaded_io.ioBasic();
if (sqlite3_open("data/bible.db", @ptrCast(&db)) != SQLITE_OK) {
    std.debug.print("Failed to open database\n", .{});
    return;
}
bible.init_db(db.?) catch |err| {
    std.debug.print("Failed to initialize database: {any}\n", .{err});
};

    defer _ = sqlite3_close(db.?);
    const app = gtk_application_new("org.bytecats.metanoia", 0);
    defer g_object_unref(app);
    _ = g_signal_connect_data(app, "activate", @ptrCast(&activate), null, null, 0);
    const status = g_application_run(@ptrCast(app), 0, null);
    if (status != 0) std.process.exit(1);
}
