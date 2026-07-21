//! Generic collapsible sidebar with expander sections.
//!
//! Provides pre-built sections: summary, word study, notes, highlights,
//! TTS control, and system logs. All external actions are routed through
//! `SidebarCallbacks`, keeping the component decoupled from application
//! state and services.

const std = @import("std");
const ffi = @import("../ffi.zig");
const signal_lib = @import("../signal.zig");
const Signal = signal_lib.Signal;

pub const HIGHLIGHT_COLORS = [_]struct { name: [*:0]const u8, hex: [*:0]const u8, class: [*:0]const u8 }{
    .{ .name = "", .hex = "#ffdfa344", .class = "h-yellow" },
    .{ .name = "", .hex = "#b9f27c44", .class = "h-green" },
    .{ .name = "", .hex = "#7da6ff44", .class = "h-blue" },
    .{ .name = "", .hex = "#ff7a9344", .class = "h-red" },
    .{ .name = "", .hex = "#d0b3ff44", .class = "h-purple" },
    .{ .name = "", .hex = "#89ddff44", .class = "h-cyan" },
    .{ .name = "", .hex = "#ffc0b944", .class = "h-orange" },
    .{ .name = "Clear", .hex = "none", .class = "h-clear" },
};

pub const SidebarCallbacks = struct {
    /// Called when a highlight color is clicked. `hex_color` is the
    /// color value (e.g. "#ffdfa344" or "none" for clear).
    onColorClicked: ?*const fn (hex_color: [*:0]const u8) void = null,

    /// Called when the voice dropdown selection changes. `index` is the
    /// selected index; `name` is the display name of the voice.
    onVoiceChanged: ?*const fn (index: u32, name: [*:0]const u8) void = null,

    /// Called when a word study is requested. `word` is the text to study.
    onWordStudy: ?*const fn (word: []const u8) void = null,

    /// Called when a note is saved. `text` is the full note content.
    onNoteSaved: ?*const fn (text: []const u8) void = null,
};

pub const Sidebar = struct {
    box: ?*ffi.GtkWidget,
    voice_dropdown: ?*ffi.GtkWidget,
    log_buffer: ?*anyopaque,

    // Sub-components for external access
    summary_label: ?*ffi.GtkLabel = null,
    word_study_label: ?*ffi.GtkLabel = null,
    llm_spinner: ?*ffi.GtkWidget = null,
    note_view: ?*ffi.GtkWidget = null,
    note_buffer: ?*anyopaque = null,

    allocator: std.mem.Allocator,
    callbacks: SidebarCallbacks,

    pub fn init(allocator: std.mem.Allocator, callbacks: SidebarCallbacks) *Sidebar {
        const self = allocator.create(Sidebar) catch unreachable;

        const sidebar = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 15);
        ffi.gtk_widget_add_css_class(sidebar, "sidebar");
        ffi.gtk_widget_set_size_request(sidebar, 250, -1);

        self.* = .{
            .box = sidebar,
            .voice_dropdown = null,
            .log_buffer = null,
            .allocator = allocator,
            .callbacks = callbacks,
        };

        self.createSummarySection();
        self.createWordStudySection();
        self.createNotesSection();
        self.createHighlightSection();
        self.createTTSSection();
        self.createLogSection();

        self.refreshVoices(&.{ null });

        return self;
    }

    fn createSummarySection(self: *Sidebar) void {
        const expander = ffi.gtk_expander_new("Chapter Summary");
        ffi.gtk_widget_add_css_class(expander, "sidebar-expander");
        ffi.gtk_expander_set_expanded(@ptrCast(expander), true);
        ffi.gtk_box_append(@ptrCast(self.box), expander);

        self.summary_label = @ptrCast(ffi.gtk_label_new("No summary loaded"));
        ffi.gtk_label_set_wrap(self.summary_label, true);
        ffi.gtk_label_set_wrap_mode(self.summary_label, ffi.PANGO_WRAP_WORD_CHAR);
        ffi.gtk_label_set_max_width_chars(self.summary_label, 1);
        ffi.gtk_label_set_xalign(self.summary_label, 0);
        ffi.gtk_widget_set_hexpand(@ptrCast(self.summary_label), true);
        ffi.gtk_widget_set_halign(@ptrCast(self.summary_label), ffi.GTK_ALIGN_FILL);
        ffi.gtk_widget_add_css_class(@ptrCast(self.summary_label), "sidebar-label");
        ffi.gtk_expander_set_child(@ptrCast(expander), @ptrCast(self.summary_label));
    }

    fn createWordStudySection(self: *Sidebar) void {
        const expander = ffi.gtk_expander_new("Word Study");
        ffi.gtk_widget_add_css_class(expander, "sidebar-expander");
        ffi.gtk_expander_set_expanded(@ptrCast(expander), true);
        ffi.gtk_box_append(@ptrCast(self.box), expander);

        const word_study_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 10);
        ffi.gtk_expander_set_child(@ptrCast(expander), word_study_box);

        self.llm_spinner = ffi.gtk_spinner_new();
        ffi.gtk_widget_set_visible(self.llm_spinner, false);
        ffi.gtk_widget_set_halign(self.llm_spinner, ffi.GTK_ALIGN_CENTER);
        ffi.gtk_box_append(@ptrCast(word_study_box), self.llm_spinner);

        self.word_study_label = @ptrCast(ffi.gtk_label_new("Click a word to begin study"));
        ffi.gtk_label_set_wrap(self.word_study_label, true);
        ffi.gtk_label_set_wrap_mode(self.word_study_label, ffi.PANGO_WRAP_WORD_CHAR);
        ffi.gtk_label_set_max_width_chars(self.word_study_label, 1);
        ffi.gtk_label_set_xalign(self.word_study_label, 0);
        ffi.gtk_widget_set_hexpand(@ptrCast(self.word_study_label), true);
        ffi.gtk_widget_set_halign(@ptrCast(self.word_study_label), ffi.GTK_ALIGN_FILL);
        ffi.gtk_widget_add_css_class(@ptrCast(self.word_study_label), "sidebar-label");
        ffi.gtk_box_append(@ptrCast(word_study_box), @ptrCast(self.word_study_label));
    }

    fn createNotesSection(self: *Sidebar) void {
        const expander = ffi.gtk_expander_new("Verse Notes");
        ffi.gtk_widget_add_css_class(expander, "sidebar-expander");
        ffi.gtk_expander_set_expanded(@ptrCast(expander), true);
        ffi.gtk_box_append(@ptrCast(self.box), expander);

        const notes_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 8);
        ffi.gtk_expander_set_child(@ptrCast(expander), notes_box);

        self.note_view = ffi.gtk_text_view_new();
        ffi.gtk_widget_set_size_request(self.note_view, -1, 200);
        ffi.gtk_widget_add_css_class(self.note_view, "note-editor");
        self.note_buffer = ffi.gtk_text_view_get_buffer(self.note_view);
        ffi.gtk_box_append(@ptrCast(notes_box), self.note_view);
    }

    fn createHighlightSection(self: *Sidebar) void {
        const expander = ffi.gtk_expander_new("Permanent Highlight");
        ffi.gtk_widget_add_css_class(expander, "sidebar-expander");
        ffi.gtk_expander_set_expanded(@ptrCast(expander), true);
        ffi.gtk_box_append(@ptrCast(self.box), expander);

        const colors_grid = ffi.gtk_flow_box_new();
        ffi.gtk_flow_box_set_min_children_per_line(@ptrCast(colors_grid), 4);
        ffi.gtk_flow_box_set_selection_mode(@ptrCast(colors_grid), 0);
        ffi.gtk_widget_set_halign(colors_grid, ffi.GTK_ALIGN_CENTER);
        ffi.gtk_expander_set_child(@ptrCast(expander), colors_grid);

        for (HIGHLIGHT_COLORS) |c| {
            const c_btn = ffi.gtk_button_new_with_label(c.name);
            ffi.gtk_widget_add_css_class(c_btn, "candy-btn");
            ffi.gtk_widget_add_css_class(c_btn, c.class);
            if (self.callbacks.onColorClicked) |cb| {
                const ColorBridge = struct {
                    static_cb: *const fn ([*:0]const u8) void,
                    hex: [*:0]const u8,
                    fn bridge(_: ?*ffi.GtkButton, data: ffi.gpointer) callconv(.c) void {
                        const ctx: *@This() = @ptrCast(@alignCast(data));
                        ctx.static_cb(ctx.hex);
                    }
                    fn destroy(data: ffi.gpointer, _: ?*anyopaque) callconv(.c) void {
                        const ctx: *@This() = @ptrCast(@alignCast(data));
                        std.heap.page_allocator.destroy(ctx);
                    }
                };
                const bridge = std.heap.page_allocator.create(ColorBridge) catch continue;
                bridge.* = .{ .static_cb = cb, .hex = c.hex };
                _ = Signal.connect(c_btn, "clicked", @ptrCast(&ColorBridge.bridge), bridge, ColorBridge.destroy);
            }
            ffi.gtk_flow_box_insert(@ptrCast(colors_grid), c_btn, -1);
        }
    }

    fn createTTSSection(self: *Sidebar) void {
        const expander = ffi.gtk_expander_new("TTS Control Center");
        ffi.gtk_widget_add_css_class(expander, "sidebar-expander");
        ffi.gtk_expander_set_expanded(@ptrCast(expander), true);
        ffi.gtk_box_append(@ptrCast(self.box), expander);

        const v_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 8);
        ffi.gtk_expander_set_child(@ptrCast(expander), v_box);

        const label = ffi.gtk_label_new("Active Voice Profile:");
        ffi.gtk_widget_set_halign(label, ffi.GTK_ALIGN_START);
        ffi.gtk_box_append(@ptrCast(v_box), label);

        const placeholder = [_]?[*:0]const u8{ "Synchronizing...", null };
        self.voice_dropdown = ffi.gtk_drop_down_new_from_strings(&placeholder);
        ffi.gtk_box_append(@ptrCast(v_box), self.voice_dropdown);
    }

    fn createLogSection(self: *Sidebar) void {
        const expander = ffi.gtk_expander_new("System Logs");
        ffi.gtk_widget_add_css_class(expander, "sidebar-expander");
        ffi.gtk_expander_set_expanded(@ptrCast(expander), false);
        ffi.gtk_box_append(@ptrCast(self.box), expander);

        const scroll = ffi.gtk_scrolled_window_new();
        ffi.gtk_widget_set_size_request(scroll, -1, 150);
        ffi.gtk_expander_set_child(@ptrCast(expander), scroll);

        const text_view = ffi.gtk_text_view_new();
        ffi.gtk_text_view_set_editable(text_view, false);
        ffi.gtk_widget_add_css_class(text_view, "log-view");
        self.log_buffer = ffi.gtk_text_view_get_buffer(text_view);
        ffi.gtk_scrolled_window_set_child(@ptrCast(scroll), text_view);

        self.log("System initialized. Neural engine online.");
    }

    pub fn deinit(self: *Sidebar) void {
        self.allocator.destroy(self);
    }

    pub fn log(self: *Sidebar, message: []const u8) void {
        if (self.log_buffer) |buf| {
            var iter: [128]u8 = undefined;
            ffi.gtk_text_buffer_get_end_iter(buf, &iter);
            const ts = ffi.g_get_monotonic_time();
            const timestamped = std.fmt.allocPrintSentinel(self.allocator, "[{d}] {s}\n", .{ ts, message }, 0) catch return;
            defer self.allocator.free(timestamped);
            ffi.gtk_text_buffer_insert(buf, &iter, timestamped.ptr, -1);
        }
    }

    /// Update the voice dropdown with a list of voice names.
    /// The list must be null-terminated (last element is `null`).
    pub fn refreshVoices(self: *Sidebar, voice_names: []const ?[*:0]const u8) void {
        const new_drop = ffi.gtk_drop_down_new_from_strings(@ptrCast(voice_names.ptr));
        if (self.voice_dropdown) |old| {
            const parent = ffi.gtk_widget_get_parent(old);
            if (parent) |p_box| {
                ffi.gtk_box_remove(@ptrCast(p_box), old);
                ffi.gtk_box_append(@ptrCast(p_box), new_drop);
            }
        }
        self.voice_dropdown = new_drop;

        if (self.callbacks.onVoiceChanged) |cb| {
            // Connect dropdown "notify::selected" to fire callback on change
            const VoiceBridge = struct {
                static_cb: *const fn (u32, [*:0]const u8) void,
                dropdown: ?*ffi.GtkWidget,
                names: []const ?[*:0]const u8,
                fn onChange(_: ?*anyopaque, _: ?*anyopaque, data: ffi.gpointer) callconv(.c) void {
                    const ctx: *@This() = @ptrCast(@alignCast(data));
                    const idx = ffi.gtk_drop_down_get_selected(ctx.dropdown);
                    if (idx < ctx.names.len) {
                        if (ctx.names[idx]) |name| {
                            ctx.static_cb(idx, name);
                        }
                    }
                }
                fn destroy(data: ffi.gpointer, _: ?*anyopaque) callconv(.c) void {
                    const ctx: *@This() = @ptrCast(@alignCast(data));
                    std.heap.page_allocator.destroy(ctx);
                }
            };
            const bridge = std.heap.page_allocator.create(VoiceBridge) catch return;
            bridge.* = .{ .static_cb = cb, .dropdown = new_drop, .names = voice_names };
            _ = Signal.connect(new_drop, "notify::selected", @ptrCast(&VoiceBridge.onChange), bridge, VoiceBridge.destroy);
        }

        self.log("Voice library synchronized.");
    }
};
