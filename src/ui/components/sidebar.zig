const std = @import("std");
const gtk = @import("../../gtk.zig");

const GtkWidget = gtk.GtkWidget;
const GtkBox = gtk.GtkBox;
const GtkButton = gtk.GtkButton;
const GtkLabel = gtk.GtkLabel;
const GtkTextBuffer = anyopaque;
const gpointer = gtk.gpointer;

pub const Sidebar = struct {
    box: ?*GtkWidget,
    voice_dropdown: ?*GtkWidget,
    log_buffer: ?*anyopaque,
    
    // Sub-components for external access
    summary_label: ?*GtkLabel = null,
    word_study_label: ?*GtkLabel = null,
    llm_spinner: ?*GtkWidget = null,
    note_view: ?*GtkWidget = null,
    note_buffer: ?*anyopaque = null,
    
    allocator: std.mem.Allocator,
    io: std.Io,
    onColorClicked: ?*const fn (btn: ?*GtkButton, user_data: gpointer) callconv(.c) void,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, onColorClicked: ?*const fn (btn: ?*GtkButton, user_data: gpointer) callconv(.c) void) *Sidebar {
        const self = allocator.create(Sidebar) catch unreachable;
        
        const sidebar = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 15);
        gtk.gtk_widget_add_css_class(sidebar, "sidebar");
        gtk.gtk_widget_set_size_request(sidebar, 250, -1);

        self.* = .{
            .box = sidebar,
            .voice_dropdown = null,
            .log_buffer = null,
            .allocator = allocator,
            .io = io,
            .onColorClicked = onColorClicked,
        };

        self.createSummarySection();
        self.createWordStudySection();
        self.createNotesSection();
        self.createHighlightSection();
        self.createTTSSection();
        self.createLogSection();
        
        self.refreshVoices();

        return self;
    }

    fn createSummarySection(self: *Sidebar) void {
        const expander = gtk.gtk_expander_new("Chapter Summary");
        gtk.gtk_widget_add_css_class(expander, "sidebar-expander");
        gtk.gtk_expander_set_expanded(@ptrCast(expander), true);
        gtk.gtk_box_append(@ptrCast(self.box), expander);

        self.summary_label = @ptrCast(gtk.gtk_label_new("No summary loaded"));
        gtk.gtk_label_set_wrap(self.summary_label, true);
        gtk.gtk_widget_add_css_class(@ptrCast(self.summary_label), "sidebar-label");
        gtk.gtk_expander_set_child(@ptrCast(expander), @ptrCast(self.summary_label));
    }

    fn createWordStudySection(self: *Sidebar) void {
        const expander = gtk.gtk_expander_new("Word Study");
        gtk.gtk_widget_add_css_class(expander, "sidebar-expander");
        gtk.gtk_expander_set_expanded(@ptrCast(expander), true);
        gtk.gtk_box_append(@ptrCast(self.box), expander);

        const word_study_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 10);
        gtk.gtk_expander_set_child(@ptrCast(expander), word_study_box);

        self.llm_spinner = gtk.gtk_spinner_new();
        gtk.gtk_widget_set_visible(self.llm_spinner, false);
        gtk.gtk_widget_set_halign(self.llm_spinner, 3); // Center
        gtk.gtk_box_append(@ptrCast(word_study_box), self.llm_spinner);

        self.word_study_label = @ptrCast(gtk.gtk_label_new("Click a word to begin study"));
        gtk.gtk_label_set_wrap(self.word_study_label, true);
        gtk.gtk_widget_add_css_class(@ptrCast(self.word_study_label), "sidebar-label");
        gtk.gtk_box_append(@ptrCast(word_study_box), @ptrCast(self.word_study_label));
    }

    fn createNotesSection(self: *Sidebar) void {
        const expander = gtk.gtk_expander_new("Verse Notes");
        gtk.gtk_widget_add_css_class(expander, "sidebar-expander");
        gtk.gtk_expander_set_expanded(@ptrCast(expander), true);
        gtk.gtk_box_append(@ptrCast(self.box), expander);

        const notes_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 8);
        gtk.gtk_expander_set_child(@ptrCast(expander), notes_box);

        self.note_view = gtk.gtk_text_view_new();
        gtk.gtk_widget_set_size_request(self.note_view, -1, 200);
        gtk.gtk_widget_add_css_class(self.note_view, "note-editor");
        self.note_buffer = gtk.gtk_text_view_get_buffer(self.note_view);
        gtk.gtk_box_append(@ptrCast(notes_box), self.note_view);
    }

    fn createHighlightSection(self: *Sidebar) void {
        const expander = gtk.gtk_expander_new("Permanent Highlight");
        gtk.gtk_widget_add_css_class(expander, "sidebar-expander");
        gtk.gtk_expander_set_expanded(@ptrCast(expander), true);
        gtk.gtk_box_append(@ptrCast(self.box), expander);

        const colors_grid = gtk.gtk_flow_box_new();
        gtk.gtk_flow_box_set_min_children_per_line(@ptrCast(colors_grid), 4);
        gtk.gtk_flow_box_set_selection_mode(@ptrCast(colors_grid), 0);
        gtk.gtk_widget_set_halign(colors_grid, 3); // Center
        gtk.gtk_expander_set_child(@ptrCast(expander), colors_grid);

        const color_list = [_]struct { name: [*:0]const u8, hex: [*:0]const u8, class: [*:0]const u8 }{
            .{ .name = "", .hex = "#ffdfa344", .class = "h-yellow" },
            .{ .name = "", .hex = "#b9f27c44", .class = "h-green" },
            .{ .name = "", .hex = "#7da6ff44", .class = "h-blue" },
            .{ .name = "", .hex = "#ff7a9344", .class = "h-red" },
            .{ .name = "", .hex = "#d0b3ff44", .class = "h-purple" },
            .{ .name = "", .hex = "#89ddff44", .class = "h-cyan" },
            .{ .name = "", .hex = "#ffc0b944", .class = "h-orange" },
            .{ .name = "Clear", .hex = "none", .class = "h-clear" },
        };

        for (color_list) |c| {
            const c_btn = gtk.gtk_button_new_with_label(c.name);
            gtk.gtk_widget_add_css_class(c_btn, "candy-btn");
            gtk.gtk_widget_add_css_class(c_btn, c.class);
            if (self.onColorClicked) |cb| {
                _ = gtk.g_signal_connect_data(c_btn, "clicked", cb, @constCast(@ptrCast(c.hex)), null, 0);
            }
            gtk.gtk_flow_box_insert(@ptrCast(colors_grid), c_btn, -1);
        }
    }

    fn createTTSSection(self: *Sidebar) void {
        const expander = gtk.gtk_expander_new("TTS Control Center");
        gtk.gtk_widget_add_css_class(expander, "sidebar-expander");
        gtk.gtk_expander_set_expanded(@ptrCast(expander), true);
        gtk.gtk_box_append(@ptrCast(self.box), expander);

        const v_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_VERTICAL, 8);
        gtk.gtk_expander_set_child(@ptrCast(expander), v_box);

        const label = gtk.gtk_label_new("Active Voice Profile:");
        gtk.gtk_widget_set_halign(label, gtk.GTK_ALIGN_START);
        gtk.gtk_box_append(@ptrCast(v_box), label);

        const placeholder = [_]?[*:0]const u8{ "Synchronizing...", null };
        self.voice_dropdown = gtk.gtk_drop_down_new_from_strings(&placeholder);
        gtk.gtk_box_append(@ptrCast(v_box), self.voice_dropdown);
    }

    fn createLogSection(self: *Sidebar) void {
        const expander = gtk.gtk_expander_new("System Logs");
        gtk.gtk_widget_add_css_class(expander, "sidebar-expander");
        gtk.gtk_expander_set_expanded(@ptrCast(expander), false);
        gtk.gtk_box_append(@ptrCast(self.box), expander);

        const scroll = gtk.gtk_scrolled_window_new();
        gtk.gtk_widget_set_size_request(scroll, -1, 150);
        gtk.gtk_expander_set_child(@ptrCast(expander), scroll);

        const text_view = gtk.gtk_text_view_new();
        gtk.gtk_text_view_set_editable(text_view, false);
        gtk.gtk_widget_add_css_class(text_view, "log-view");
        self.log_buffer = gtk.gtk_text_view_get_buffer(text_view);
        gtk.gtk_scrolled_window_set_child(@ptrCast(scroll), text_view);
        
        self.log("System initialized. Neural engine online.");
    }

    pub fn log(self: *Sidebar, message: []const u8) void {
        if (self.log_buffer) |buf| {
            var iter: [128]u8 = undefined;
            gtk.gtk_text_buffer_get_end_iter(buf, &iter);
            const ts = gtk.g_get_monotonic_time();
            const timestamped = std.fmt.allocPrintSentinel(self.allocator, "[{d}] {s}\n", .{ts, message}, 0) catch return;
            defer self.allocator.free(timestamped);
            gtk.gtk_text_buffer_insert(buf, &iter, timestamped.ptr, -1);
        }
    }

    pub fn refreshVoices(self: *Sidebar) void {
        const Task = struct {
            sidebar: *Sidebar,
            fn run(p: gpointer) callconv(.c) gpointer {
                const s: *@This() = @ptrCast(@alignCast(p));
                const allocator = s.sidebar.allocator;
                s.sidebar.log("Syncing voice library...");
                const argv = &[_][]const u8{ "curl", "-s", "http://127.0.0.1:8000/voice_status" };
                var child = std.process.spawn(s.sidebar.io, .{ .argv = argv, .stdout = .pipe }) catch return null;
                
                var stdout_list = std.ArrayListUnmanaged(u8).empty;
                defer stdout_list.deinit(allocator);
                
                var r_buf: [4096]u8 = undefined;
                var f_reader = child.stdout.?.reader(s.sidebar.io, &r_buf);
                const json_data = f_reader.interface.allocRemaining(allocator, std.Io.Limit.unlimited) catch return null;
                defer allocator.free(json_data);
                
                _ = child.wait(s.sidebar.io) catch {};
                
                const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_data, .{}) catch return null;
                defer parsed.deinit();
                
                var names_list = std.ArrayListUnmanaged(?[*:0]const u8).empty;
                if (parsed.value == .object) {
                    var iter = parsed.value.object.iterator();
                    while (iter.next()) |entry| {
                        if (entry.value_ptr.* == .object) {
                            if (entry.value_ptr.*.object.get("display_name")) |dn| {
                                names_list.append(allocator, allocator.dupeZ(u8, dn.string) catch continue) catch continue;
                            }
                        }
                    }
                }
                names_list.append(allocator, null) catch {};
                const UpdateUI = struct {
                    sb: *Sidebar,
                    voice_names: [*:null]?[*:0]const u8,
                    fn update(ptr: gpointer) callconv(.c) bool {
                        const ctx: *@This() = @ptrCast(@alignCast(ptr));
                        const new_drop = gtk.gtk_drop_down_new_from_strings(ctx.voice_names);
                        const parent = gtk.gtk_widget_get_parent(ctx.sb.voice_dropdown);
                        if (parent) |p_box| {
                            gtk.gtk_box_remove(@ptrCast(p_box), ctx.sb.voice_dropdown);
                            gtk.gtk_box_append(@ptrCast(p_box), new_drop);
                            ctx.sb.voice_dropdown = new_drop;
                        }
                        ctx.sb.log("Voice library synchronized.");
                        return false;
                    }
                };
                const ui_ctx = allocator.create(UpdateUI) catch return null;
                ui_ctx.* = .{ .sb = s.sidebar, .voice_names = @ptrCast(names_list.toOwnedSlice(allocator) catch unreachable) };
                _ = gtk.g_idle_add(&UpdateUI.update, ui_ctx);
                allocator.destroy(s);
                return null;
            }
        };
        const task = self.allocator.create(Task) catch return;
        task.* = .{ .sidebar = self };
        _ = gtk.g_thread_new("voice-sync", &Task.run, task);
    }
};
