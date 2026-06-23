const std = @import("std");
const gtk = @import("gtk.zig");
const bible = @import("bible_db.zig");
const models = @import("models/config.zig");
const sidebar_cmp = @import("ui/components/sidebar.zig");
const status_bar_cmp = @import("ui/components/status_bar.zig");
const tts_engine = @import("services/tts_engine.zig");

const GtkWindow = gtk.GtkWindow;
const GtkWidget = gtk.GtkWidget;
const GtkBox = gtk.GtkBox;
const GtkPaned = gtk.GtkPaned;
const GtkNotebook = gtk.GtkNotebook;
const GtkCssProvider = gtk.GtkCssProvider;
const GtkLabel = gtk.GtkLabel;
const GtkStack = gtk.GtkStack;
const GtkButton = gtk.GtkButton;
const GtkFlowBox = gtk.GtkFlowBox;
const SearchResult = bible.SearchResult;
const sqlite3 = bible.sqlite3;

pub const ActiveNoteVerse = struct {
    book: [64]u8,
    ch: i32,
    v: i32,
};

pub const AppState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    config: models.Config,
    db: ?*sqlite3,

    // GTK Widget References
    main_window: ?*GtkWindow,
    main_notebook: ?*GtkNotebook,
    bible_view: ?*GtkBox,
    main_paned: ?*GtkPaned,
    font_provider: ?*GtkCssProvider,
    main_sidebar: ?*sidebar_cmp.Sidebar,
    main_status_bar: ?*status_bar_cmp.StatusBar,

    // Search state
    search_window: ?*GtkWindow,
    search_entry: ?*GtkWidget,
    search_results_list: ?*GtkWidget,
    search_results_container: ?*GtkWidget,
    persistent_search_results: [50]SearchResult,

    // Study view
    study_left_view: ?*GtkBox,
    study_right_view: ?*GtkBox,
    study_left_scroll: ?*GtkWidget,
    study_right_scroll: ?*GtkWidget,
    right_scroll_pane: ?*GtkWidget,
    f_right_plus_btn: ?*GtkWidget,
    f_right_minus_btn: ?*GtkWidget,

    // Sidebar sub-references
    chapter_summary_label: ?*GtkLabel,
    word_study_label: ?*GtkLabel,
    llm_spinner: ?*GtkWidget,
    note_view: ?*GtkWidget,
    note_buffer: ?*anyopaque,

    // Navigation
    selection_dialog: ?*GtkWindow,
    modal_stack: ?*GtkStack,
    modal_title: ?*GtkLabel,
    cur_book_name: [64]u8,
    cur_chapter: i32,

    // Verse data
    current_chapter_verses: ?std.ArrayListUnmanaged([]const u8),
    verse_labels: ?std.ArrayListUnmanaged(?*GtkWidget),
    highlighted_index: ?usize,
    rerender_target_index: usize,
    verse_popover: ?*GtkWidget,
    active_note_verse: ?ActiveNoteVerse,

    // TTS
    tts_engine: ?*tts_engine.TTSEngine,
    tts_button_ref: ?*GtkButton,
    tts_start_index: usize,
    last_speaker_click_time: i64,
    tts_lock: std.atomic.Value(bool),
    tts_proc_lock: std.atomic.Value(bool),
    tts_process: ?*std.process.Child,
    tts_playing: std.atomic.Value(bool),
    tts_stop_requested: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) AppState {
        return .{
            .allocator = allocator,
            .io = io,
            .config = models.Config{},
            .db = null,
            .main_window = null,
            .main_notebook = null,
            .bible_view = null,
            .main_paned = null,
            .font_provider = null,
            .main_sidebar = null,
            .main_status_bar = null,
            .search_window = null,
            .search_entry = null,
            .search_results_list = null,
            .search_results_container = null,
            .persistent_search_results = undefined,
            .study_left_view = null,
            .study_right_view = null,
            .study_left_scroll = null,
            .study_right_scroll = null,
            .right_scroll_pane = null,
            .f_right_plus_btn = null,
            .f_right_minus_btn = null,
            .chapter_summary_label = null,
            .word_study_label = null,
            .llm_spinner = null,
            .note_view = null,
            .note_buffer = null,
            .selection_dialog = null,
            .modal_stack = null,
            .modal_title = null,
            .cur_book_name = @splat(0),
            .cur_chapter = 1,
            .current_chapter_verses = null,
            .verse_labels = null,
            .highlighted_index = null,
            .rerender_target_index = 0,
            .verse_popover = null,
            .active_note_verse = null,
            .tts_engine = null,
            .tts_button_ref = null,
            .tts_start_index = 0,
            .last_speaker_click_time = 0,
            .tts_lock = std.atomic.Value(bool).init(false),
            .tts_proc_lock = std.atomic.Value(bool).init(false),
            .tts_process = null,
            .tts_playing = std.atomic.Value(bool).init(false),
            .tts_stop_requested = std.atomic.Value(bool).init(false),
        };
    }
};
