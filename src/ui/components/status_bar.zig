const std = @import("std");
const gtk = @import("../../gtk.zig");

const GtkWidget = gtk.GtkWidget;
const GtkLabel = gtk.GtkLabel;
const GtkBox = gtk.GtkBox;
const GtkProgressBar = gtk.GtkProgressBar;
const GtkSeparator = gtk.GtkSeparator;
const gpointer = gtk.gpointer;

pub const StatusBar = struct {
    box: ?*GtkWidget,
    status_icon: ?*GtkWidget,
    status_label: ?*GtkLabel,
    progress_bar: ?*GtkProgressBar,
    voice_label: ?*GtkLabel,
    db_label: ?*GtkLabel,
    engine_label: ?*GtkLabel,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) *StatusBar {
        const self = allocator.create(StatusBar) catch unreachable;

        const main_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 0);
        gtk.gtk_widget_add_css_class(main_box, "status-bar");

        // --- LEFT SECTION: Status & Icon ---
        const left_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 8);
        gtk.gtk_widget_add_css_class(left_box, "status-bar-left");
        
        const status_icon = gtk.gtk_image_new_from_icon_name("emblem-system-symbolic");
        gtk.gtk_widget_add_css_class(status_icon, "status-icon");
        gtk.gtk_box_append(@ptrCast(left_box), status_icon);

        const status_label = @as(?*GtkLabel, @ptrCast(gtk.gtk_label_new("System Ready")));
        gtk.gtk_label_set_xalign(status_label, 0.0);
        gtk.gtk_widget_add_css_class(@ptrCast(status_label), "status-bar-label");
        gtk.gtk_box_append(@ptrCast(left_box), @ptrCast(status_label));
        
        gtk.gtk_box_append(@ptrCast(main_box), left_box);

        // --- CENTER SECTION: Progress ---
        const center_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 0);
        gtk.gtk_widget_set_hexpand(center_box, true);
        gtk.gtk_widget_set_halign(center_box, gtk.GTK_ALIGN_CENTER);
        
        const progress_bar = @as(?*GtkProgressBar, @ptrCast(gtk.gtk_progress_bar_new()));
        gtk.gtk_widget_set_size_request(@ptrCast(progress_bar), 200, 4);
        gtk.gtk_widget_set_valign(@ptrCast(progress_bar), gtk.GTK_ALIGN_CENTER);
        gtk.gtk_widget_set_visible(@ptrCast(progress_bar), false);
        gtk.gtk_widget_add_css_class(@ptrCast(progress_bar), "status-progress");
        gtk.gtk_box_append(@ptrCast(center_box), @ptrCast(progress_bar));
        
        gtk.gtk_box_append(@ptrCast(main_box), center_box);

        // --- RIGHT SECTION: Telemetry ---
        const right_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 12);
        gtk.gtk_widget_add_css_class(right_box, "status-bar-right");

        // Voice Segment
        const voice_box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 4);
        const v_icon = gtk.gtk_image_new_from_icon_name("audio-input-microphone-symbolic");
        gtk.gtk_box_append(@ptrCast(voice_box), v_icon);
        const voice_label = @as(?*GtkLabel, @ptrCast(gtk.gtk_label_new("Voice: Default")));
        gtk.gtk_widget_add_css_class(@ptrCast(voice_label), "status-telemetry-item");
        gtk.gtk_box_append(@ptrCast(voice_box), @ptrCast(voice_label));
        gtk.gtk_box_append(@ptrCast(right_box), voice_box);

        gtk.gtk_box_append(@ptrCast(right_box), gtk.gtk_separator_new(gtk.GTK_ORIENTATION_VERTICAL));

        // DB Segment
        const db_label = @as(?*GtkLabel, @ptrCast(gtk.gtk_label_new("DB: Connected")));
        gtk.gtk_widget_add_css_class(@ptrCast(db_label), "status-telemetry-item");
        gtk.gtk_box_append(@ptrCast(right_box), @ptrCast(db_label));

        gtk.gtk_box_append(@ptrCast(right_box), gtk.gtk_separator_new(gtk.GTK_ORIENTATION_VERTICAL));

        // Engine Segment
        const engine_label = @as(?*GtkLabel, @ptrCast(gtk.gtk_label_new("Engine: Idle")));
        gtk.gtk_widget_add_css_class(@ptrCast(engine_label), "status-telemetry-item-bold");
        gtk.gtk_box_append(@ptrCast(right_box), @ptrCast(engine_label));

        gtk.gtk_box_append(@ptrCast(main_box), right_box);

        self.* = .{
            .box = main_box,
            .status_icon = status_icon,
            .status_label = status_label,
            .progress_bar = progress_bar,
            .voice_label = voice_label,
            .db_label = db_label,
            .engine_label = engine_label,
            .allocator = allocator,
        };

        return self;
    }

    pub fn updateStatus(self: *StatusBar, message: []const u8, is_error: bool) void {
        const UpdateUI = struct {
            self: *StatusBar,
            msg: [*:0]const u8,
            err: bool,
            fn update(ptr: gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                const allocator = ctx.self.allocator;
                const status_bar = ctx.self;
                const msg_ptr = ctx.msg;
                const is_err = ctx.err;
                
                const color = if (is_err) "#f7768e" else "#7aa2f7";
                const icon = if (is_err) "dialog-error-symbolic" else "emblem-system-symbolic";
                
                const markup = std.fmt.allocPrintSentinel(allocator, "<span foreground='{s}'>{s}</span>", .{color, msg_ptr}, 0) catch {
                    allocator.free(std.mem.span(msg_ptr));
                    allocator.destroy(ctx);
                    return false;
                };
                
                gtk.gtk_label_set_markup(status_bar.status_label, markup.ptr);
                gtk.gtk_image_set_from_icon_name(status_bar.status_icon, icon);
                
                allocator.free(markup);
                allocator.free(std.mem.span(msg_ptr));
                allocator.destroy(ctx);
                return false;
            }
        };

        const ctx = self.allocator.create(UpdateUI) catch return;
        const msg = self.allocator.dupeSentinel(u8, message, 0) catch {
            self.allocator.destroy(ctx);
            return;
        };
        ctx.* = .{
            .self = self,
            .msg = msg,
            .err = is_error,
        };
        _ = gtk.g_idle_add(&UpdateUI.update, ctx);
    }

    pub fn updateProgress(self: *StatusBar, fraction: f64) void {
        const UpdateUI = struct {
            pbar: ?*GtkProgressBar,
            val: f64,
            fn update(ptr: gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                if (ctx.val < 0) {
                    gtk.gtk_widget_set_visible(@ptrCast(ctx.pbar), false);
                } else {
                    gtk.gtk_widget_set_visible(@ptrCast(ctx.pbar), true);
                    gtk.gtk_progress_bar_set_fraction(ctx.pbar, ctx.val);
                }
                std.heap.page_allocator.destroy(ctx);
                return false;
            }
        };
        const u = std.heap.page_allocator.create(UpdateUI) catch return;
        u.* = .{ .pbar = self.progress_bar, .val = fraction };
        _ = gtk.g_idle_add(&UpdateUI.update, u);
    }

    pub fn pulseProgress(self: *StatusBar) void {
        const UpdateUI = struct {
            pbar: ?*GtkProgressBar,
            fn update(ptr: gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                gtk.gtk_widget_set_visible(@ptrCast(ctx.pbar), true);
                gtk.gtk_progress_bar_pulse(ctx.pbar);
                std.heap.page_allocator.destroy(ctx);
                return false;
            }
        };
        const u = std.heap.page_allocator.create(UpdateUI) catch return;
        u.* = .{ .pbar = self.progress_bar };
        _ = gtk.g_idle_add(&UpdateUI.update, u);
    }

    pub fn updateVoice(self: *StatusBar, voice: []const u8) void {
        const UpdateUI = struct {
            label: ?*GtkLabel,
            msg: [*:0]const u8,
            allocator: std.mem.Allocator,
            fn update(ptr: gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                const allocator = ctx.allocator;
                const label = ctx.label;
                const msg_ptr = ctx.msg;

                const text = std.fmt.allocPrintSentinel(allocator, "Voice: {s}", .{msg_ptr}, 0) catch {
                    allocator.free(std.mem.span(msg_ptr));
                    allocator.destroy(ctx);
                    return false;
                };
                
                gtk.gtk_label_set_text(@ptrCast(label), text.ptr);
                
                allocator.free(text);
                allocator.free(std.mem.span(msg_ptr));
                allocator.destroy(ctx);
                return false;
            }
        };
        const ctx = self.allocator.create(UpdateUI) catch return;
        const msg = self.allocator.dupeSentinel(u8, voice, 0) catch {
            self.allocator.destroy(ctx);
            return;
        };
        ctx.* = .{
            .label = self.voice_label,
            .msg = msg,
            .allocator = self.allocator,
        };
        _ = gtk.g_idle_add(&UpdateUI.update, ctx);
    }

    pub fn updateEngine(self: *StatusBar, engine_info: []const u8) void {
        const UpdateUI = struct {
            label: ?*GtkLabel,
            msg: [*:0]const u8,
            allocator: std.mem.Allocator,
            fn update(ptr: gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                const allocator = ctx.allocator;
                const label = ctx.label;
                const msg_ptr = ctx.msg;

                gtk.gtk_label_set_text(@ptrCast(label), msg_ptr);
                
                allocator.free(std.mem.span(msg_ptr));
                allocator.destroy(ctx);
                return false;
            }
        };
        const ctx = self.allocator.create(UpdateUI) catch return;
        const msg = self.allocator.dupeSentinel(u8, engine_info, 0) catch {
            self.allocator.destroy(ctx);
            return;
        };
        ctx.* = .{
            .label = self.engine_label,
            .msg = msg,
            .allocator = self.allocator,
        };
        _ = gtk.g_idle_add(&UpdateUI.update, ctx);
    }
};
