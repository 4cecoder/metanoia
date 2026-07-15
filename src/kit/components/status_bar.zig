//! Decoupled status bar component.
//!
//! Displays status messages, a progress bar, and telemetry readouts
//! (voice, DB, engine). All updates are posted to the GLib main loop
//! via idle callbacks. No coupling to `app_state` — the caller provides
//! an allocator; all widget references live in the struct.

const std = @import("std");
const ffi = @import("../ffi.zig");
const text = @import("../util/text.zig");

pub const StatusBar = struct {
    box: ?*ffi.GtkWidget,
    status_icon: ?*ffi.GtkWidget,
    status_label: ?*ffi.GtkLabel,
    progress_bar: ?*ffi.GtkProgressBar,
    voice_label: ?*ffi.GtkLabel,
    db_label: ?*ffi.GtkLabel,
    engine_label: ?*ffi.GtkLabel,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) *StatusBar {
        const self = allocator.create(StatusBar) catch unreachable;

        const main_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 0);
        ffi.gtk_widget_add_css_class(main_box, "status-bar");

        // --- LEFT SECTION: Status & Icon ---
        const left_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 8);
        ffi.gtk_widget_add_css_class(left_box, "status-bar-left");

        const status_icon = ffi.gtk_image_new_from_icon_name("emblem-system-symbolic");
        ffi.gtk_widget_add_css_class(status_icon, "status-icon");
        ffi.gtk_box_append(@ptrCast(left_box), status_icon);

        const status_label: ?*ffi.GtkLabel = @ptrCast(ffi.gtk_label_new("System Ready"));
        ffi.gtk_label_set_xalign(status_label, 0.0);
        ffi.gtk_widget_add_css_class(@ptrCast(status_label), "status-bar-label");
        ffi.gtk_box_append(@ptrCast(left_box), @ptrCast(status_label));

        ffi.gtk_box_append(@ptrCast(main_box), left_box);

        // --- CENTER SECTION: Progress ---
        const center_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 0);
        ffi.gtk_widget_set_hexpand(center_box, true);
        ffi.gtk_widget_set_halign(center_box, ffi.GTK_ALIGN_CENTER);

        const progress_bar: ?*ffi.GtkProgressBar = @ptrCast(ffi.gtk_progress_bar_new());
        ffi.gtk_widget_set_size_request(@ptrCast(progress_bar), 200, 4);
        ffi.gtk_widget_set_valign(@ptrCast(progress_bar), ffi.GTK_ALIGN_CENTER);
        ffi.gtk_widget_set_visible(@ptrCast(progress_bar), false);
        ffi.gtk_widget_add_css_class(@ptrCast(progress_bar), "status-progress");
        ffi.gtk_box_append(@ptrCast(center_box), @ptrCast(progress_bar));

        ffi.gtk_box_append(@ptrCast(main_box), center_box);

        // --- RIGHT SECTION: Telemetry ---
        const right_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 12);
        ffi.gtk_widget_add_css_class(right_box, "status-bar-right");

        // Voice Segment
        const voice_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 4);
        const v_icon = ffi.gtk_image_new_from_icon_name("audio-input-microphone-symbolic");
        ffi.gtk_box_append(@ptrCast(voice_box), v_icon);
        const voice_label: ?*ffi.GtkLabel = @ptrCast(ffi.gtk_label_new("Voice: Default"));
        ffi.gtk_widget_add_css_class(@ptrCast(voice_label), "status-telemetry-item");
        ffi.gtk_box_append(@ptrCast(voice_box), @ptrCast(voice_label));
        ffi.gtk_box_append(@ptrCast(right_box), voice_box);

        ffi.gtk_box_append(@ptrCast(right_box), ffi.gtk_separator_new(ffi.GTK_ORIENTATION_VERTICAL));

        // DB Segment
        const db_label: ?*ffi.GtkLabel = @ptrCast(ffi.gtk_label_new("DB: Connected"));
        ffi.gtk_widget_add_css_class(@ptrCast(db_label), "status-telemetry-item");
        ffi.gtk_box_append(@ptrCast(right_box), @ptrCast(db_label));

        ffi.gtk_box_append(@ptrCast(right_box), ffi.gtk_separator_new(ffi.GTK_ORIENTATION_VERTICAL));

        // Engine Segment
        const engine_label: ?*ffi.GtkLabel = @ptrCast(ffi.gtk_label_new("Engine: Idle"));
        ffi.gtk_widget_add_css_class(@ptrCast(engine_label), "status-telemetry-item-bold");
        ffi.gtk_box_append(@ptrCast(right_box), @ptrCast(engine_label));

        ffi.gtk_box_append(@ptrCast(main_box), right_box);

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

    pub fn deinit(self: *StatusBar) void {
        self.allocator.destroy(self);
    }

    pub fn updateStatus(self: *StatusBar, message: []const u8, is_error: bool) void {
        const UpdateUI = struct {
            self_ptr: *StatusBar,
            msg: [*:0]const u8,
            err: bool,
            fn update(ptr: ffi.gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                const status_bar = ctx.self_ptr;
                const msg_ptr = ctx.msg;
                const is_err = ctx.err;

                const color = if (is_err) "#f7768e" else "#7aa2f7";
                const icon = if (is_err) "dialog-error-symbolic" else "emblem-system-symbolic";

                const escaped = text.escape(status_bar.allocator, std.mem.span(msg_ptr)) catch {
                    status_bar.allocator.free(std.mem.span(msg_ptr));
                    status_bar.allocator.destroy(ctx);
                    return false;
                };
                defer status_bar.allocator.free(escaped);

                const fmt_markup = std.fmt.allocPrintSentinel(status_bar.allocator, "<span foreground='{s}'>{s}</span>", .{ color, escaped }, 0) catch {
                    status_bar.allocator.free(escaped);
                    status_bar.allocator.free(std.mem.span(msg_ptr));
                    status_bar.allocator.destroy(ctx);
                    return false;
                };

                ffi.gtk_label_set_markup(status_bar.status_label, fmt_markup.ptr);
                ffi.gtk_image_set_from_icon_name(status_bar.status_icon, icon);

                status_bar.allocator.free(fmt_markup);
                status_bar.allocator.free(std.mem.span(msg_ptr));
                status_bar.allocator.destroy(ctx);
                return false;
            }
        };

        const ctx = self.allocator.create(UpdateUI) catch return;
        const msg = self.allocator.dupeSentinel(u8, message, 0) catch {
            self.allocator.destroy(ctx);
            return;
        };
        ctx.* = .{
            .self_ptr = self,
            .msg = msg,
            .err = is_error,
        };
        _ = ffi.g_idle_add(&UpdateUI.update, ctx);
    }

    pub fn updateProgress(self: *StatusBar, fraction: f64) void {
        const UpdateUI = struct {
            pbar: ?*ffi.GtkProgressBar,
            val: f64,
            fn update(ptr: ffi.gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                if (ctx.val < 0) {
                    ffi.gtk_widget_set_visible(@ptrCast(ctx.pbar), false);
                } else {
                    ffi.gtk_widget_set_visible(@ptrCast(ctx.pbar), true);
                    ffi.gtk_progress_bar_set_fraction(ctx.pbar, ctx.val);
                }
                std.heap.page_allocator.destroy(ctx);
                return false;
            }
        };
        const u = std.heap.page_allocator.create(UpdateUI) catch return;
        u.* = .{ .pbar = self.progress_bar, .val = fraction };
        _ = ffi.g_idle_add(&UpdateUI.update, u);
    }

    pub fn pulseProgress(self: *StatusBar) void {
        const UpdateUI = struct {
            pbar: ?*ffi.GtkProgressBar,
            fn update(ptr: ffi.gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                ffi.gtk_widget_set_visible(@ptrCast(ctx.pbar), true);
                ffi.gtk_progress_bar_pulse(ctx.pbar);
                std.heap.page_allocator.destroy(ctx);
                return false;
            }
        };
        const u = std.heap.page_allocator.create(UpdateUI) catch return;
        u.* = .{ .pbar = self.progress_bar };
        _ = ffi.g_idle_add(&UpdateUI.update, u);
    }

    pub fn updateVoice(self: *StatusBar, voice: []const u8) void {
        const UpdateUI = struct {
            label: ?*ffi.GtkLabel,
            msg: [*:0]const u8,
            allocator: std.mem.Allocator,
            fn update(ptr: ffi.gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                const text_str = std.fmt.allocPrintSentinel(ctx.allocator, "Voice: {s}", .{ctx.msg}, 0) catch {
                    ctx.allocator.free(std.mem.span(ctx.msg));
                    ctx.allocator.destroy(ctx);
                    return false;
                };

                ffi.gtk_label_set_text(@ptrCast(ctx.label), text_str.ptr);

                ctx.allocator.free(text_str);
                ctx.allocator.free(std.mem.span(ctx.msg));
                ctx.allocator.destroy(ctx);
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
        _ = ffi.g_idle_add(&UpdateUI.update, ctx);
    }

    pub fn updateEngine(self: *StatusBar, engine_info: []const u8) void {
        const UpdateUI = struct {
            label: ?*ffi.GtkLabel,
            msg: [*:0]const u8,
            allocator: std.mem.Allocator,
            fn update(ptr: ffi.gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));

                ffi.gtk_label_set_text(@ptrCast(ctx.label), ctx.msg);

                ctx.allocator.free(std.mem.span(ctx.msg));
                ctx.allocator.destroy(ctx);
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
        _ = ffi.g_idle_add(&UpdateUI.update, ctx);
    }
};
