const std = @import("std");

pub const gpointer = ?*anyopaque;
pub const GtkApplication = anyopaque;
pub const GApplication = anyopaque;
pub const GtkWindow = anyopaque;
pub const GtkWidget = anyopaque;
pub const GtkBox = anyopaque;
pub const GtkPaned = anyopaque;
pub const GtkLabel = anyopaque;
pub const GtkScrolledWindow = anyopaque;
pub const GtkCssProvider = anyopaque;
pub const GdkDisplay = anyopaque;
pub const GtkButton = anyopaque;
pub const GtkNotebook = anyopaque;
pub const GtkFlowBox = anyopaque;
pub const GtkStack = anyopaque;
pub const GtkAdjustment = anyopaque;
pub const GtkExpander = anyopaque;

pub const GTK_ORIENTATION_HORIZONTAL = 0;
pub const GTK_ORIENTATION_VERTICAL = 1;
pub const GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = 600;
pub const GTK_STYLE_PROVIDER_PRIORITY_USER = 800;

pub const GTK_TEXT_DIR_LTR = 1;
pub const GTK_TEXT_DIR_RTL = 2;

pub const GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT = 7;

pub const GTK_ALIGN_FILL = 0;
pub const GTK_ALIGN_START = 1;
pub const GTK_ALIGN_END = 2;
pub const GTK_ALIGN_CENTER = 3;
pub const GTK_ALIGN_BASELINE = 4;

// Standard GTK/GLib Exports
pub extern fn gtk_application_new(application_id: ?[*:0]const u8, flags: i32) ?*GtkApplication;
pub extern fn g_application_run(application: ?*GApplication, argc: i32, argv: ?[*]?[*:0]u8) i32;
pub extern fn g_object_unref(object: gpointer) void;
pub extern fn g_main_context_iteration(context: ?*anyopaque, may_block: bool) bool;
pub extern fn gtk_application_window_new(application: ?*GtkApplication) ?*GtkWidget;
pub extern fn gtk_window_new() ?*GtkWidget;
pub extern fn gtk_window_set_title(window: ?*GtkWindow, title: [*:0]const u8) void;
pub extern fn gtk_window_set_default_size(window: ?*GtkWindow, width: i32, height: i32) void;
pub extern fn gtk_window_present(window: ?*GtkWindow) void;
pub extern fn gtk_window_is_active(window: ?*GtkWindow) bool;
pub extern fn gtk_window_set_child(window: ?*GtkWindow, child: ?*GtkWidget) void;
pub extern fn gtk_window_set_modal(window: ?*GtkWindow, modal: bool) void;
pub extern fn gtk_window_set_transient_for(window: ?*GtkWindow, parent: ?*GtkWindow) void;
pub extern fn gtk_window_destroy(window: ?*GtkWindow) void;
pub extern fn gtk_window_set_decorated(window: ?*GtkWindow, setting: bool) void;
pub extern fn gtk_window_set_resizable(window: ?*GtkWindow, resizable: bool) void;
pub extern fn gtk_window_close(window: ?*GtkWindow) void;

pub extern fn g_signal_connect_data(instance: gpointer, detailed_signal: [*:0]const u8, c_handler: ?*const anyopaque, data: gpointer, destroy_data: ?*const anyopaque, connect_flags: i32) u64;
pub extern fn g_signal_emit_by_name(instance: gpointer, detailed_signal: [*:0]const u8, ...) void;

pub extern fn gtk_box_new(orientation: i32, spacing: i32) ?*GtkWidget;
pub extern fn gtk_box_append(box: ?*GtkBox, child: ?*GtkWidget) void;
pub extern fn gtk_box_remove(box: ?*GtkBox, child: ?*GtkWidget) void;
pub extern fn gtk_widget_get_first_child(widget: ?*GtkWidget) ?*GtkWidget;
pub extern fn gtk_widget_get_next_sibling(widget: ?*GtkWidget) ?*GtkWidget;
pub extern fn gtk_widget_get_parent(widget: ?*GtkWidget) ?*GtkWidget;
pub extern fn gtk_widget_set_parent(widget: ?*anyopaque, parent: ?*GtkWidget) void;
pub extern fn gtk_widget_unparent(widget: ?*GtkWidget) void;

pub extern fn gtk_paned_new(orientation: i32) ?*GtkWidget;
pub extern fn gtk_paned_set_start_child(paned: ?*GtkPaned, child: ?*GtkWidget) void;
pub extern fn gtk_paned_set_end_child(paned: ?*GtkPaned, child: ?*GtkWidget) void;
pub extern fn gtk_paned_set_position(paned: ?*GtkPaned, position: i32) void;
pub extern fn gtk_paned_get_position(paned: ?*GtkPaned) i32;

pub extern fn gtk_label_new(str: ?[*:0]const u8) ?*GtkWidget;
pub extern fn gtk_label_set_markup(label: ?*GtkLabel, str: [*:0]const u8) void;
pub extern fn gtk_label_set_wrap(label: ?*GtkLabel, setting: bool) void;
pub extern fn gtk_label_set_xalign(label: ?*GtkLabel, xalign: f32) void;

pub extern fn gtk_scrolled_window_new() ?*GtkWidget;
pub extern fn gtk_scrolled_window_set_child(sw: ?*GtkScrolledWindow, child: ?*GtkWidget) void;
pub extern fn gtk_scrolled_window_get_vadjustment(sw: ?*GtkScrolledWindow) ?*GtkAdjustment;
pub extern fn gtk_adjustment_set_value(adj: ?*GtkAdjustment, value: f64) void;
pub extern fn gtk_adjustment_get_value(adj: ?*GtkAdjustment) f64;

pub extern fn gtk_widget_set_vexpand(widget: ?*GtkWidget, expand: bool) void;
pub extern fn gtk_widget_set_hexpand(widget: ?*GtkWidget, expand: bool) void;
pub extern fn gtk_widget_set_sensitive(widget: ?*GtkWidget, sensitive: bool) void;
pub extern fn gtk_widget_set_visible(widget: ?*GtkWidget, visible: bool) void;
pub extern fn gtk_widget_get_visible(widget: ?*GtkWidget) bool;
pub extern fn gtk_widget_set_direction(widget: ?*GtkWidget, dir: i32) void;
pub extern fn gtk_widget_set_name(widget: ?*GtkWidget, name: [*:0]const u8) void;
pub extern fn gtk_widget_set_size_request(widget: ?*GtkWidget, width: i32, height: i32) void;
pub extern fn gtk_widget_grab_focus(widget: ?*GtkWidget) bool;

pub extern fn gtk_css_provider_new() ?*GtkCssProvider;
pub extern fn gtk_css_provider_load_from_path(provider: ?*GtkCssProvider, path: [*:0]const u8) void;
pub extern fn gtk_css_provider_load_from_data(provider: ?*GtkCssProvider, data: [*:0]const u8, length: isize) void;
pub extern fn gdk_display_get_default() ?*GdkDisplay;
pub extern fn gtk_style_context_add_provider_for_display(display: ?*GdkDisplay, provider: ?*anyopaque, priority: u32) void;
pub extern fn gtk_widget_add_css_class(widget: ?*GtkWidget, css_class: [*:0]const u8) void;
pub extern fn gtk_widget_remove_css_class(widget: ?*GtkWidget, css_class: [*:0]const u8) void;
pub extern fn gtk_widget_add_controller(widget: ?*GtkWidget, controller: ?*anyopaque) void;

pub extern fn g_timeout_add(interval: u32, function: ?*const fn (data: gpointer) callconv(.c) bool, data: gpointer) u32;

pub extern fn gtk_drop_down_new_from_strings(strings: [*]const ?[*:0]const u8) ?*GtkWidget;
pub extern fn gtk_drop_down_get_selected(self: ?*anyopaque) u32;
pub extern fn gtk_drop_down_set_selected(self: ?*anyopaque, position: u32) void;

pub extern fn gtk_gesture_click_new() ?*anyopaque;
pub extern fn gtk_gesture_single_set_button(gesture: ?*anyopaque, button: u32) void;
pub extern fn gtk_gesture_long_press_new() ?*anyopaque;

pub extern fn gtk_text_view_new() ?*GtkWidget;
pub extern fn gtk_text_view_get_buffer(text_view: ?*anyopaque) ?*anyopaque;
pub extern fn gtk_text_view_set_editable(text_view: ?*anyopaque, setting: bool) void;
pub extern fn gtk_text_view_set_cursor_visible(text_view: ?*anyopaque, setting: bool) void;
pub extern fn gtk_text_view_scroll_to_iter(text_view: ?*anyopaque, iter: *anyopaque, within_margin: f64, use_align: bool, xalign: f64, yalign: f64) void;

pub extern fn gtk_text_buffer_set_text(buffer: ?*anyopaque, text: [*:0]const u8, len: i32) void;
pub extern fn gtk_text_buffer_insert(buffer: ?*anyopaque, iter: *anyopaque, text: [*:0]const u8, len: i32) void;
pub extern fn gtk_text_buffer_get_start_iter(buffer: ?*anyopaque, iter: *anyopaque) void;
pub extern fn gtk_text_buffer_get_end_iter(buffer: ?*anyopaque, iter: *anyopaque) void;
pub extern fn gtk_text_buffer_get_text(buffer: ?*anyopaque, start: *anyopaque, end: *anyopaque, include_hidden_chars: bool) [*:0]u8;

pub extern fn gtk_event_controller_get_widget(controller: ?*anyopaque) ?*GtkWidget;
pub extern fn gtk_event_controller_key_new() ?*anyopaque;
pub extern fn gdk_event_get_modifier_state(event: ?*anyopaque) u32;
pub extern fn gdk_event_get_keyval(event: ?*anyopaque) u32;

pub extern fn gtk_search_entry_new() ?*GtkWidget;
pub extern fn gtk_entry_new() ?*GtkWidget;
pub extern fn gtk_editable_get_text(editable: ?*anyopaque) [*:0]const u8;
pub extern fn gtk_editable_set_text(editable: ?*anyopaque, text: [*:0]const u8) void;
pub extern fn gtk_search_entry_set_key_capture_widget(entry: ?*anyopaque, widget: ?*GtkWidget) void;

pub extern fn gtk_popover_new() ?*GtkWidget;
pub extern fn gtk_popover_set_child(popover: ?*anyopaque, child: ?*GtkWidget) void;
pub extern fn gtk_popover_set_has_arrow(popover: ?*anyopaque, has_arrow: bool) void;
pub extern fn gtk_popover_present(popover: ?*anyopaque) void;
pub extern fn gtk_popover_popup(popover: ?*anyopaque) void;
pub extern fn gtk_popover_popdown(popover: ?*anyopaque) void;
pub extern fn gtk_popover_set_pointing_to(popover: ?*anyopaque, rect: *anyopaque) void;
pub extern fn gtk_popover_set_offset(popover: ?*anyopaque, x: i32, y: i32) void;
pub extern fn gtk_popover_set_autohide(popover: ?*anyopaque, autohide: bool) void;
pub extern fn gtk_popover_menu_new_from_model(model: ?*anyopaque) ?*GtkWidget;

pub extern fn gtk_list_box_new() ?*GtkWidget;
pub extern fn gtk_list_box_append(list_box: ?*anyopaque, child: ?*GtkWidget) void;
pub extern fn gtk_list_box_remove_all(list_box: ?*anyopaque) void;
pub extern fn gtk_list_box_set_selection_mode(list_box: ?*anyopaque, mode: i32) void;

pub extern fn gtk_search_bar_new() ?*GtkWidget;
pub extern fn gtk_search_bar_set_child(bar: ?*anyopaque, child: ?*GtkWidget) void;
pub extern fn gtk_search_bar_connect_entry(bar: ?*anyopaque, entry: ?*anyopaque) void;
pub extern fn gtk_search_bar_set_key_capture_widget(bar: ?*anyopaque, widget: ?*GtkWidget) void;
pub extern fn gtk_search_bar_set_search_mode(bar: ?*anyopaque, search_mode: bool) void;

pub extern fn gtk_spinner_new() ?*GtkWidget;
pub extern fn gtk_spinner_start(spinner: ?*anyopaque) void;
pub extern fn gtk_spinner_stop(spinner: ?*anyopaque) void;

pub extern fn gtk_button_new_with_label(label: [*:0]const u8) ?*GtkWidget;
pub extern fn gtk_button_set_label(button: ?*GtkButton, label: [*:0]const u8) void;
pub extern fn gtk_button_set_child(button: ?*anyopaque, child: ?*GtkWidget) void;

pub extern fn gtk_notebook_new() ?*GtkWidget;
pub extern fn gtk_notebook_append_page(notebook: ?*GtkNotebook, child: ?*GtkWidget, tab_label: ?*GtkWidget) i32;
pub extern fn gtk_notebook_set_current_page(notebook: ?*GtkNotebook, page_num: i32) void;

pub extern fn gtk_flow_box_new() ?*GtkWidget;
pub extern fn gtk_flow_box_insert(flow_box: ?*GtkFlowBox, widget: ?*GtkWidget, position: i32) void;
pub extern fn gtk_flow_box_set_selection_mode(flow_box: ?*GtkFlowBox, mode: i32) void;
pub extern fn gtk_flow_box_set_min_children_per_line(flow_box: ?*GtkFlowBox, n: u32) void;
pub extern fn gtk_flow_box_set_max_children_per_line(flow_box: ?*GtkFlowBox, n: u32) void;

pub extern fn gtk_stack_new() ?*GtkWidget;
pub extern fn gtk_stack_add_named(stack: ?*GtkStack, child: ?*GtkWidget, name: [*:0]const u8) void;
pub extern fn gtk_stack_set_visible_child_name(stack: ?*GtkStack, name: [*:0]const u8) void;
pub extern fn gtk_stack_get_visible_child_name(stack: ?*GtkStack) ?[*:0]const u8;
pub extern fn gtk_stack_remove(stack: ?*GtkStack, child: ?*GtkWidget) void;
pub extern fn gtk_stack_get_child_by_name(stack: ?*GtkStack, name: [*:0]const u8) ?*GtkWidget;
pub extern fn gtk_stack_set_transition_type(stack: ?*GtkStack, transition: i32) void;

pub extern fn gtk_expander_new(label: ?[*:0]const u8) ?*GtkWidget;
pub extern fn gtk_expander_set_child(expander: ?*GtkExpander, child: ?*GtkWidget) void;
pub extern fn gtk_expander_set_expanded(expander: ?*GtkExpander, expanded: bool) void;

pub extern fn gtk_widget_set_halign(widget: ?*GtkWidget, alignment: i32) void;
pub extern fn gtk_widget_set_valign(widget: ?*GtkWidget, alignment: i32) void;

pub extern fn g_strdup(str: ?[*:0]const u8) ?[*:0]u8;
pub extern fn g_free(ptr: gpointer) void;
pub extern fn g_get_monotonic_time() i64;
pub extern fn g_usleep(microseconds: u64) void;
pub extern fn g_thread_new(name: ?[*:0]const u8, func: ?*const anyopaque, data: gpointer) ?*anyopaque;
pub extern fn g_idle_add(function: ?*const fn (data: gpointer) callconv(.c) bool, data: gpointer) u32;

pub extern fn gtk_widget_compute_bounds(widget: ?*GtkWidget, target: ?*GtkWidget, out_bounds: *anyopaque) bool;
pub extern fn gtk_adjustment_get_page_size(adjustment: ?*GtkAdjustment) f64;

pub extern fn g_menu_new() ?*anyopaque;
pub extern fn g_menu_append(menu: ?*anyopaque, label: ?[*:0]const u8, detailed_action: ?[*:0]const u8) void;

pub const GActionEntry = extern struct {
    name: [*:0]const u8,
    activate: ?*const fn (action: ?*anyopaque, parameter: ?*anyopaque, user_data: gpointer) callconv(.c) void,
    parameter_type: ?[*:0]const u8 = null,
    state: ?[*:0]const u8 = null,
    change_state: ?*const anyopaque = null,
    padding: [3]usize = [_]usize{ 0, 0, 0 },
};
pub extern fn g_action_map_add_action_entries(action_map: ?*anyopaque, entries: [*]const GActionEntry, n_entries: i32, user_data: gpointer) void;

pub const settings_dialog = @import("ui/settings_dialog.zig");
