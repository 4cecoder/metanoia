//! Metanoia UI/UX Kit — a reusable, decoupled component library for GTK4.
//!
//! This is the public entry point for the kit. It re-exports all modules
//! so consumers can do:
//!
//!     const kit = @import("kit");
//!     const box = kit.widget.Box.vertical(0);
//!
//! Or import individual sub-modules:
//!
//!     const ffi = @import("kit/ffi");
//!     const text = @import("kit/util/text");

pub const ffi = @import("ffi.zig");
pub const widget = @import("widget.zig");
pub const theme = @import("theme.zig");
pub const signal = @import("signal.zig");

pub const util = struct {
    pub const text = @import("util/text.zig");
    pub const threading = @import("util/threading.zig");
    pub const tracker = @import("util/tracker.zig");
};

pub const components = struct {
    pub const StatusBar = @import("components/status_bar.zig").StatusBar;
    pub const Search = @import("components/search_window.zig").Search;
    pub const SearchCallbacks = @import("components/search_window.zig").SearchCallbacks;
    pub const SearchResult = @import("components/search_window.zig").SearchResult;
    pub const Sidebar = @import("components/sidebar.zig").Sidebar;
    pub const SidebarCallbacks = @import("components/sidebar.zig").SidebarCallbacks;
    pub const FlowPicker = @import("components/flow_picker.zig").FlowPicker;
    pub const FlowPickerCallbacks = @import("components/flow_picker.zig").FlowPickerCallbacks;
    pub const PickerItem = @import("components/flow_picker.zig").PickerItem;
    pub const PickerLevel = @import("components/flow_picker.zig").PickerLevel;
    pub const Dialog = @import("components/dialog.zig").Dialog;
    pub const DialogCallbacks = @import("components/dialog.zig").DialogCallbacks;
    pub const DialogButton = @import("components/dialog.zig").DialogButton;
    pub const SettingsPanel = @import("components/settings_panel.zig").SettingsPanel;
    pub const SettingsCallbacks = @import("components/settings_panel.zig").SettingsCallbacks;
    pub const SettingsSection = @import("components/settings_panel.zig").SettingsSection;
    pub const SettingsField = @import("components/settings_panel.zig").SettingsField;
    pub const SettingsFieldValue = @import("components/settings_panel.zig").SettingsFieldValue;
};
