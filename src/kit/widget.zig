//! Type-safe wrappers around raw GTK4 widget FFI types.
//!
//! Each wrapper holds a nullable pointer to the underlying GTK widget and
//! exposes only the operations relevant to that widget kind, providing a
//! more ergonomic API than raw FFI calls.

const ffi = @import("ffi.zig");

// ──────────────── Widget (base) ────────────────

pub const Widget = struct {
    ptr: ?*ffi.GtkWidget,

    pub fn wrap(ptr: ?*ffi.GtkWidget) Widget {
        return .{ .ptr = ptr };
    }

    pub fn setVisible(self: Widget, visible: bool) void {
        ffi.gtk_widget_set_visible(self.ptr, visible);
    }

    pub fn getVisible(self: Widget) bool {
        return ffi.gtk_widget_get_visible(self.ptr);
    }

    pub fn setVexpand(self: Widget, expand: bool) void {
        ffi.gtk_widget_set_vexpand(self.ptr, expand);
    }

    pub fn setHexpand(self: Widget, expand: bool) void {
        ffi.gtk_widget_set_hexpand(self.ptr, expand);
    }

    pub fn setSensitive(self: Widget, sensitive: bool) void {
        ffi.gtk_widget_set_sensitive(self.ptr, sensitive);
    }

    pub fn setSizeRequest(self: Widget, width: i32, height: i32) void {
        ffi.gtk_widget_set_size_request(self.ptr, width, height);
    }

    pub fn setHalign(self: Widget, alignment: i32) void {
        ffi.gtk_widget_set_halign(self.ptr, alignment);
    }

    pub fn setValign(self: Widget, alignment: i32) void {
        ffi.gtk_widget_set_valign(self.ptr, alignment);
    }

    pub fn addCssClass(self: Widget, css_class: [*:0]const u8) void {
        ffi.gtk_widget_add_css_class(self.ptr, css_class);
    }

    pub fn removeCssClass(self: Widget, css_class: [*:0]const u8) void {
        ffi.gtk_widget_remove_css_class(self.ptr, css_class);
    }

    pub fn grabFocus(self: Widget) bool {
        return ffi.gtk_widget_grab_focus(self.ptr);
    }

    pub fn setDirection(self: Widget, dir: i32) void {
        ffi.gtk_widget_set_direction(self.ptr, dir);
    }

    pub fn getFirstChild(self: Widget) ?*ffi.GtkWidget {
        return ffi.gtk_widget_get_first_child(self.ptr);
    }

    pub fn getNextSibling(self: Widget) ?*ffi.GtkWidget {
        return ffi.gtk_widget_get_next_sibling(self.ptr);
    }

    pub fn getParent(self: Widget) ?*ffi.GtkWidget {
        return ffi.gtk_widget_get_parent(self.ptr);
    }

    pub fn setName(self: Widget, name: [*:0]const u8) void {
        ffi.gtk_widget_set_name(self.ptr, name);
    }

    pub fn addController(self: Widget, controller: ?*anyopaque) void {
        ffi.gtk_widget_add_controller(self.ptr, controller);
    }

    pub fn signalConnect(self: Widget, signal: [*:0]const u8, handler: ?*const anyopaque, data: ffi.gpointer, flags: i32) u64 {
        return ffi.g_signal_connect_data(self.ptr, signal, handler, data, null, flags);
    }
};

// ──────────────── Window ────────────────

pub const Window = struct {
    ptr: ?*ffi.GtkWindow,

    pub fn new() Window {
        return .{ .ptr = @ptrCast(ffi.gtk_window_new()) };
    }

    pub fn wrap(ptr: ?*ffi.GtkWindow) Window {
        return .{ .ptr = ptr };
    }

    pub fn widget(self: Window) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn setTitle(self: Window, title: [*:0]const u8) void {
        ffi.gtk_window_set_title(self.ptr, title);
    }

    pub fn setDefaultSize(self: Window, width: i32, height: i32) void {
        ffi.gtk_window_set_default_size(self.ptr, width, height);
    }

    pub fn present(self: Window) void {
        ffi.gtk_window_present(self.ptr);
    }

    pub fn isActive(self: Window) bool {
        return ffi.gtk_window_is_active(self.ptr);
    }

    pub fn setChild(self: Window, child: ?*ffi.GtkWidget) void {
        ffi.gtk_window_set_child(self.ptr, child);
    }

    pub fn setModal(self: Window, modal: bool) void {
        ffi.gtk_window_set_modal(self.ptr, modal);
    }

    pub fn setTransientFor(self: Window, parent: ?*ffi.GtkWindow) void {
        ffi.gtk_window_set_transient_for(self.ptr, parent);
    }

    pub fn destroy(self: Window) void {
        ffi.gtk_window_destroy(self.ptr);
    }

    pub fn setDecorated(self: Window, setting: bool) void {
        ffi.gtk_window_set_decorated(self.ptr, setting);
    }

    pub fn setResizable(self: Window, resizable: bool) void {
        ffi.gtk_window_set_resizable(self.ptr, resizable);
    }

    pub fn close(self: Window) void {
        ffi.gtk_window_close(self.ptr);
    }
};

// ──────────────── Box ────────────────

pub const Box = struct {
    ptr: ?*ffi.GtkBox,

    pub fn new(orientation: i32, spacing: i32) Box {
        return .{ .ptr = @ptrCast(ffi.gtk_box_new(orientation, spacing)) };
    }

    pub fn vertical(spacing: i32) Box {
        return new(ffi.GTK_ORIENTATION_VERTICAL, spacing);
    }

    pub fn horizontal(spacing: i32) Box {
        return new(ffi.GTK_ORIENTATION_HORIZONTAL, spacing);
    }

    pub fn widget(self: Box) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn append(self: Box, child: ?*ffi.GtkWidget) void {
        ffi.gtk_box_append(self.ptr, child);
    }

    pub fn remove(self: Box, child: ?*ffi.GtkWidget) void {
        ffi.gtk_box_remove(self.ptr, child);
    }
};

// ──────────────── Label ────────────────

pub const Label = struct {
    ptr: ?*ffi.GtkLabel,

    pub fn new(str: ?[*:0]const u8) Label {
        return .{ .ptr = @ptrCast(ffi.gtk_label_new(str)) };
    }

    pub fn wrap(ptr: ?*ffi.GtkLabel) Label {
        return .{ .ptr = ptr };
    }

    pub fn widget(self: Label) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn setText(self: Label, str: [*:0]const u8) void {
        ffi.gtk_label_set_text(self.ptr, str);
    }

    pub fn setMarkup(self: Label, str: [*:0]const u8) void {
        ffi.gtk_label_set_markup(self.ptr, str);
    }

    pub fn setWrap(self: Label, setting: bool) void {
        ffi.gtk_label_set_wrap(self.ptr, setting);
    }

    pub fn setXalign(self: Label, xalign: f32) void {
        ffi.gtk_label_set_xalign(self.ptr, xalign);
    }
};

// ──────────────── Button ────────────────

pub const Button = struct {
    ptr: ?*ffi.GtkButton,

    pub fn newWithLabel(label: [*:0]const u8) Button {
        return .{ .ptr = @ptrCast(ffi.gtk_button_new_with_label(label)) };
    }

    pub fn widget(self: Button) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn setLabel(self: Button, label: [*:0]const u8) void {
        ffi.gtk_button_set_label(self.ptr, label);
    }

    pub fn setChild(self: Button, child: ?*ffi.GtkWidget) void {
        ffi.gtk_button_set_child(self.ptr, child);
    }

    pub fn signalConnectClicked(self: Button, handler: ?*const anyopaque, data: ffi.gpointer) u64 {
        return ffi.g_signal_connect_data(self.ptr, "clicked", handler, data, null, 0);
    }
};

// ──────────────── ScrolledWindow ────────────────

pub const ScrolledWindow = struct {
    ptr: ?*ffi.GtkScrolledWindow,

    pub fn new() ScrolledWindow {
        return .{ .ptr = @ptrCast(ffi.gtk_scrolled_window_new()) };
    }

    pub fn widget(self: ScrolledWindow) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn setChild(self: ScrolledWindow, child: ?*ffi.GtkWidget) void {
        ffi.gtk_scrolled_window_set_child(self.ptr, child);
    }

    pub fn getVadjustment(self: ScrolledWindow) ?*ffi.GtkAdjustment {
        return ffi.gtk_scrolled_window_get_vadjustment(self.ptr);
    }
};

// ──────────────── ProgressBar ────────────────

pub const ProgressBar = struct {
    ptr: ?*ffi.GtkProgressBar,

    pub fn new() ProgressBar {
        return .{ .ptr = @ptrCast(ffi.gtk_progress_bar_new()) };
    }

    pub fn widget(self: ProgressBar) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn setFraction(self: ProgressBar, fraction: f64) void {
        ffi.gtk_progress_bar_set_fraction(self.ptr, fraction);
    }

    pub fn pulse(self: ProgressBar) void {
        ffi.gtk_progress_bar_pulse(self.ptr);
    }
};

// ──────────────── Separator ────────────────

pub const Separator = struct {
    ptr: ?*ffi.GtkSeparator,

    pub fn new(orientation: i32) Separator {
        return .{ .ptr = @ptrCast(ffi.gtk_separator_new(orientation)) };
    }

    pub fn vertical() Separator {
        return new(ffi.GTK_ORIENTATION_VERTICAL);
    }

    pub fn horizontal() Separator {
        return new(ffi.GTK_ORIENTATION_HORIZONTAL);
    }

    pub fn widget(self: Separator) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }
};

// ──────────────── Image ────────────────

pub const Image = struct {
    ptr: ?*ffi.GtkWidget,

    pub fn newFromIconName(icon_name: [*:0]const u8) Image {
        return .{ .ptr = ffi.gtk_image_new_from_icon_name(icon_name) };
    }

    pub fn widget(self: Image) Widget {
        return .{ .ptr = self.ptr };
    }

    pub fn setFromIconName(self: Image, icon_name: [*:0]const u8) void {
        ffi.gtk_image_set_from_icon_name(self.ptr, icon_name);
    }
};

// ──────────────── Spinner ────────────────

pub const Spinner = struct {
    ptr: ?*ffi.GtkWidget,

    pub fn new() Spinner {
        return .{ .ptr = ffi.gtk_spinner_new() };
    }

    pub fn widget(self: Spinner) Widget {
        return .{ .ptr = self.ptr };
    }

    pub fn start(self: Spinner) void {
        ffi.gtk_spinner_start(@ptrCast(self.ptr));
    }

    pub fn stop(self: Spinner) void {
        ffi.gtk_spinner_stop(@ptrCast(self.ptr));
    }
};

// ──────────────── FlowBox ────────────────

pub const FlowBox = struct {
    ptr: ?*ffi.GtkFlowBox,

    pub fn new() FlowBox {
        return .{ .ptr = @ptrCast(ffi.gtk_flow_box_new()) };
    }

    pub fn widget(self: FlowBox) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn insert(self: FlowBox, child: ?*ffi.GtkWidget, position: i32) void {
        ffi.gtk_flow_box_insert(self.ptr, child, position);
    }

    pub fn setSelectionMode(self: FlowBox, mode: i32) void {
        ffi.gtk_flow_box_set_selection_mode(self.ptr, mode);
    }

    pub fn setMinChildrenPerLine(self: FlowBox, n: u32) void {
        ffi.gtk_flow_box_set_min_children_per_line(self.ptr, n);
    }

    pub fn setMaxChildrenPerLine(self: FlowBox, n: u32) void {
        ffi.gtk_flow_box_set_max_children_per_line(self.ptr, n);
    }
};

// ──────────────── Stack ────────────────

pub const Stack = struct {
    ptr: ?*ffi.GtkStack,

    pub fn new() Stack {
        return .{ .ptr = @ptrCast(ffi.gtk_stack_new()) };
    }

    pub fn widget(self: Stack) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn addNamed(self: Stack, child: ?*ffi.GtkWidget, name: [*:0]const u8) void {
        ffi.gtk_stack_add_named(self.ptr, child, name);
    }

    pub fn setVisibleChildName(self: Stack, name: [*:0]const u8) void {
        ffi.gtk_stack_set_visible_child_name(self.ptr, name);
    }

    pub fn getVisibleChildName(self: Stack) ?[*:0]const u8 {
        return ffi.gtk_stack_get_visible_child_name(self.ptr);
    }

    pub fn remove(self: Stack, child: ?*ffi.GtkWidget) void {
        ffi.gtk_stack_remove(self.ptr, child);
    }

    pub fn getChildByName(self: Stack, name: [*:0]const u8) ?*ffi.GtkWidget {
        return ffi.gtk_stack_get_child_by_name(self.ptr, name);
    }

    pub fn setTransitionType(self: Stack, transition: i32) void {
        ffi.gtk_stack_set_transition_type(self.ptr, transition);
    }
};

// ──────────────── Expander ────────────────

pub const Expander = struct {
    ptr: ?*ffi.GtkExpander,

    pub fn new(label: ?[*:0]const u8) Expander {
        return .{ .ptr = @ptrCast(ffi.gtk_expander_new(label)) };
    }

    pub fn widget(self: Expander) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn setChild(self: Expander, child: ?*ffi.GtkWidget) void {
        ffi.gtk_expander_set_child(self.ptr, child);
    }

    pub fn setExpanded(self: Expander, expanded: bool) void {
        ffi.gtk_expander_set_expanded(self.ptr, expanded);
    }
};

// ──────────────── Paned ────────────────

pub const Paned = struct {
    ptr: ?*ffi.GtkPaned,

    pub fn new(orientation: i32) Paned {
        return .{ .ptr = @ptrCast(ffi.gtk_paned_new(orientation)) };
    }

    pub fn widget(self: Paned) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn setStartChild(self: Paned, child: ?*ffi.GtkWidget) void {
        ffi.gtk_paned_set_start_child(self.ptr, child);
    }

    pub fn setEndChild(self: Paned, child: ?*ffi.GtkWidget) void {
        ffi.gtk_paned_set_end_child(self.ptr, child);
    }

    pub fn setPosition(self: Paned, position: i32) void {
        ffi.gtk_paned_set_position(self.ptr, position);
    }

    pub fn getPosition(self: Paned) i32 {
        return ffi.gtk_paned_get_position(self.ptr);
    }
};

// ──────────────── ListBox ────────────────

pub const ListBox = struct {
    ptr: ?*anyopaque,

    pub fn new() ListBox {
        return .{ .ptr = ffi.gtk_list_box_new() };
    }

    pub fn widget(self: ListBox) Widget {
        return .{ .ptr = @ptrCast(self.ptr) };
    }

    pub fn append(self: ListBox, child: ?*ffi.GtkWidget) void {
        ffi.gtk_list_box_append(self.ptr, child);
    }

    pub fn removeAll(self: ListBox) void {
        ffi.gtk_list_box_remove_all(self.ptr);
    }

    pub fn setSelectionMode(self: ListBox, mode: i32) void {
        ffi.gtk_list_box_set_selection_mode(self.ptr, mode);
    }
};

// ──────────────── Search Entry ────────────────

pub const SearchEntry = struct {
    ptr: ?*ffi.GtkWidget,

    pub fn new() SearchEntry {
        return .{ .ptr = ffi.gtk_search_entry_new() };
    }

    pub fn widget(self: SearchEntry) Widget {
        return .{ .ptr = self.ptr };
    }

    pub fn setKeyCaptureWidget(self: SearchEntry, target: ?*ffi.GtkWidget) void {
        ffi.gtk_search_entry_set_key_capture_widget(self.ptr, target);
    }
};

// ──────────────── Entry ────────────────

pub const Entry = struct {
    ptr: ?*ffi.GtkWidget,

    pub fn new() Entry {
        return .{ .ptr = ffi.gtk_entry_new() };
    }

    pub fn widget(self: Entry) Widget {
        return .{ .ptr = self.ptr };
    }

    pub fn getText(self: Entry) [*:0]const u8 {
        return ffi.gtk_editable_get_text(self.ptr);
    }

    pub fn setText(self: Entry, text: [*:0]const u8) void {
        ffi.gtk_editable_set_text(self.ptr, text);
    }
};

// ──────────────── DropDown ────────────────

pub const DropDown = struct {
    ptr: ?*ffi.GtkWidget,

    pub fn newFromStrings(strings: [*]const ?[*:0]const u8) DropDown {
        return .{ .ptr = ffi.gtk_drop_down_new_from_strings(strings) };
    }

    pub fn widget(self: DropDown) Widget {
        return .{ .ptr = self.ptr };
    }

    pub fn getSelected(self: DropDown) u32 {
        return ffi.gtk_drop_down_get_selected(self.ptr);
    }

    pub fn setSelected(self: DropDown, position: u32) void {
        ffi.gtk_drop_down_set_selected(self.ptr, position);
    }
};

// ──────────────── TextView ────────────────

pub const TextView = struct {
    ptr: ?*ffi.GtkWidget,

    pub fn new() TextView {
        return .{ .ptr = ffi.gtk_text_view_new() };
    }

    pub fn widget(self: TextView) Widget {
        return .{ .ptr = self.ptr };
    }

    pub fn getBuffer(self: TextView) ?*anyopaque {
        return ffi.gtk_text_view_get_buffer(self.ptr);
    }

    pub fn setEditable(self: TextView, setting: bool) void {
        ffi.gtk_text_view_set_editable(self.ptr, setting);
    }

    pub fn setCursorVisible(self: TextView, setting: bool) void {
        ffi.gtk_text_view_set_cursor_visible(self.ptr, setting);
    }
};

// ──────────────── EventControllerKey ────────────────

pub const EventControllerKey = struct {
    ptr: ?*anyopaque,

    pub fn new() EventControllerKey {
        return .{ .ptr = ffi.gtk_event_controller_key_new() };
    }

    pub fn signalKeyPressed(self: EventControllerKey, handler: ?*const anyopaque, data: ffi.gpointer) u64 {
        return ffi.g_signal_connect_data(self.ptr, "key-pressed", handler, data, null, 0);
    }
};
