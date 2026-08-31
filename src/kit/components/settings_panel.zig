//! Reusable settings panel builder.
//!
//! Creates a settings dialog with sections, entry fields, and action
//! buttons. All configuration data and save logic flows through callbacks,
//! keeping the component decoupled from application-specific config structs.

const std = @import("std");
const ffi = @import("../ffi.zig");
const Signal = @import("../signal.zig").Signal;

const G_CONNECT_AFTER: i32 = 1;

pub const SettingsField = struct {
    label: [*:0]const u8,
    entry_css_class: ?[*:0]const u8 = null,
    initial_value: ?[*:0]const u8 = null,
    width: i32 = -1,
};

/// A single checkbox row: label + optional helper description, rendered
/// as a GtkCheckButton. Reported back through the same string-valued
/// `SettingsFieldValue` list `onSave` already receives (value is "true" or
/// "false"), so callers don't need a second callback shape just to read
/// one boolean.
pub const SettingsCheckbox = struct {
    label: [*:0]const u8,
    description: ?[*:0]const u8 = null,
    initial_value: bool = false,
};

pub const SettingsSection = struct {
    title: [*:0]const u8,
    icon: [*:0]const u8,
    description: ?[*:0]const u8 = null,
    icon_color: ?[*:0]const u8 = null,
    fields: []const SettingsField = &.{},
    checkboxes: []const SettingsCheckbox = &.{},
    /// Escape hatch for sections that need more than label+entry rows (e.g.
    /// a status label + action button). Rendered as-is after the header/
    /// description and before `fields`. Keeps this component decoupled from
    /// any specific non-text-field UI need rather than teaching it every
    /// widget shape callers might eventually want.
    custom_content: ?*ffi.GtkWidget = null,
};

/// A single field value as returned by the save callback.
pub const SettingsFieldValue = struct {
    label: [*:0]const u8,
    value: [*:0]const u8,
};

pub const SettingsCallbacks = struct {
    /// Called when the user clicks Save. `field_values` maps each field
    /// label to its current text value. The caller owns the strings.
    onSave: *const fn (field_values: []const SettingsFieldValue) void,

    /// Called when the user clicks Restore Defaults. Return the default
    /// values for each field in the same order as the original fields.
    onRestoreDefaults: ?*const fn (defaults: []const SettingsField) void = null,
};

pub const SettingsPanel = struct {
    allocator: std.mem.Allocator,
    window: ?*ffi.GtkWindow,
    callbacks: SettingsCallbacks,
    sections: []const SettingsSection,
    entry_widgets: std.ArrayListUnmanaged(?*ffi.GtkWidget),
    checkbox_widgets: std.ArrayListUnmanaged(?*ffi.GtkWidget),

    pub fn init(
        allocator: std.mem.Allocator,
        parent: ?*ffi.GtkWindow,
        title: [*:0]const u8,
        subtitle: [*:0]const u8,
        sections: []const SettingsSection,
        callbacks: SettingsCallbacks,
    ) *SettingsPanel {
        const self = allocator.create(SettingsPanel) catch unreachable;
        self.* = .{
            .allocator = allocator,
            .window = null,
            .callbacks = callbacks,
            .sections = sections,
            .entry_widgets = .empty,
            .checkbox_widgets = .empty,
        };

        applyStyles();

        const window: ?*ffi.GtkWindow = @ptrCast(ffi.gtk_window_new());
        ffi.gtk_window_set_title(window, "Preferences");
        ffi.gtk_window_set_default_size(window, 600, 650);
        ffi.gtk_window_set_modal(window, true);
        ffi.gtk_window_set_transient_for(window, parent);
        self.window = window;

        // Auto-free SettingsPanel when GTK window is destroyed (G_CONNECT_AFTER
        // ensures our handler runs after GTK's internal cleanup).
        const DestroySelf = struct {
            fn callback(_: ?*anyopaque, data: ffi.gpointer) callconv(.c) void {
                const panel: *SettingsPanel = @ptrCast(@alignCast(data));
                panel.entry_widgets.deinit(panel.allocator);
                panel.checkbox_widgets.deinit(panel.allocator);
                panel.allocator.destroy(panel);
            }
        };
        _ = Signal.connectFlags(window, "destroy", @ptrCast(&DestroySelf.callback), self, null, G_CONNECT_AFTER);

        const root_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 0);
        ffi.gtk_widget_add_css_class(root_box, "settings-dialog-root");
        ffi.gtk_window_set_child(window, root_box);

        // Header
        const header_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 4);
        ffi.gtk_widget_add_css_class(header_box, "settings-dialog-header");
        ffi.gtk_box_append(@ptrCast(root_box), header_box);

        const title_lbl = ffi.gtk_label_new(null);
        ffi.gtk_label_set_markup(title_lbl, title);
        ffi.gtk_label_set_xalign(title_lbl, 0.0);
        ffi.gtk_box_append(@ptrCast(header_box), title_lbl);

        const sub_title = ffi.gtk_label_new(subtitle);
        ffi.gtk_widget_add_css_class(sub_title, "settings-dialog-subtitle");
        ffi.gtk_label_set_xalign(sub_title, 0.0);
        ffi.gtk_box_append(@ptrCast(header_box), sub_title);

        // Content
        const scroll = ffi.gtk_scrolled_window_new();
        ffi.gtk_widget_set_vexpand(scroll, true);
        ffi.gtk_box_append(@ptrCast(root_box), scroll);

        const content_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 24);
        ffi.gtk_widget_add_css_class(content_box, "settings-dialog-content");
        ffi.gtk_scrolled_window_set_child(@ptrCast(scroll), content_box);

        // Build sections
        for (sections) |section| {
            const section_widget = self.createSection(section);
            ffi.gtk_box_append(@ptrCast(content_box), section_widget);
        }

        // Footer
        const footer_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 12);
        ffi.gtk_widget_add_css_class(footer_box, "settings-dialog-footer");
        ffi.gtk_box_append(@ptrCast(root_box), footer_box);

        if (callbacks.onRestoreDefaults) |_| {
            const reset_btn = ffi.gtk_button_new_with_label("Restore Defaults");
            ffi.gtk_widget_add_css_class(reset_btn, "btn-ghost");
            _ = Signal.connect(reset_btn, "clicked", @ptrCast(&onResetClicked), self, null);
            ffi.gtk_box_append(@ptrCast(footer_box), reset_btn);
        }

        const spacer = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 0);
        ffi.gtk_widget_set_hexpand(spacer, true);
        ffi.gtk_box_append(@ptrCast(footer_box), spacer);

        const cancel_btn = ffi.gtk_button_new_with_label("Cancel");
        ffi.gtk_widget_add_css_class(cancel_btn, "btn-secondary");
        _ = Signal.connect(cancel_btn, "clicked", @ptrCast(&onCancelClicked), self, null);
        ffi.gtk_box_append(@ptrCast(footer_box), cancel_btn);

        const save_btn = ffi.gtk_button_new_with_label("Save Changes");
        ffi.gtk_widget_add_css_class(save_btn, "btn-primary");
        _ = Signal.connect(save_btn, "clicked", @ptrCast(&onSaveClicked), self, null);
        ffi.gtk_box_append(@ptrCast(footer_box), save_btn);

        return self;
    }

    pub fn deinit(self: *SettingsPanel) void {
        self.entry_widgets.deinit(self.allocator);
        self.checkbox_widgets.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn show(self: *SettingsPanel) void {
        if (self.window) |win| {
            ffi.gtk_window_present(win);
        }
    }

    pub fn close(self: *SettingsPanel) void {
        if (self.window) |win| {
            ffi.gtk_window_destroy(win);
            // self is freed by the destroy handler — do not touch after
        }
    }

    fn createSection(self: *SettingsPanel, section: SettingsSection) ?*ffi.GtkWidget {
        const sec_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 12);
        ffi.gtk_widget_add_css_class(sec_box, "card-section");

        // Section header with icon
        const label_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 8);
        ffi.gtk_box_append(@ptrCast(sec_box), label_box);

        const icon = ffi.gtk_label_new(section.icon);
        ffi.gtk_box_append(@ptrCast(label_box), icon);

        const title = ffi.gtk_label_new(null);
        const title_markup = std.fmt.allocPrintSentinel(
            self.allocator,
            "<span weight='bold' size='large' foreground='{s}'>{s}</span>",
            .{ section.icon_color orelse "#7aa2f7", section.title },
            0,
        ) catch "Section";
        defer self.allocator.free(title_markup);
        ffi.gtk_label_set_markup(title, title_markup);
        ffi.gtk_box_append(@ptrCast(label_box), title);

        if (section.description) |desc| {
            const desc_lbl = ffi.gtk_label_new(desc);
            ffi.gtk_widget_add_css_class(desc_lbl, "text-dim");
            ffi.gtk_label_set_xalign(desc_lbl, 0.0);
            ffi.gtk_box_append(@ptrCast(sec_box), desc_lbl);
        }

        if (section.custom_content) |content| {
            ffi.gtk_box_append(@ptrCast(sec_box), content);
        }

        // Fields
        for (section.fields) |field| {
            const row = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 12);
            ffi.gtk_box_append(@ptrCast(sec_box), row);

            const lbl = ffi.gtk_label_new(field.label);
            ffi.gtk_widget_set_hexpand(lbl, true);
            ffi.gtk_label_set_xalign(lbl, 0.0);
            ffi.gtk_box_append(@ptrCast(row), lbl);

            const entry = ffi.gtk_entry_new();
            ffi.gtk_widget_add_css_class(entry, field.entry_css_class orelse "modern-entry");
            if (field.initial_value) |val| {
                ffi.gtk_editable_set_text(entry, val);
            }
            ffi.gtk_box_append(@ptrCast(row), entry);
            self.entry_widgets.append(self.allocator, entry) catch {};
        }

        // Checkboxes
        for (section.checkboxes) |checkbox| {
            const row = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 2);
            ffi.gtk_box_append(@ptrCast(sec_box), row);

            const check = ffi.gtk_check_button_new();
            ffi.gtk_check_button_set_label(check, checkbox.label);
            ffi.gtk_check_button_set_active(check, checkbox.initial_value);
            ffi.gtk_box_append(@ptrCast(row), check);

            if (checkbox.description) |desc| {
                const desc_lbl = ffi.gtk_label_new(desc);
                ffi.gtk_widget_add_css_class(desc_lbl, "text-dim");
                ffi.gtk_label_set_xalign(desc_lbl, 0.0);
                ffi.gtk_box_append(@ptrCast(row), desc_lbl);
            }
            self.checkbox_widgets.append(self.allocator, check) catch {};
        }

        return sec_box;
    }

    fn gatherValues(self: *SettingsPanel) []const SettingsFieldValue {
        var values = std.ArrayListUnmanaged(SettingsFieldValue).empty;
        var field_idx: usize = 0;
        var checkbox_idx: usize = 0;
        for (self.sections) |section| {
            for (section.fields) |field| {
                if (field_idx < self.entry_widgets.items.len) {
                    if (self.entry_widgets.items[field_idx]) |entry| {
                        const val = ffi.gtk_editable_get_text(entry);
                        values.append(self.allocator, .{ .label = field.label, .value = val }) catch {};
                    }
                }
                field_idx += 1;
            }
            for (section.checkboxes) |checkbox| {
                if (checkbox_idx < self.checkbox_widgets.items.len) {
                    if (self.checkbox_widgets.items[checkbox_idx]) |check| {
                        const active = ffi.gtk_check_button_get_active(check);
                        values.append(self.allocator, .{ .label = checkbox.label, .value = if (active) "true" else "false" }) catch {};
                    }
                }
                checkbox_idx += 1;
            }
        }
        return values.toOwnedSlice(self.allocator) catch &.{};
    }

    fn onCancelClicked(btn: ?*ffi.GtkButton, user_data: ffi.gpointer) callconv(.c) void {
        _ = btn;
        const self: *SettingsPanel = @ptrCast(@alignCast(user_data));
        self.close();
    }

    fn onSaveClicked(btn: ?*ffi.GtkButton, user_data: ffi.gpointer) callconv(.c) void {
        _ = btn;
        const self: *SettingsPanel = @ptrCast(@alignCast(user_data));
        const alloc = self.allocator;
        const values = self.gatherValues();
        defer alloc.free(values);
        self.callbacks.onSave(values);
        self.close();
    }

    fn onResetClicked(btn: ?*ffi.GtkButton, user_data: ffi.gpointer) callconv(.c) void {
        _ = btn;
        const self: *SettingsPanel = @ptrCast(@alignCast(user_data));
        if (self.callbacks.onRestoreDefaults) |restore_fn| {
            // Collect all original field values
            var defaults = std.ArrayListUnmanaged(SettingsField).empty;
            for (self.sections) |section| {
                for (section.fields) |field| {
                    defaults.append(self.allocator, field) catch {};
                }
            }
            const defaults_slice = defaults.toOwnedSlice(self.allocator) catch return;
            defer self.allocator.free(defaults_slice);
            restore_fn(defaults_slice);
        }
    }
};

fn applyStyles() void {
    const css =
        \\.settings-dialog-root { background-color: #1a1b26; color: #c0caf5; }
        \\.settings-dialog-header { padding: 32px; background-color: rgba(255,255,255,0.02); border-bottom: 1px solid rgba(255,255,255,0.05); }
        \\.settings-dialog-subtitle { color: #565f89; font-size: 13px; margin-top: 4px; }
        \\.settings-dialog-content { padding: 32px; }
        \\.settings-dialog-footer { padding: 24px 32px; background-color: rgba(0,0,0,0.2); border-top: 1px solid rgba(255,255,255,0.05); }
        \\
        \\.card-section { 
        \\  background-color: rgba(255,255,255,0.03); 
        \\  border: 1px solid rgba(255,255,255,0.08); 
        \\  border-radius: 12px; 
        \\  padding: 20px; 
        \\}
        \\
        \\.modern-entry { 
        \\  background-color: #16161e; 
        \\  color: #c0caf5; 
        \\  border: 1px solid #414868; 
        \\  border-radius: 8px; 
        \\  padding: 8px 12px; 
        \\}
        \\.modern-entry:focus { border-color: #7aa2f7; box-shadow: 0 0 0 2px rgba(122,162,247,0.2); }
        \\
        \\.text-dim { color: #565f89; font-size: 12px; }
        \\
        \\.btn-primary { 
        \\  background-color: #7aa2f7; 
        \\  color: #1a1b26; 
        \\  font-weight: bold; 
        \\  border-radius: 8px; 
        \\  padding: 10px 24px; 
        \\}
        \\.btn-primary:hover { background-color: #89ddff; }
        \\
        \\.btn-secondary { 
        \\  background-color: #2f334d; 
        \\  color: #c0caf5; 
        \\  border-radius: 8px; 
        \\  padding: 10px 24px; 
        \\}
        \\.btn-secondary:hover { background-color: #414868; }
        \\
        \\.btn-ghost { 
        \\  background: none; 
        \\  color: #565f89; 
        \\  padding: 8px 16px; 
        \\}
        \\.btn-ghost:hover { color: #f7768e; }
    ;

    const provider = ffi.gtk_css_provider_new();
    ffi.gtk_css_provider_load_from_data(provider, css, -1);
    const display = ffi.gdk_display_get_default();
    ffi.gtk_style_context_add_provider_for_display(display, provider, ffi.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
}

test "SettingsField defaults" {
    const field = SettingsField{
        .label = "Test",
        .entry_css_class = null,
        .initial_value = null,
        .width = -1,
    };
    try std.testing.expectEqualStrings("Test", field.label);
    try std.testing.expect(field.entry_css_class == null);
    try std.testing.expect(field.initial_value == null);
    try std.testing.expectEqual(@as(i32, -1), field.width);
}
