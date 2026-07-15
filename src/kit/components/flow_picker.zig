//! Reusable grid-based picker component.
//!
//! Displays a multi-step selection grid (e.g., book -> chapter -> verse).
//! The caller provides the data via `FlowPickerCallbacks`, making it
//! generic enough for any hierarchical selection (Bible navigation,
//! file browsing, category selection, etc.).

const std = @import("std");
const ffi = @import("../ffi.zig");
const Signal = @import("../signal.zig").Signal;

/// Represents one selectable item in the grid.
pub const PickerItem = struct {
    label: [*:0]const u8,
    enabled: bool = true,
    css_class: ?[*:0]const u8 = null,
};

/// Describes one level/step in the picker hierarchy.
pub const PickerLevel = struct {
    title: [*:0]const u8,
    items: []const PickerItem,
};

pub const FlowPickerCallbacks = struct {
    /// Called when the user completes all selections. The `selected`
    /// slice contains the index of the chosen item at each level.
    onSelectionComplete: *const fn (selected: []const usize) void,

    /// Optional: called when the next level needs to be built dynamically.
    /// Return the level data, or `null` to signal completion.
    /// Strings in the returned `PickerLevel` must outlive the picker (static
    /// or page-allocated). Set this when levels depend on prior selections.
    onLevelNeeded: ?*const fn (
        prev_level_idx: usize,
        prev_selection_idx: usize,
        allocator: std.mem.Allocator,
    ) ?PickerLevel = null,
};

pub const FlowPicker = struct {
    allocator: std.mem.Allocator,
    dialog: ?*ffi.GtkWindow,
    stack: ?*ffi.GtkStack,
    title_label: ?*ffi.GtkLabel,
    levels: std.ArrayListUnmanaged(PickerLevel),
    selections: std.ArrayListUnmanaged(usize),
    callbacks: FlowPickerCallbacks,

    pub fn init(allocator: std.mem.Allocator, callbacks: FlowPickerCallbacks) *FlowPicker {
        const self = allocator.create(FlowPicker) catch unreachable;
        self.* = .{
            .allocator = allocator,
            .dialog = null,
            .stack = null,
            .title_label = null,
            .levels = .empty,
            .selections = .empty,
            .callbacks = callbacks,
        };
        return self;
    }

    pub fn deinit(self: *FlowPicker) void {
        self.levels.deinit(self.allocator);
        self.selections.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Add a picker level. Levels are displayed in order; the first level
    /// is shown when `show()` is called, and subsequent levels appear after
    /// the user makes a selection in the previous one.
    pub fn addLevel(self: *FlowPicker, level: PickerLevel) void {
        self.levels.append(self.allocator, level) catch return;
    }

    /// Return the current selections. Index `i` is the chosen item at level `i`.
    pub fn getSelections(self: *const FlowPicker) []const usize {
        return self.selections.items;
    }

    /// Reset picker state, clearing all levels except the first `keep` levels.
    /// Call before `show()` to clear dynamically generated levels.
    pub fn reset(self: *FlowPicker, keep: usize) void {
        while (self.levels.items.len > keep) {
            _ = self.levels.pop();
        }
        self.selections.clearRetainingCapacity();
    }

    /// Create and display the picker dialog as a modal transient of `parent`.
    pub fn show(self: *FlowPicker, parent: ?*ffi.GtkWindow) void {
        if (self.dialog != null) return;
        self.selections.clearRetainingCapacity();

        self.dialog = @ptrCast(ffi.gtk_window_new());
        ffi.gtk_window_set_title(self.dialog, "Select");
        ffi.gtk_window_set_default_size(self.dialog, 900, 750);
        ffi.gtk_window_set_modal(self.dialog, true);
        ffi.gtk_window_set_transient_for(self.dialog, parent);

        const root_box = ffi.gtk_box_new(ffi.GTK_ORIENTATION_VERTICAL, 0);
        ffi.gtk_window_set_child(self.dialog, root_box);

        // Header with back button and title
        const header = ffi.gtk_box_new(ffi.GTK_ORIENTATION_HORIZONTAL, 15);
        ffi.gtk_widget_add_css_class(header, "nav-header");
        ffi.gtk_box_append(@ptrCast(root_box), header);

        const back_btn = ffi.gtk_button_new_with_label("Back");
        _ = Signal.connect(back_btn, "clicked", @ptrCast(&onBackClicked), self, null);
        ffi.gtk_box_append(@ptrCast(header), back_btn);

        self.title_label = @ptrCast(ffi.gtk_label_new("<b>Select</b>"));
        ffi.gtk_label_set_markup(self.title_label, "<b>Select</b>");
        ffi.gtk_box_append(@ptrCast(header), @ptrCast(self.title_label));

        self.stack = @ptrCast(ffi.gtk_stack_new());
        ffi.gtk_stack_set_transition_type(self.stack, ffi.GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT);
        ffi.gtk_widget_set_vexpand(@ptrCast(self.stack), true);
        ffi.gtk_box_append(@ptrCast(root_box), @ptrCast(self.stack));

        self.buildLevel(0);
        ffi.gtk_window_present(self.dialog);
    }

    fn buildLevel(self: *FlowPicker, level_idx: usize) void {
        if (level_idx >= self.levels.items.len) return;
        const level = self.levels.items[level_idx];

        ffi.gtk_label_set_markup(self.title_label, level.title);

        const scroll = ffi.gtk_scrolled_window_new();
        ffi.gtk_widget_set_vexpand(scroll, true);

        const flow = ffi.gtk_flow_box_new();
        ffi.gtk_flow_box_set_selection_mode(@ptrCast(flow), 0);
        ffi.gtk_flow_box_set_min_children_per_line(@ptrCast(flow), 5);
        ffi.gtk_widget_add_css_class(flow, "selection-grid");
        ffi.gtk_widget_add_css_class(flow, "compact-grid");
        ffi.gtk_scrolled_window_set_child(@ptrCast(scroll), flow);

        for (level.items, 0..) |item, item_idx| {
            const btn = ffi.gtk_button_new_with_label(item.label);
            ffi.gtk_widget_set_sensitive(btn, item.enabled);
            if (item.css_class) |cls| {
                ffi.gtk_widget_add_css_class(btn, cls);
            }

            const ClickCtx = struct {
                picker: *FlowPicker,
                level_idx: usize,
                item_idx: usize,
                fn onClick(_: ?*ffi.GtkButton, data: ffi.gpointer) callconv(.c) void {
                    const ctx: *@This() = @ptrCast(@alignCast(data));
                    ctx.picker.onItemSelected(ctx.level_idx, ctx.item_idx);
                }
                fn destroy(data: ffi.gpointer, _: ?*anyopaque) callconv(.c) void {
                    const ctx: *@This() = @ptrCast(@alignCast(data));
                    ctx.picker.allocator.destroy(ctx);
                }
            };
            const ctx = self.allocator.create(ClickCtx) catch continue;
            ctx.* = .{ .picker = self, .level_idx = level_idx, .item_idx = item_idx };
            _ = Signal.connect(btn, "clicked", @ptrCast(&ClickCtx.onClick), ctx, ClickCtx.destroy);
            ffi.gtk_flow_box_insert(@ptrCast(flow), btn, -1);
        }

        const name_buf = std.fmt.allocPrintSentinel(self.allocator, "level_{d}", .{level_idx}, 0) catch return;
        defer self.allocator.free(name_buf);

        if (ffi.gtk_stack_get_child_by_name(self.stack, name_buf)) |old| {
            ffi.gtk_stack_remove(self.stack, old);
        }
        ffi.gtk_stack_add_named(self.stack, scroll, name_buf);
        ffi.gtk_stack_set_visible_child_name(self.stack, name_buf);
    }

    fn onItemSelected(self: *FlowPicker, level_idx: usize, item_idx: usize) void {
        while (self.selections.items.len <= level_idx) {
            self.selections.append(self.allocator, 0) catch return;
        }
        self.selections.items[level_idx] = item_idx;

        const next_level = level_idx + 1;
        if (next_level < self.levels.items.len) {
            self.buildLevel(next_level);
        } else if (self.callbacks.onLevelNeeded) |needed| {
            if (needed(level_idx, item_idx, self.allocator)) |level| {
                self.levels.append(self.allocator, level) catch {};
                self.buildLevel(next_level);
            } else {
                self.callbacks.onSelectionComplete(self.selections.items);
                self.close();
            }
        } else {
            self.callbacks.onSelectionComplete(self.selections.items);
            self.close();
        }
    }

    fn onBackClicked(btn: ?*ffi.GtkButton, user_data: ffi.gpointer) callconv(.c) void {
        _ = btn;
        const self: *FlowPicker = @ptrCast(@alignCast(user_data));
        if (self.selections.items.len > 0) {
            _ = self.selections.pop();
            const prev_level = self.selections.items.len;
            // Remove dynamically generated levels
            while (self.levels.items.len > prev_level + 1) {
                _ = self.levels.pop();
            }
            if (prev_level < self.levels.items.len) {
                self.buildLevel(prev_level);
            } else {
                ffi.gtk_label_set_markup(self.title_label, self.levels.items[0].title);
            }
        }
    }

    fn close(self: *FlowPicker) void {
        if (self.dialog) |win| {
            ffi.gtk_window_destroy(win);
            self.dialog = null;
        }
    }
};
