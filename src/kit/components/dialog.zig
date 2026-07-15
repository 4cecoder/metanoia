//! Reusable dialog/modal builder.
//!
//! Provides a simple API for creating standard dialog windows with a
//! title, content widget, and action buttons. Supports confirm/cancel
//! patterns and custom button configurations.

const std = @import("std");
const ffi = @import("../ffi.zig");
const Signal = @import("../signal.zig").Signal;

pub const DialogButton = struct {
    label: [*:0]const u8,
    css_class: ?[*:0]const u8 = null,
    response_id: i32 = 0,
};

pub const DialogCallbacks = struct {
    onResponse: *const fn (response_id: i32, user_data: ?*anyopaque) void,
};

pub const Dialog = struct {
    allocator: std.mem.Allocator,
    window: ?*ffi.GtkWindow,
    content_box: ?*ffi.GtkWidget,
    callbacks: DialogCallbacks,
    user_data: ?*anyopaque,

    pub fn init(
        allocator: std.mem.Allocator,
        parent: ?*ffi.GtkWindow,
        title: [*:0]const u8,
        width: i32,
        height: i32,
        callbacks: DialogCallbacks,
        user_data: ?*anyopaque,
    ) *Dialog {
        const self = allocator.create(Dialog) catch unreachable;

        const window: ?*ffi.GtkWindow = @ptrCast(ffi.gtk_window_new());
        ffi.gtk_window_set_title(window, title);
        ffi.gtk_window_set_default_size(window, width, height);
        ffi.gtk_window_set_modal(window, true);
        ffi.gtk_window_set_transient_for(window, parent);

        const root_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 0);
        ffi.gtk_widget_add_css_class(root_box, "dialog-root");
        ffi.gtk_window_set_child(window, root_box);

        self.* = .{
            .allocator = allocator,
            .window = window,
            .content_box = root_box,
            .callbacks = callbacks,
            .user_data = user_data,
        };

        return self;
    }

    pub fn deinit(self: *Dialog) void {
        self.allocator.destroy(self);
    }

    /// Get the content box for adding child widgets.
    pub fn getContentBox(self: *Dialog) ?*ffi.GtkWidget {
        return self.content_box;
    }

    /// Set the main child of the dialog's content area.
    pub fn setContent(self: *Dialog, child: ?*ffi.GtkWidget) void {
        if (self.content_box) |box| {
            ffi.gtk_box_append(@ptrCast(box), child);
        }
    }

    /// Add a row of buttons at the bottom of the dialog.
    pub fn addButtonRow(self: *Dialog, buttons: []const DialogButton) void {
        const footer = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 12);
        ffi.gtk_widget_add_css_class(footer, "dialog-footer");
        ffi.gtk_box_append(@ptrCast(self.content_box), footer);

        // Add spacer to push buttons to the right
        const spacer = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 0);
        ffi.gtk_widget_set_hexpand(spacer, true);
        ffi.gtk_box_append(@ptrCast(footer), spacer);

        for (buttons) |btn_config| {
            const btn = ffi.gtk_button_new_with_label(btn_config.label);
            if (btn_config.css_class) |cls| {
                ffi.gtk_widget_add_css_class(btn, cls);
            }

            const BtnCtx = struct {
                dialog: *Dialog,
                response_id: i32,
                fn onClick(_: ?*ffi.GtkButton, data: ffi.gpointer) callconv(.c) void {
                    const ctx: *@This() = @ptrCast(@alignCast(data));
                    ctx.dialog.callbacks.onResponse(ctx.response_id, ctx.dialog.user_data);
                }
                fn destroy(data: ffi.gpointer, _: ?*anyopaque) callconv(.c) void {
                    const ctx: *@This() = @ptrCast(@alignCast(data));
                    ctx.dialog.allocator.destroy(ctx);
                }
            };
            const ctx = self.allocator.create(BtnCtx) catch continue;
            ctx.* = .{ .dialog = self, .response_id = btn_config.response_id };
            _ = Signal.connect(btn, "clicked", @ptrCast(&BtnCtx.onClick), ctx, BtnCtx.destroy);
            ffi.gtk_box_append(@ptrCast(footer), btn);
        }
    }

    /// Add standard Cancel/OK buttons.
    pub fn addConfirmButtons(self: *Dialog) void {
        self.addButtonRow(&.{
            .{ .label = "Cancel", .css_class = "btn-secondary", .response_id = 0 },
            .{ .label = "OK", .css_class = "btn-primary", .response_id = 1 },
        });
    }

    /// Show the dialog.
    pub fn show(self: *Dialog) void {
        if (self.window) |win| {
            ffi.gtk_window_present(win);
        }
    }

    /// Close and destroy the dialog.
    pub fn close(self: *Dialog) void {
        if (self.window) |win| {
            ffi.gtk_window_destroy(win);
            self.window = null;
        }
    }

    /// Add a close-request handler that hides instead of destroying.
    pub fn handleCloseRequest(self: *Dialog) void {
        if (self.window) |win| {
            const CloseCtx = struct {
                dialog: *Dialog,
                fn onClose(_: ?*anyopaque, data: ffi.gpointer) callconv(.c) bool {
                    const ctx: *@This() = @ptrCast(@alignCast(data));
                    ctx.dialog.close();
                    return true;
                }
                fn destroy(data: ffi.gpointer, _: ?*anyopaque) callconv(.c) void {
                    const ctx: *@This() = @ptrCast(@alignCast(data));
                    ctx.dialog.allocator.destroy(ctx);
                }
            };
            const ctx = self.allocator.create(CloseCtx) catch return;
            ctx.* = .{ .dialog = self };
            _ = Signal.connect(win, "close-request", @ptrCast(&CloseCtx.onClose), ctx, CloseCtx.destroy);
        }
    }
};
