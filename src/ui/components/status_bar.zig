const std = @import("std");
const gtk = @import("../../gtk.zig");

const GtkWidget = gtk.GtkWidget;
const GtkLabel = gtk.GtkLabel;
const GtkBox = gtk.GtkBox;
const gpointer = gtk.gpointer;

pub const StatusBar = struct {
    box: ?*GtkWidget,
    status_label: ?*GtkLabel,
    engine_label: ?*GtkLabel,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) *StatusBar {
        const self = allocator.create(StatusBar) catch unreachable;

        const box = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 12);
        gtk.gtk_widget_add_css_class(box, "status-bar");

        const status_label = @as(?*GtkLabel, @ptrCast(gtk.gtk_label_new("System Ready")));
        gtk.gtk_label_set_xalign(status_label, 0.0);
        gtk.gtk_widget_add_css_class(@ptrCast(status_label), "status-bar-label");
        gtk.gtk_box_append(@ptrCast(box), @ptrCast(status_label));

        const spacer = gtk.gtk_box_new(gtk.GTK_ORIENTATION_HORIZONTAL, 0);
        gtk.gtk_widget_set_hexpand(spacer, true);
        gtk.gtk_box_append(@ptrCast(box), spacer);

        const engine_label = @as(?*GtkLabel, @ptrCast(gtk.gtk_label_new("Engine: Idle")));
        gtk.gtk_label_set_xalign(engine_label, 1.0);
        gtk.gtk_widget_add_css_class(@ptrCast(engine_label), "status-bar-telemetry");
        gtk.gtk_box_append(@ptrCast(box), @ptrCast(engine_label));

        self.* = .{
            .box = box,
            .status_label = status_label,
            .engine_label = engine_label,
            .allocator = allocator,
        };

        return self;
    }

    pub fn updateStatus(self: *StatusBar, message: []const u8, is_error: bool) void {
        const UpdateUI = struct {
            label: ?*GtkLabel,
            msg: [*:0]const u8,
            err: bool,
            allocator: std.mem.Allocator,
            fn update(ptr: gpointer) callconv(.c) bool {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                const color = if (ctx.err) "#f7768e" else "#7aa2f7";
                const markup = std.fmt.allocPrintSentinel(ctx.allocator, "<span foreground='{s}'>{s}</span>", .{color, ctx.msg}, 0) catch return false;
                defer ctx.allocator.free(markup);
                gtk.gtk_label_set_markup(ctx.label, markup.ptr);
                ctx.allocator.free(std.mem.span(ctx.msg));
                ctx.allocator.destroy(ctx);
                return false;
            }
        };

        const ctx = self.allocator.create(UpdateUI) catch return;
        ctx.* = .{
            .label = self.status_label,
            .msg = self.allocator.dupeZ(u8, message) catch return,
            .err = is_error,
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
                gtk.gtk_label_set_text(@ptrCast(ctx.label), ctx.msg);
                ctx.allocator.free(std.mem.span(ctx.msg));
                ctx.allocator.destroy(ctx);
                return false;
            }
        };

        const ctx = self.allocator.create(UpdateUI) catch return;
        ctx.* = .{
            .label = self.engine_label,
            .msg = self.allocator.dupeZ(u8, engine_info) catch return,
            .allocator = self.allocator,
        };
        _ = gtk.g_idle_add(&UpdateUI.update, ctx);
    }
};
