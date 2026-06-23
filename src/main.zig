const std = @import("std");
const gtk = @import("gtk.zig");
const models = @import("models/config.zig");
const app_state = @import("app_state.zig");
const bible = @import("bible_db.zig");
const tts_client = @import("tts_client.zig");
const ollama = @import("ollama_client.zig");
const scraper = @import("scraper_client.zig");
const tts_engine_mod = @import("services/tts_engine.zig");
const llm_engine_mod = @import("services/llm_engine.zig");
const theme_mod = @import("ui/theme.zig");
const nav_dialog = @import("ui/navigation_dialog.zig");
const search_mod = @import("ui/components/search.zig");
const sidebar_cmp = @import("ui/components/sidebar.zig");
const status_bar_cmp = @import("ui/components/status_bar.zig");
const settings_dialog = @import("ui/settings_dialog.zig");

const AppState = app_state.AppState;
const ActiveNoteVerse = app_state.ActiveNoteVerse;
const Config = models.Config;
const SearchResult = bible.SearchResult;
const BIBLE_BOOKS = bible.BIBLE_BOOKS;
const BIBLE_ABBREVIATIONS = bible.BIBLE_ABBREVIATIONS;
const TTSEngine = tts_engine_mod.TTSEngine;
const TTSEngineConfig = tts_engine_mod.TTSEngineConfig;
const PlaybackCallbacks = tts_engine_mod.PlaybackCallbacks;
const LLMEngine = llm_engine_mod.LLMEngine;
const Theme = theme_mod.Theme;

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

const GTK_ORIENTATION_HORIZONTAL = gtk.GTK_ORIENTATION_HORIZONTAL;
const GTK_ORIENTATION_VERTICAL = gtk.GTK_ORIENTATION_VERTICAL;
const GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = gtk.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION;
const GTK_STYLE_PROVIDER_PRIORITY_USER = gtk.GTK_STYLE_PROVIDER_PRIORITY_USER;
const GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT = gtk.GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT;
const SQLITE_ROW = bible.SQLITE_ROW;
const SQLITE_OK = bible.SQLITE_OK;

var state: AppState = undefined;
var app_theme: Theme = undefined;
var nav_dialog_instance: *nav_dialog.NavigationDialog = undefined;
var search_instance: *search_mod.Search = undefined;
var llm_engine: *LLMEngine = undefined;

fn clearBox(box: ?*GtkBox) void {
    if (box == null) return;
    while (gtk.gtk_widget_get_first_child(@ptrCast(box))) |child| {
        gtk.gtk_box_remove(box, child);
    }
}

// TTS Callbacks
fn onTtsStatus(msg: []const u8) void {
    if (state.main_status_bar) |sb| sb.updateStatus(msg, false);
}

fn onTtsHighlight(idx: usize) void {
    _ = gtk.g_idle_add(&update_highlight_and_scroll, @ptrFromInt(idx));
}

fn onTtsPlayState(playing: bool) void {
    state.tts_playing.store(playing, .release);
    if (state.tts_button_ref) |_| {
        _ = gtk.g_timeout_add(0, struct {
            fn run(_: gpointer) callconv(.c) bool {
                if (state.tts_button_ref) |b| {
                    gtk.gtk_button_set_label(b, if (state.tts_playing.load(.acquire)) "\u{23F3}" else "\u{1F508}");
                }
                return false;
            }
        }.run, null);
    }
}

const tts_playback_cbs = PlaybackCallbacks{
    .onStatusUpdate = onTtsStatus,
    .onVerseHighlight = onTtsHighlight,
    .onPlayStateChanged = onTtsPlayState,
};

// LLM Idle Callbacks
fn llmStepIdle(data: gpointer) callconv(.c) bool {
    const s: [*:0]u8 = @ptrCast(@alignCast(data));
    defer state.allocator.free(std.mem.span(s));
    const msg = std.mem.span(s);
    if (state.main_status_bar) |sb| sb.updateStatus(msg, false);
    if (state.main_sidebar) |ms| ms.log(msg);
    if (state.word_study_label) |lbl| gtk.gtk_label_set_markup(lbl, s);
    return false;
}

fn llmSummaryIdle(data: gpointer) callconv(.c) bool {
    const s: [*:0]u8 = @ptrCast(@alignCast(data));
    defer state.allocator.free(std.mem.span(s));
    if (state.main_sidebar) |ms| ms.log("Summary updated.");
    if (state.chapter_summary_label) |lbl| gtk.gtk_label_set_markup(lbl, s);
    return false;
}

fn llmResultIdle(data: gpointer) callconv(.c) bool {
    const s: [*:0]u8 = @ptrCast(@alignCast(data));
    defer state.allocator.free(std.mem.span(s));
    if (state.main_status_bar) |sb| sb.updateStatus("Analysis Complete", false);
    if (state.main_sidebar) |ms| ms.log("Neural analysis finished.");
    if (state.word_study_label) |lbl| gtk.gtk_label_set_markup(lbl, s);
    if (state.llm_spinner) |sp| {
        gtk.gtk_spinner_stop(sp);
        gtk.gtk_widget_set_visible(sp, false);
    }
    return false;
}

// LLM Callbacks
fn llmStepCb(msg: []const u8) void {
    const s = state.allocator.dupeSentinel(u8, msg, 0) catch return;
    _ = gtk.g_idle_add(&llmStepIdle, @ptrCast(s.ptr));
}

fn llmSummaryCb(summary: []const u8) void {
    const s = state.allocator.dupeSentinel(u8, summary, 0) catch return;
    _ = gtk.g_idle_add(&llmSummaryIdle, @ptrCast(s.ptr));
}

fn llmResultCb(result: []const u8) void {
    const s = state.allocator.dupeSentinel(u8, result, 0) catch return;
    _ = gtk.g_idle_add(&llmResultIdle, @ptrCast(s.ptr));
}

fn llmErrorCb(err: []const u8) void {
    const s = state.allocator.dupeSentinel(u8, err, 0) catch return;
    _ = gtk.g_idle_add(&llmResultIdle, @ptrCast(s.ptr));
}

const llm_callbacks = LLMEngine.AnalysisCallbacks{
    .onStep = llmStepCb,
    .onSummary = llmSummaryCb,
    .onResult = llmResultCb,
    .onError = llmErrorCb,
};

fn resetSaveButtonIdle(data: gpointer) callconv(.c) bool {
    const btn: ?*GtkButton = @ptrCast(@alignCast(data));
    if (btn) |b| {
        gtk.gtk_button_set_label(b, "Save Note");
        gtk.gtk_widget_remove_css_class(@ptrCast(b), "save-success");
    }
    return false;
}

// Highlight and Note Handlers
fn onColorClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const color: [*:0]const u8 = @ptrCast(user_data);
    const color_span = std.mem.span(color);
    if (state.active_note_verse) |av| {
        const book = std.mem.span(@as([*:0]const u8, @ptrCast(&av.book)));
        if (std.mem.eql(u8, color_span, "none")) {
            bible.delete_verse_highlight(state.db.?, book, av.ch, av.v) catch {};
            if (state.main_status_bar) |sb| sb.updateStatus("Highlight removed", false);
        } else {
            bible.set_verse_highlight(state.db.?, book, av.ch, av.v, color_span) catch |err| {
                std.debug.print("Failed to save highlight: {any}\n", .{err});
                if (state.main_status_bar) |sb| sb.updateStatus("Failed to save highlight", true);
            };
            if (state.main_status_bar) |sb| sb.updateStatus("Verse highlighted", false);
        }
        load_chapter_into_study(book, av.ch, av.v);
    }
}

fn onVerseLongPress(gesture: ?*anyopaque, x: f64, y: f64, user_data: gpointer) callconv(.c) void {
    _ = gesture; _ = x; _ = y;
    const index: usize = @intCast(@intFromPtr(user_data));
    state.highlighted_index = index;
    _ = gtk.g_idle_add(&update_highlight_and_scroll, @ptrFromInt(index));

    const book = std.mem.span(@as([*:0]u8, @ptrCast(&state.cur_book_name)));
    const v_num = @as(i32, @intCast(index)) + 1;

    state.active_note_verse = ActiveNoteVerse{
        .book = state.cur_book_name,
        .ch = state.cur_chapter,
        .v = v_num,
    };

    if (state.main_sidebar) |sb| gtk.gtk_widget_set_visible(sb.box.?, true);

    const existing = bible.get_verse_note(state.allocator, state.db.?, book, state.cur_chapter, v_num) catch "";
    defer state.allocator.free(existing);
    const existing_z = state.allocator.dupeSentinel(u8, existing, 0) catch {
        gtk.gtk_text_buffer_set_text(state.note_buffer, "", -1);
        return;
    };
    defer state.allocator.free(existing_z);
    gtk.gtk_text_buffer_set_text(state.note_buffer, existing_z, -1);
}

fn onSaveNoteClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = user_data;
    if (state.active_note_verse) |av| {
        var start_iter: [128]u8 = undefined;
        var end_iter: [128]u8 = undefined;
        gtk.gtk_text_buffer_get_start_iter(state.note_buffer, &start_iter);
        gtk.gtk_text_buffer_get_end_iter(state.note_buffer, &end_iter);
        const text = gtk.gtk_text_buffer_get_text(state.note_buffer, &start_iter, &end_iter, false);
        defer gtk.g_free(text);

        const book = std.mem.span(@as([*:0]const u8, @ptrCast(&av.book)));
        bible.save_verse_note(state.db.?, book, av.ch, av.v, std.mem.span(text)) catch |err| {
            std.debug.print("Failed to save note: {any}\n", .{err});
            if (state.main_status_bar) |sb| sb.updateStatus("Failed to save note", true);
            return;
        };
        if (state.main_status_bar) |sb| sb.updateStatus("Note saved successfully", false);
        if (btn) |b| {
            gtk.gtk_button_set_label(b, "\u{2705} Saved!");
            gtk.gtk_widget_add_css_class(@ptrCast(b), "save-success");
            _ = gtk.g_timeout_add(1500, &resetSaveButtonIdle, b);
        }
    }
}

// Verse Highlight & Scroll
fn update_highlight_and_scroll(data: gpointer) callconv(.c) bool {
    const index: usize = @intCast(@intFromPtr(data));
    const labels = state.verse_labels orelse return false;
    const verses = state.current_chapter_verses orelse return false;

    if (state.highlighted_index) |prev| {
        if (prev < labels.items.len) {
            const lbl = labels.items[prev] orelse return false;
            const highlights = bible.get_chapter_highlights(state.allocator, state.db.?, std.mem.span(@as([*:0]u8, @ptrCast(&state.cur_book_name))), state.cur_chapter) catch std.AutoHashMapUnmanaged(i32, []const u8).empty;
            defer {
                var it = highlights.iterator();
                while (it.next()) |entry| state.allocator.free(entry.value_ptr.*);
                var h = highlights;
                h.deinit(state.allocator);
            }
            const v_num = @as(i32, @intCast(prev)) + 1;
            const bg_color = highlights.get(v_num);
            const text = verses.items[prev];
            const markup_slice = if (bg_color) |bg|
                std.fmt.allocPrintSentinel(state.allocator, "<span background='{s}'><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='#7aa2f7'>{d}</span> {s}</span>", .{ bg, v_num, text }, 0) catch @constCast("Error")
            else
                std.fmt.allocPrintSentinel(state.allocator, "<span><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='#7aa2f7'>{d}</span> {s}</span>", .{ v_num, text }, 0) catch @constCast("Error");
            gtk.gtk_label_set_markup(@ptrCast(lbl), markup_slice);
            if (!std.mem.eql(u8, markup_slice, "Error")) state.allocator.free(markup_slice);
        }
    }

    if (index < labels.items.len) {
        state.highlighted_index = index;
        const lbl = labels.items[index] orelse return false;
        const v_num = @as(i32, @intCast(index)) + 1;
        const text = verses.items[index];
        const markup_slice = std.fmt.allocPrintSentinel(state.allocator, "<span><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='#e0af68'>{d}</span> {s}</span>", .{ v_num, text }, 0) catch return false;
        gtk.gtk_label_set_markup(@ptrCast(lbl), markup_slice);
        state.allocator.free(markup_slice);

        var bounds: [4]f32 = undefined;
        if (state.study_left_scroll) |sc| {
            if (gtk.gtk_widget_compute_bounds(@ptrCast(lbl), @ptrCast(state.study_left_view), &bounds)) {
                const left_adj = gtk.gtk_scrolled_window_get_vadjustment(@ptrCast(sc));
                const page_size = gtk.gtk_adjustment_get_page_size(left_adj);
                gtk.gtk_adjustment_set_value(left_adj, @max(0, bounds[1] - (page_size / 3.0)));
            }
        }
        if (state.study_right_scroll) |sc| {
            var current = gtk.gtk_widget_get_first_child(@ptrCast(state.study_right_view));
            var count: usize = 0;
            while (count < index) : (count += 1) {
                if (current) |c| { current = gtk.gtk_widget_get_next_sibling(c); } else break;
            }
            if (current) |right_widget| {
                if (gtk.gtk_widget_compute_bounds(right_widget, @ptrCast(state.study_right_view), &bounds)) {
                    const right_adj = gtk.gtk_scrolled_window_get_vadjustment(@ptrCast(sc));
                    const page_size = gtk.gtk_adjustment_get_page_size(right_adj);
                    gtk.gtk_adjustment_set_value(right_adj, @max(0, bounds[1] - (page_size / 3.0)));
                }
            }
        }
    }
    return false;
}

// Interlinear Word Click
fn onInterlinearWordClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const strongs_raw: [*:0]const u8 = @ptrCast(user_data);
    if (bible.get_lexicon_detail(state.allocator, state.db.?, std.mem.span(strongs_raw)) catch null) |detail| {
        defer {
            state.allocator.free(detail.strongs);
            state.allocator.free(detail.lemma);
            state.allocator.free(detail.transliteration);
            state.allocator.free(detail.definition);
            state.allocator.free(detail.language);
        }
        const info = std.fmt.allocPrintSentinel(state.allocator,
            "<span size='xx-large' color='#7aa2f7'><b>{s}</b></span> (<span color='#bb9af7'>{s}</span>)\n<span size='large' color='#e0af68'><i>{s}</i></span>\n\n<span color='#c0caf5'>{s}</span>",
            .{ detail.strongs, detail.lemma, detail.transliteration, detail.definition }, 0) catch return;
        defer state.allocator.free(info);
        gtk.gtk_label_set_markup(state.word_study_label, info);
    } else {
        const info = std.fmt.allocPrintSentinel(state.allocator, "<span size='xx-large' color='#7aa2f7'><b>{s}</b></span>\n\n<span color='#565f89'>[Definition not cached]</span>", .{strongs_raw}, 0) catch return;
        defer state.allocator.free(info);
        gtk.gtk_label_set_markup(state.word_study_label, info);
    }
}

fn addInteractiveWord(flow: ?*GtkFlowBox, word: [*:0]const u8, strongs: [*:0]const u8, trans: [*:0]const u8) void {
    const word_box = gtk.gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk.gtk_widget_add_css_class(@ptrCast(word_box), "interlinear-word");
    const word_btn = gtk.gtk_button_new_with_label(word);
    gtk.gtk_widget_add_css_class(word_btn, "interlinear-word-btn");
    const strongs_span = std.mem.span(strongs);
    if (strongs_span.len > 0) {
        if (strongs_span[0] == 'G') gtk.gtk_widget_add_css_class(word_btn, "greek")
        else if (strongs_span[0] == 'H') gtk.gtk_widget_add_css_class(word_btn, "hebrew");
    }
    const persistent_strongs = gtk.g_strdup(strongs);
    _ = gtk.g_signal_connect_data(word_btn, "clicked", @ptrCast(&onInterlinearWordClicked), persistent_strongs, null, 0);
    const trans_lbl = gtk.gtk_label_new(trans);
    gtk.gtk_widget_add_css_class(trans_lbl, "interlinear-english");
    gtk.gtk_box_append(@ptrCast(word_box), word_btn);
    gtk.gtk_box_append(@ptrCast(word_box), trans_lbl);
    gtk.gtk_flow_box_insert(flow, word_box, -1);
}

// Chapter Loading
fn load_chapter_into_study(book: []const u8, chapter: i32, start_verse: i32) void {
    const allocator = state.allocator;
    const loading_msg = std.fmt.allocPrint(allocator, "Loading {s} {d}...", .{ book, chapter }) catch "Loading...";
    if (state.main_status_bar) |sb| {
        sb.updateStatus(loading_msg, false);
        sb.pulseProgress();
    }
    if (!std.mem.eql(u8, loading_msg, "Loading...")) allocator.free(loading_msg);

    if (state.tts_engine) |e| e.stop();

    const sql = std.fmt.allocPrintSentinel(allocator, "SELECT verse, text FROM verses WHERE book='{s}' AND chapter={d} ORDER BY verse ASC", .{ book, chapter }, 0) catch return;
    defer allocator.free(sql);
    var stmt: ?*bible.sqlite3_stmt = null;
    if (bible.sqlite3_prepare_v2(state.db.?, sql, -1, @ptrCast(&stmt), null) == SQLITE_OK) {
        clearBox(state.study_left_view);
        clearBox(state.study_right_view);

        if (state.current_chapter_verses) |*list| {
            for (list.items) |v| allocator.free(v);
            list.clearAndFree(allocator);
            state.current_chapter_verses = null;
        }
        if (state.verse_labels) |*list| {
            list.clearAndFree(allocator);
            state.verse_labels = null;
        }
        state.highlighted_index = null;

        var chapter_verses = std.ArrayListUnmanaged([]const u8).empty;
        var labels = std.ArrayListUnmanaged(?*GtkWidget).empty;

        var highlights = bible.get_chapter_highlights(allocator, state.db.?, book, chapter) catch std.AutoHashMapUnmanaged(i32, []const u8).empty;
        defer {
            var it = highlights.iterator();
            while (it.next()) |entry| allocator.free(entry.value_ptr.*);
            highlights.deinit(allocator);
        }

        const title_text = std.fmt.allocPrintSentinel(allocator, "{s} {d}", .{ book, chapter }, 0) catch return;
        const title = gtk.gtk_label_new(null);
        gtk.gtk_label_set_markup(@ptrCast(title), title_text);
        gtk.gtk_widget_set_name(title, "chapter_title");
        gtk.gtk_label_set_xalign(@ptrCast(title), 0.5);
        gtk.gtk_box_append(state.study_left_view, title);

        while (bible.sqlite3_step(stmt.?) == SQLITE_ROW) {
            const verse_num = bible.sqlite3_column_int(stmt.?, 0);
            const text = bible.sqlite3_column_text(stmt.?, 1);
            const v_text = std.mem.span(text.?);
            chapter_verses.append(allocator, allocator.dupe(u8, v_text) catch "") catch {};

            const v_num_color = if (verse_num == start_verse) "#e0af68" else "#7aa2f7";
            const bg_color = highlights.get(verse_num);

            var verse_markup: [:0]u8 = undefined;
            if (bg_color) |bg| {
                verse_markup = std.fmt.allocPrintSentinel(allocator, "<span background='{s}'><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='{s}'>{d}</span> {s}</span>", .{ bg, v_num_color, verse_num, text.? }, 0) catch continue;
            } else {
                verse_markup = std.fmt.allocPrintSentinel(allocator, "<span><span font_family='SF Pro Text' weight='bold' size='smaller' rise='4000' color='{s}'>{d}</span> {s}</span>", .{ v_num_color, verse_num, text.? }, 0) catch continue;
            }
            defer allocator.free(verse_markup);
            const lbl = gtk.gtk_label_new(null);
            gtk.gtk_label_set_markup(@ptrCast(lbl), verse_markup.ptr);
            gtk.gtk_widget_add_css_class(@ptrCast(lbl), "verse-label");
            gtk.gtk_label_set_wrap(@ptrCast(lbl), true);
            gtk.gtk_label_set_xalign(@ptrCast(lbl), 0.0);
            gtk.gtk_box_append(state.study_left_view, lbl);
            labels.append(allocator, @ptrCast(lbl)) catch {};

            const db_click = gtk.gtk_gesture_click_new();
            gtk.gtk_gesture_single_set_button(db_click, 1);
            _ = gtk.g_signal_connect_data(db_click, "pressed", @ptrCast(&onVerseDoubleClick), @ptrFromInt(chapter_verses.items.len - 1), null, 0);
            gtk.gtk_widget_add_controller(@ptrCast(lbl), @ptrCast(db_click));

            const right_gesture = gtk.gtk_gesture_click_new();
            gtk.gtk_gesture_single_set_button(right_gesture, 3);
            _ = gtk.g_signal_connect_data(right_gesture, "pressed", @ptrCast(&onVerseRightClick), @ptrFromInt(chapter_verses.items.len - 1), null, 0);
            gtk.gtk_widget_add_controller(@ptrCast(lbl), @ptrCast(right_gesture));

            const long_press = gtk.gtk_gesture_long_press_new();
            _ = gtk.g_signal_connect_data(long_press, "pressed", @ptrCast(&onVerseLongPress), @ptrFromInt(chapter_verses.items.len - 1), null, 0);
            gtk.gtk_widget_add_controller(@ptrCast(lbl), @ptrCast(long_press));

            const flow = gtk.gtk_flow_box_new();
            gtk.gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
            const strongs_sql = std.fmt.allocPrintSentinel(allocator, "SELECT strongs FROM interlinear WHERE book='{s}' AND chapter={d} AND verse={d} LIMIT 1", .{ book, chapter, verse_num }, 0) catch continue;
            defer allocator.free(strongs_sql);
            var s_stmt: ?*bible.sqlite3_stmt = null;
            if (bible.sqlite3_prepare_v2(state.db.?, strongs_sql, -1, @ptrCast(&s_stmt), null) == SQLITE_OK) {
                if (bible.sqlite3_step(s_stmt.?) == SQLITE_ROW) {
                    const s_txt = bible.sqlite3_column_text(s_stmt.?, 0) orelse "";
                    if (std.mem.span(s_txt).len > 0 and std.mem.span(s_txt)[0] == 'H') gtk.gtk_widget_set_direction(@ptrCast(flow), gtk.GTK_TEXT_DIR_RTL);
                }
                _ = bible.sqlite3_finalize(s_stmt.?);
            }
            gtk.gtk_box_append(state.study_right_view, flow);
            var i_stmt: ?*bible.sqlite3_stmt = null;
            const i_sql = std.fmt.allocPrintSentinel(allocator, "SELECT original_text, strongs, translation FROM interlinear WHERE book='{s}' AND chapter={d} AND verse={d} ORDER BY word_index ASC", .{ book, chapter, verse_num }, 0) catch continue;
            defer allocator.free(i_sql);
            if (bible.sqlite3_prepare_v2(state.db.?, i_sql, -1, @ptrCast(&i_stmt), null) == SQLITE_OK) {
                var found = false;
                while (bible.sqlite3_step(i_stmt.?) == SQLITE_ROW) {
                    found = true;
                    addInteractiveWord(@ptrCast(flow), bible.sqlite3_column_text(i_stmt.?, 0) orelse "", bible.sqlite3_column_text(i_stmt.?, 1) orelse "", bible.sqlite3_column_text(i_stmt.?, 2) orelse "");
                }
                _ = bible.sqlite3_finalize(i_stmt.?);
                if (!found) gtk.gtk_flow_box_insert(@ptrCast(flow), gtk.gtk_label_new("[Interlinear not cached]"), -1);
            }
        }
        _ = bible.sqlite3_finalize(stmt.?);

        state.current_chapter_verses = chapter_verses;
        state.verse_labels = labels;

        const verse_count = chapter_verses.items.len;
        const loaded_msg = std.fmt.allocPrint(allocator, "Loaded {s} {d} ({d} verses)", .{ book, chapter, verse_count }) catch "Loaded.";
        if (state.main_status_bar) |sb| {
            sb.updateStatus(loaded_msg, false);
            sb.updateProgress(-1);
        }
        if (!std.mem.eql(u8, loaded_msg, "Loaded.")) allocator.free(loaded_msg);

        @memcpy(state.cur_book_name[0..@min(book.len, 63)], book[0..@min(book.len, 63)]);
        state.cur_book_name[@min(book.len, 63)] = 0;
        state.cur_chapter = chapter;

        if (book.ptr != &state.config.last_book) {
            @memset(&state.config.last_book, 0);
            @memcpy(state.config.last_book[0..@min(book.len, 63)], book[0..@min(book.len, 63)]);
        }
        state.config.last_chapter = chapter;
        state.config.last_verse = start_verse;
        state.config.save(state.io);

        gtk.gtk_notebook_set_current_page(state.main_notebook, 1);
    } else {
        const failed_msg = std.fmt.allocPrint(allocator, "Failed to load {s} {d}", .{ book, chapter }) catch "Failed to load.";
        if (state.main_status_bar) |sb| sb.updateStatus(failed_msg, true);
        if (!std.mem.eql(u8, failed_msg, "Failed to load.")) allocator.free(failed_msg);
    }
}

// Navigation
fn onPrevChapterClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const book = std.mem.span(@as([*:0]u8, @ptrCast(&state.cur_book_name)));
    if (state.cur_chapter > 1) load_chapter_into_study(book, state.cur_chapter - 1, 1)
    else for (BIBLE_BOOKS, 0..) |b, i| if (std.mem.eql(u8, std.mem.span(b.name), book)) {
        if (i > 0) load_chapter_into_study(std.mem.span(BIBLE_BOOKS[i - 1].name), BIBLE_BOOKS[i - 1].chapters, 1);
        break;
    };
}

fn onNextChapterClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const book = std.mem.span(@as([*:0]u8, @ptrCast(&state.cur_book_name)));
    var max: i32 = 21;
    var found: ?usize = null;
    for (BIBLE_BOOKS, 0..) |b, i| if (std.mem.eql(u8, std.mem.span(b.name), book)) { max = b.chapters; found = i; break; };
    if (state.cur_chapter < max) load_chapter_into_study(book, state.cur_chapter + 1, 1)
    else if (found) |idx| if (idx + 1 < BIBLE_BOOKS.len) load_chapter_into_study(std.mem.span(BIBLE_BOOKS[idx + 1].name), 1, 1);
}

// Verse Double Click (TTS)
fn onVerseDoubleClick(gesture: ?*anyopaque, n_press: i32, x: f64, y: f64, user_data: gpointer) callconv(.c) void {
    _ = gesture; _ = x; _ = y;
    if (n_press == 2) {
        const index: usize = @intCast(@intFromPtr(user_data));
        const engine = state.tts_engine orelse return;
        engine.stop();
        const verses = state.current_chapter_verses orelse return;
        if (index >= verses.items.len) return;
        engine.playSequential(verses.items, index, .{
            .voice = state.config.selected_voice,
            .speed = state.config.speed,
            .emotion = state.config.emotion,
            .mode = state.config.tts_mode,
        }, tts_playback_cbs);
    }
}

fn onVerseRightClick(gesture: ?*anyopaque, n_press: i32, x: f64, y: f64, user_data: gpointer) callconv(.c) void {
    _ = gesture; _ = n_press; _ = x; _ = y;
    state.rerender_target_index = @intCast(@intFromPtr(user_data));
    if (state.verse_popover) |p| gtk.gtk_popover_popup(@ptrCast(p));
}

fn onRerenderClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    if (state.verse_popover) |p| gtk.gtk_popover_popdown(@ptrCast(p));
    const index = state.rerender_target_index;
    const verses = state.current_chapter_verses orelse return;
    if (index >= verses.items.len) return;

    if (state.tts_engine) |engine| {
        engine.regenerateVerse(verses.items[index], .{
            .voice = state.config.selected_voice,
            .speed = state.config.speed,
            .emotion = state.config.emotion,
            .mode = "gold",
        }, struct {
            fn done() void {
                if (state.main_status_bar) |sb| sb.updateStatus("Verse re-rendered", false);
            }
        }.done);
    }
}

fn onRerenderAction(action: ?*anyopaque, parameter: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = action; _ = parameter; _ = user_data;
    onRerenderClicked(null, @ptrFromInt(state.rerender_target_index));
}

// Speaker Button
fn onSpeakerClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = user_data;
    const engine = state.tts_engine orelse return;
    const now = gtk.g_get_monotonic_time();
    const diff = now - state.last_speaker_click_time;
    state.last_speaker_click_time = now;
    state.tts_button_ref = btn;

    if (diff < 300000) {
        engine.stop();
        return;
    }
    if (engine.isPlaying()) {
        engine.stop();
        gtk.gtk_button_set_label(btn.?, "\u{1F508}");
    } else {
        const verses = state.current_chapter_verses orelse return;
        if (verses.items.len == 0) return;
        gtk.gtk_button_set_label(btn.?, "\u{23F3}");
        engine.playSequential(verses.items, 0, .{
            .voice = state.config.selected_voice,
            .speed = state.config.speed,
            .emotion = state.config.emotion,
            .mode = state.config.tts_mode,
        }, tts_playback_cbs);
    }
}

// LLM Analysis
fn onLlmClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const verses = state.current_chapter_verses orelse return;
    const index = state.highlighted_index orelse 0;
    if (index >= verses.items.len) return;

    const verse_text = verses.items[index];
    const book_name = std.mem.span(@as([*:0]const u8, @ptrCast(&state.cur_book_name)));

    gtk.gtk_label_set_markup(state.word_study_label, "<span color='#7aa2f7'>Consulting Granite 4 LLM...</span>");
    if (state.llm_spinner) |s| {
        gtk.gtk_widget_set_visible(s, true);
        gtk.gtk_spinner_start(s);
    }
    if (state.main_sidebar) |sb| gtk.gtk_widget_set_visible(sb.box.?, true);

    llm_engine.analyzeVerse(book_name, state.cur_chapter, @intCast(index + 1), verse_text, llm_callbacks);
}

// Paned, Font, Display
fn onPanedNotifyPosition(self: ?*anyopaque, pspec: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = pspec; _ = user_data;
    const pos = gtk.gtk_paned_get_position(@ptrCast(self));
    if (pos > 0 and pos != state.config.sidebar_width) {
        state.config.sidebar_width = pos;
        state.config.save(state.io);
    }
}

fn onFontAdjust(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const adjust: i32 = @intCast(@intFromPtr(user_data));
    switch (adjust) {
        1 => state.config.english_font_size += 2,
        2 => state.config.english_font_size -= 2,
        3 => state.config.interlinear_font_size += 2,
        4 => state.config.interlinear_font_size -= 2,
        else => {},
    }
    app_theme.updateFontSizes(state.config.english_font_size, state.config.interlinear_font_size);
    state.config.save(state.io);
    if (state.main_status_bar) |sb| sb.updateStatus("Font size adjusted", false);
}

fn onParallelToggled(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const is_visible = gtk.gtk_widget_get_visible(state.right_scroll_pane);
    const new_visibility = !is_visible;
    gtk.gtk_widget_set_visible(state.right_scroll_pane, new_visibility);
    if (state.f_right_plus_btn) |b| gtk.gtk_widget_set_visible(b, new_visibility);
    if (state.f_right_minus_btn) |b| gtk.gtk_widget_set_visible(b, new_visibility);
}

fn onSidebarToggled(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    if (state.main_sidebar) |sb| {
        const is_visible = gtk.gtk_widget_get_visible(sb.box.?);
        gtk.gtk_widget_set_visible(sb.box.?, !is_visible);
    }
}

// Voice Dropdown
fn onVoiceChanged(self: ?*anyopaque, pspec: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    _ = pspec; _ = user_data;
    const selected = gtk.gtk_drop_down_get_selected(self);
    const voices = [_][]const u8{ "lennox", "tommy", "mari", "jordan", "shamoun", "roumie" };
    if (selected < voices.len) {
        state.config.selected_voice = voices[selected];
        state.config.save(state.io);
        if (state.main_status_bar) |sb| {
            sb.updateVoice(voices[selected]);
            sb.updateStatus("Voice updated", false);
        }
    }
}

// Search & Keyboard
fn onSearchNavigate(book: []const u8, chapter: i32, verse: i32) void {
    load_chapter_into_study(book, chapter, verse);
}

fn onSearchStatus(msg: []const u8, is_error: bool) void {
    if (state.main_status_bar) |sb| sb.updateStatus(msg, is_error);
}

fn onMainWindowKey(controller: ?*anyopaque, keyval: u32, keycode: u32, state_mod: u32, user_data: gpointer) callconv(.c) bool {
    _ = controller; _ = keycode; _ = user_data;
    const GDK_MOD_COMMAND = 1 << 28;
    if ((state_mod & GDK_MOD_COMMAND) != 0) {
        if (search_mod.Search.handleKeyPress(keyval, search_instance)) return true;
    }
    return false;
}

fn onSearchTriggerClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    search_instance.show();
}

fn onNavNavigate(book: []const u8, chapter: i32, verse: i32) void {
    load_chapter_into_study(book, chapter, verse);
}

// Settings
fn onSettingsSave(config: settings_dialog.SettingsConfig) void {
    state.config.tts_server_url = state.allocator.dupe(u8, config.tts_url) catch state.config.tts_server_url;
    state.config.tts_timeout_ms = config.tts_timeout_ms;
    state.config.tts_retry_count = config.tts_retry_count;
    state.config.llm_server_url = state.allocator.dupe(u8, config.llm_url) catch state.config.llm_server_url;
    state.config.save(state.io);
    if (state.main_status_bar) |sb| sb.updateStatus("Settings saved", false);
}

fn onSettingsBtnClicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    const dialog = settings_dialog.SettingsDialog.init(
        state.allocator,
        state.main_window,
        .{
            .onSave = onSettingsSave,
            .allocator = state.allocator,
        },
        .{
            .tts_url = state.config.tts_server_url,
            .tts_timeout_ms = state.config.tts_timeout_ms,
            .tts_retry_count = @intCast(state.config.tts_retry_count),
            .llm_url = state.config.llm_server_url,
        },
        state.io,
    );
    dialog.show();
}

// Activate - GTK Window Assembly
fn activate(app: ?*GtkApplication, user_data: gpointer) callconv(.c) void {
    _ = user_data;
    state.main_window = @ptrCast(gtk.gtk_application_window_new(app));
    gtk.gtk_window_set_title(state.main_window, "Metanoia - Bible Study");
    gtk.gtk_window_set_default_size(state.main_window, 1280, 800);

    app_theme = Theme.init("assets/themes/tokyo-night.css");
    app_theme.updateFontSizes(state.config.english_font_size, state.config.interlinear_font_size);

    const main_layout = gtk.gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk.gtk_window_set_child(state.main_window, main_layout);

    const entries = [_]gtk.GActionEntry{
        .{ .name = "rerender", .activate = onRerenderAction },
    };
    gtk.g_action_map_add_action_entries(@ptrCast(state.main_window), &entries, entries.len, null);

    const menu = gtk.g_menu_new();
    gtk.g_menu_append(menu, "Re-render Verse", "win.rerender");
    state.verse_popover = gtk.gtk_popover_menu_new_from_model(menu);
    gtk.gtk_widget_set_parent(state.verse_popover, @ptrCast(main_layout));
    gtk.gtk_popover_set_has_arrow(@ptrCast(state.verse_popover), false);

    // Toolbar
    const top_bar = gtk.gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    gtk.gtk_widget_add_css_class(top_bar, "headerbar");
    gtk.gtk_box_append(@ptrCast(main_layout), top_bar);

    const sidebar_toggle = gtk.gtk_button_new_with_label("\u{2261}");
    _ = gtk.g_signal_connect_data(sidebar_toggle, "clicked", @ptrCast(&onSidebarToggled), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), sidebar_toggle);

    const search_btn = gtk.gtk_button_new_with_label("Search Scripture...");
    gtk.gtk_widget_set_hexpand(search_btn, true);
    gtk.gtk_widget_add_css_class(search_btn, "search-trigger-btn");
    _ = gtk.g_signal_connect_data(search_btn, "clicked", @ptrCast(&onSearchTriggerClicked), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), search_btn);

    const prev_btn = gtk.gtk_button_new_with_label("<");
    _ = gtk.g_signal_connect_data(prev_btn, "clicked", @ptrCast(&onPrevChapterClicked), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), prev_btn);

    const next_btn = gtk.gtk_button_new_with_label(">");
    _ = gtk.g_signal_connect_data(next_btn, "clicked", @ptrCast(&onNextChapterClicked), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), next_btn);

    const f_left_plus = gtk.gtk_button_new_with_label("L+");
    _ = gtk.g_signal_connect_data(f_left_plus, "clicked", @ptrCast(&onFontAdjust), @ptrFromInt(1), null, 0);
    const f_left_minus = gtk.gtk_button_new_with_label("L-");
    _ = gtk.g_signal_connect_data(f_left_minus, "clicked", @ptrCast(&onFontAdjust), @ptrFromInt(2), null, 0);
    const f_right_plus = gtk.gtk_button_new_with_label("R+");
    _ = gtk.g_signal_connect_data(f_right_plus, "clicked", @ptrCast(&onFontAdjust), @ptrFromInt(3), null, 0);
    const f_right_minus = gtk.gtk_button_new_with_label("R-");
    _ = gtk.g_signal_connect_data(f_right_minus, "clicked", @ptrCast(&onFontAdjust), @ptrFromInt(4), null, 0);
    state.f_right_plus_btn = f_right_plus;
    state.f_right_minus_btn = f_right_minus;
    gtk.gtk_widget_set_visible(f_right_plus, false);
    gtk.gtk_widget_set_visible(f_right_minus, false);
    gtk.gtk_box_append(@ptrCast(top_bar), f_left_plus);
    gtk.gtk_box_append(@ptrCast(top_bar), f_left_minus);
    gtk.gtk_box_append(@ptrCast(top_bar), f_right_plus);
    gtk.gtk_box_append(@ptrCast(top_bar), f_right_minus);

    const parallel_btn = gtk.gtk_button_new_with_label("Parallel");
    _ = gtk.g_signal_connect_data(parallel_btn, "clicked", @ptrCast(&onParallelToggled), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), parallel_btn);

    const speaker_btn = gtk.gtk_button_new_with_label("\u{1F508}");
    _ = gtk.g_signal_connect_data(speaker_btn, "clicked", @ptrCast(&onSpeakerClicked), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), speaker_btn);

    const passage_btn = gtk.gtk_button_new_with_label("Passage");
    gtk.gtk_widget_add_css_class(passage_btn, "suggested-action");
    _ = gtk.g_signal_connect_data(passage_btn, "clicked", @ptrCast(&on_passage_btn_clicked), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), passage_btn);

    const settings_btn = gtk.gtk_button_new_with_label("\u{2699}\u{FE0F}");
    _ = gtk.g_signal_connect_data(settings_btn, "clicked", @ptrCast(&onSettingsBtnClicked), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), settings_btn);

    const llm_btn = gtk.gtk_button_new_with_label("LLM Study");
    _ = gtk.g_signal_connect_data(llm_btn, "clicked", @ptrCast(&onLlmClicked), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), llm_btn);

    const voices = [_]?[*:0]const u8{ "John Lennox", "Tommy", "Mari", "Jordan Peterson", "Sam Shamoun", "Jonathan Roumie", null };
    const voice_drop = gtk.gtk_drop_down_new_from_strings(&voices);
    const voice_ids = [_][]const u8{ "lennox", "tommy", "mari", "jordan", "shamoun", "roumie" };
    for (voice_ids, 0..) |id, idx| {
        if (std.mem.eql(u8, state.config.selected_voice, id)) {
            gtk.gtk_drop_down_set_selected(voice_drop, @intCast(idx));
            break;
        }
    }
    _ = gtk.g_signal_connect_data(voice_drop, "notify::selected", @ptrCast(&onVoiceChanged), null, null, 0);
    gtk.gtk_box_append(@ptrCast(top_bar), voice_drop);

    // Paned + Sidebar
    state.main_paned = @ptrCast(gtk.gtk_paned_new(GTK_ORIENTATION_HORIZONTAL));
    gtk.gtk_box_append(@ptrCast(main_layout), @ptrCast(state.main_paned));
    _ = gtk.g_signal_connect_data(state.main_paned, "notify::position", @ptrCast(&onPanedNotifyPosition), null, null, 0);

    state.main_status_bar = status_bar_cmp.StatusBar.init(state.allocator);
    state.main_status_bar.?.updateVoice(state.config.selected_voice);
    gtk.gtk_box_append(@ptrCast(main_layout), state.main_status_bar.?.box);

    state.main_sidebar = sidebar_cmp.Sidebar.init(state.allocator, state.io, onColorClicked);
    gtk.gtk_widget_set_visible(state.main_sidebar.?.box.?, false);
    gtk.gtk_paned_set_start_child(@ptrCast(state.main_paned), state.main_sidebar.?.box);
    gtk.gtk_paned_set_position(@ptrCast(state.main_paned), state.config.sidebar_width);

    state.chapter_summary_label = state.main_sidebar.?.summary_label;
    state.word_study_label = state.main_sidebar.?.word_study_label;
    state.llm_spinner = state.main_sidebar.?.llm_spinner;
    state.note_view = state.main_sidebar.?.note_view;
    state.note_buffer = state.main_sidebar.?.note_buffer;

    // Notebook
    state.main_notebook = @ptrCast(gtk.gtk_notebook_new());
    gtk.gtk_widget_add_css_class(@ptrCast(state.main_notebook), "main-content");
    gtk.gtk_paned_set_end_child(@ptrCast(state.main_paned), @ptrCast(state.main_notebook));
    _ = gtk.gtk_notebook_append_page(state.main_notebook, gtk.gtk_label_new("Dashboard Content"), gtk.gtk_label_new("Dashboard"));

    const study_paned = gtk.gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
    _ = gtk.gtk_notebook_append_page(state.main_notebook, study_paned, gtk.gtk_label_new("Study"));
    gtk.gtk_paned_set_position(@ptrCast(study_paned), 600);

    const left_scroll = gtk.gtk_scrolled_window_new();
    state.study_left_scroll = @ptrCast(left_scroll);
    gtk.gtk_widget_set_vexpand(left_scroll, true);
    state.study_left_view = @ptrCast(gtk.gtk_box_new(GTK_ORIENTATION_VERTICAL, 24));
    gtk.gtk_widget_set_name(@ptrCast(state.study_left_view), "left_view");
    gtk.gtk_scrolled_window_set_child(@ptrCast(left_scroll), @ptrCast(state.study_left_view));
    gtk.gtk_paned_set_start_child(@ptrCast(study_paned), left_scroll);

    const right_scroll = gtk.gtk_scrolled_window_new();
    state.study_right_scroll = @ptrCast(right_scroll);
    state.right_scroll_pane = @ptrCast(right_scroll);
    gtk.gtk_widget_set_vexpand(right_scroll, true);
    state.study_right_view = @ptrCast(gtk.gtk_box_new(GTK_ORIENTATION_VERTICAL, 24));
    gtk.gtk_widget_set_name(@ptrCast(state.study_right_view), "right_view");
    gtk.gtk_scrolled_window_set_child(@ptrCast(right_scroll), @ptrCast(state.study_right_view));
    gtk.gtk_paned_set_end_child(@ptrCast(study_paned), right_scroll);
    gtk.gtk_widget_set_visible(state.right_scroll_pane, false);

    const left_adj = gtk.gtk_scrolled_window_get_vadjustment(@ptrCast(left_scroll));
    const right_adj = gtk.gtk_scrolled_window_get_vadjustment(@ptrCast(right_scroll));
    _ = gtk.g_signal_connect_data(left_adj, "value-changed", @ptrCast(&onScrollChanged), right_adj, null, 0);
    _ = gtk.g_signal_connect_data(right_adj, "value-changed", @ptrCast(&onScrollChanged), left_adj, null, 0);

    // Modules
    state.tts_engine = TTSEngine.init(state.allocator, state.io);
    llm_engine = LLMEngine.init(state.allocator, state.io, state.db);
    search_instance = search_mod.Search.init(state.allocator, state.main_window, state.db, .{
        .onNavigate = onSearchNavigate,
        .onStatus = onSearchStatus,
    });
    nav_dialog_instance = nav_dialog.NavigationDialog.init(state.allocator, state.db, onNavNavigate);

    // Keyboard Shortcut
    gtk.gtk_window_present(state.main_window);
    const key_controller = gtk.gtk_event_controller_key_new();
    _ = gtk.g_signal_connect_data(key_controller, "key-pressed", @ptrCast(&onMainWindowKey), null, null, 0);
    gtk.gtk_widget_add_controller(@ptrCast(state.main_window), key_controller);

    // Initial load
    const last_book = std.mem.span(@as([*:0]const u8, @ptrCast(&state.config.last_book)));
    load_chapter_into_study(last_book, state.config.last_chapter, state.config.last_verse);
}

fn onScrollChanged(adj: ?*anyopaque, user_data: gpointer) callconv(.c) void {
    const target_adj: ?*GtkAdjustment = @ptrCast(user_data);
    const value = gtk.gtk_adjustment_get_value(adj);
    if (@abs(value - gtk.gtk_adjustment_get_value(target_adj.?)) > 1.0) {
        gtk.gtk_adjustment_set_value(target_adj.?, value);
    }
}

fn on_passage_btn_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn; _ = user_data;
    nav_dialog_instance.show(state.main_window);
}

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var threaded_io = std.Io.Threaded.init(gpa, .{});
    const io = threaded_io.io();

    state = AppState.init(gpa, io);

    if (bible.sqlite3_open("data/bible.db", @ptrCast(&state.db)) != SQLITE_OK) {
        std.debug.print("Failed to open database\n", .{});
        return;
    }
    defer _ = bible.sqlite3_close(state.db.?);
    bible.init_db(state.db.?) catch |err| {
        std.debug.print("Failed to initialize database: {any}\n", .{err});
    };

    state.config = Config.load(state.allocator, state.io);

    const app = gtk.gtk_application_new("org.bytecats.metanoia", 0);
    defer gtk.g_object_unref(app);
    _ = gtk.g_signal_connect_data(app, "activate", @ptrCast(&activate), null, null, 0);
    const status = gtk.g_application_run(@ptrCast(app), 0, null);
    if (status != 0) std.process.exit(1);
}
