const std = @import("std");
const gtk = @import("../gtk.zig");
const network_discovery = @import("../services/network_discovery.zig");

const gpointer = gtk.gpointer;
const GtkWindow = gtk.GtkWindow;
const GtkWidget = gtk.GtkWidget;
const GtkBox = gtk.GtkBox;
const GtkLabel = gtk.GtkLabel;
const GtkButton = gtk.GtkButton;

// GTK Imports
const gtk_box_append = gtk.gtk_box_append;
const gtk_box_new = gtk.gtk_box_new;
const gtk_label_new = gtk.gtk_label_new;
const gtk_label_set_markup = gtk.gtk_label_set_markup;
const gtk_label_set_xalign = gtk.gtk_label_set_xalign;
const gtk_button_new_with_label = gtk.gtk_button_new_with_label;
const gtk_entry_new = gtk.gtk_entry_new;
const g_signal_connect_data = gtk.g_signal_connect_data;
const gtk_widget_set_visible = gtk.gtk_widget_set_visible;
const gtk_widget_set_vexpand = gtk.gtk_widget_set_vexpand;
const gtk_widget_add_css_class = gtk.gtk_widget_add_css_class;
const gtk_widget_set_hexpand = gtk.gtk_widget_set_hexpand;
const gtk_window_present = gtk.gtk_window_present;
const gtk_window_set_title = gtk.gtk_window_set_title;
const gtk_window_set_default_size = gtk.gtk_window_set_default_size;
const gtk_window_set_modal = gtk.gtk_window_set_modal;
const gtk_window_set_transient_for = gtk.gtk_window_set_transient_for;
const gtk_window_new = gtk.gtk_window_new;
const gtk_window_set_child = gtk.gtk_window_set_child;
const gtk_window_destroy = gtk.gtk_window_destroy;
const gtk_editable_set_text = gtk.gtk_editable_set_text;
const gtk_editable_get_text = gtk.gtk_editable_get_text;
const g_idle_add = gtk.g_idle_add;
const g_thread_new = gtk.g_thread_new;
const gtk_widget_set_sensitive = gtk.gtk_widget_set_sensitive;
const gtk_button_set_label = gtk.gtk_button_set_label;
const gtk_css_provider_new = gtk.gtk_css_provider_new;
const gtk_css_provider_load_from_data = gtk.gtk_css_provider_load_from_data;
const gdk_display_get_default = gtk.gdk_display_get_default;
const gtk_style_context_add_provider_for_display = gtk.gtk_style_context_add_provider_for_display;

const GTK_ORIENTATION_VERTICAL = gtk.GTK_ORIENTATION_VERTICAL;
const GTK_ORIENTATION_HORIZONTAL = gtk.GTK_ORIENTATION_HORIZONTAL;

pub const SettingsConfig = struct {
    tts_url: []const u8,
    tts_timeout_ms: u32 = 200,
    tts_retry_count: u8 = 3,
    llm_url: []const u8 = "http://127.0.0.1:11434",
    font_size: i32 = 14,
    theme: []const u8 = "tokyo-night",
};

pub const SettingsCallbacks = struct {
    onSave: *const fn (config: SettingsConfig) void,
    onTest: ?*const fn (url: []const u8) bool = null,
    allocator: std.mem.Allocator,
};

pub const SettingsDialog = struct {
    window: ?*GtkWindow,
    tts_url_entry: ?*GtkWidget,
    llm_url_entry: ?*GtkWidget,
    timeout_entry: ?*GtkWidget,
    retry_entry: ?*GtkWidget,
    status_label: ?*GtkWidget,
    test_status_label: ?*GtkWidget,
    callbacks: SettingsCallbacks,
    discovery: network_discovery.NetworkDiscovery,
    parent: ?*GtkWindow,
    allocator: std.mem.Allocator,
    io: std.Io,
    config: SettingsConfig,

    pub fn init(allocator: std.mem.Allocator, parent: ?*GtkWindow, callbacks: SettingsCallbacks, config: SettingsConfig, io: std.Io) *SettingsDialog {
        const self = allocator.create(SettingsDialog) catch unreachable;

        const window = gtk_window_new();
        gtk_window_set_title(window, "Metanoia Preferences");
        gtk_window_set_default_size(window, 600, 650);
        gtk_window_set_modal(window, true);
        gtk_window_set_transient_for(window, parent);

        applyStyles();

        const root_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
        gtk_widget_add_css_class(root_box, "settings-dialog-root");
        gtk_window_set_child(window, root_box);

        // Sidebar-style Navigation/Header
        const header_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
        gtk_widget_add_css_class(header_box, "settings-dialog-header");
        gtk_box_append(root_box, header_box);

        const title = gtk_label_new(null);
        gtk_label_set_markup(title, "<span size='xx-large' weight='bold' foreground='#7aa2f7'>Preferences</span>");
        gtk_label_set_xalign(title, 0.0);
        gtk_box_append(header_box, title);

        const sub_title = gtk_label_new("Configure your neural environment and backend servers.");
        gtk_widget_add_css_class(sub_title, "settings-dialog-subtitle");
        gtk_label_set_xalign(sub_title, 0.0);
        gtk_box_append(header_box, sub_title);

        // Content Area
        const scroll = gtk.gtk_scrolled_window_new();
        gtk_widget_set_vexpand(scroll, true);
        gtk_box_append(root_box, scroll);

        const content_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 24);
        gtk_widget_add_css_class(content_box, "settings-dialog-content");
        gtk.gtk_scrolled_window_set_child(@ptrCast(scroll), content_box);

        self.* = .{
            .window = window,
            .tts_url_entry = null,
            .llm_url_entry = null,
            .timeout_entry = null,
            .retry_entry = null,
            .status_label = null,
            .test_status_label = null,
            .callbacks = callbacks,
            .discovery = network_discovery.NetworkDiscovery.init(allocator, io, .{}),
            .parent = parent,
            .allocator = allocator,
            .io = io,
            .config = config,
        };

        const tts_section = self.createTTSSection(config);
        gtk_box_append(content_box, tts_section);

        const llm_section = self.createLLMSection(config);
        gtk_box_append(content_box, llm_section);

        const advanced_section = self.createAdvancedSection(config);
        gtk_box_append(content_box, advanced_section);

        // Footer Actions
        const footer_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
        gtk_widget_add_css_class(footer_box, "settings-dialog-footer");
        gtk_box_append(root_box, footer_box);

        const reset_btn = gtk_button_new_with_label("Restore Defaults");
        gtk_widget_add_css_class(reset_btn, "btn-ghost");
        _ = g_signal_connect_data(reset_btn, "clicked", @ptrCast(&on_reset_clicked), self, null, 0);
        gtk_box_append(footer_box, reset_btn);

        const spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
        gtk_widget_set_hexpand(spacer, true);
        gtk_box_append(footer_box, spacer);

        const cancel_btn = gtk_button_new_with_label("Cancel");
        gtk_widget_add_css_class(cancel_btn, "btn-secondary");
        _ = g_signal_connect_data(cancel_btn, "clicked", @ptrCast(&on_cancel_clicked), self, null, 0);
        gtk_box_append(footer_box, cancel_btn);

        const save_btn = gtk_button_new_with_label("Save Changes");
        gtk_widget_add_css_class(save_btn, "btn-primary");
        _ = g_signal_connect_data(save_btn, "clicked", @ptrCast(&on_save_clicked), self, null, 0);
        gtk_box_append(footer_box, save_btn);

        return self;
    }

    fn createTTSSection(self: *SettingsDialog, config: SettingsConfig) *GtkWidget {
        const section = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
        gtk_widget_add_css_class(section, "card-section");

        const label_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        gtk_box_append(section, label_box);

        const icon = gtk_label_new("🔊");
        gtk_box_append(label_box, icon);

        const title = gtk_label_new(null);
        gtk_label_set_markup(title, "<span weight='bold' size='large' foreground='#bb9af7'>Audio Engine</span>");
        gtk_box_append(label_box, title);

        const desc = gtk_label_new("Endpoint for Qwen3-TTS neural synthesis.");
        gtk_widget_add_css_class(desc, "text-dim");
        gtk_label_set_xalign(desc, 0.0);
        gtk_box_append(section, desc);

        const entry_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        gtk_box_append(section, entry_row);

        self.tts_url_entry = gtk_entry_new();
        gtk_widget_set_hexpand(self.tts_url_entry, true);
        gtk_widget_add_css_class(self.tts_url_entry, "modern-entry");
        const url_z = self.allocator.dupeZ(u8, config.tts_url) catch "";
        gtk_editable_set_text(self.tts_url_entry, url_z);
        self.allocator.free(url_z);
        gtk_box_append(entry_row, self.tts_url_entry);

        const discover_btn = gtk_button_new_with_label("Find Server");
        gtk_widget_add_css_class(discover_btn, "btn-accent-dim");
        _ = g_signal_connect_data(discover_btn, "clicked", @ptrCast(&on_discover_clicked), self, null, 0);
        gtk_box_append(entry_row, discover_btn);

        const test_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
        gtk_box_append(section, test_row);

        const test_btn = gtk_button_new_with_label("Test Ping");
        gtk_widget_add_css_class(test_btn, "btn-small");
        _ = g_signal_connect_data(test_btn, "clicked", @ptrCast(&on_test_clicked), self, null, 0);
        gtk_box_append(test_row, test_btn);

        self.test_status_label = gtk_label_new("");
        gtk_label_set_xalign(self.test_status_label, 0.0);
        gtk_box_append(test_row, self.test_status_label);

        return section.?;
    }

    fn createLLMSection(self: *SettingsDialog, config: SettingsConfig) *GtkWidget {
        const section = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
        gtk_widget_add_css_class(section, "card-section");

        const label_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        gtk_box_append(section, label_box);

        const icon = gtk_label_new("🧠");
        gtk_box_append(label_box, icon);

        const title = gtk_label_new(null);
        gtk_label_set_markup(title, "<span weight='bold' size='large' foreground='#9ece6a'>Intelligence API</span>");
        gtk_box_append(label_box, title);

        const desc = gtk_label_new("Connect to Ollama for Granite 4 word studies.");
        gtk_widget_add_css_class(desc, "text-dim");
        gtk_label_set_xalign(desc, 0.0);
        gtk_box_append(section, desc);

        self.llm_url_entry = gtk_entry_new();
        gtk_widget_add_css_class(self.llm_url_entry, "modern-entry");
        const url_z = self.allocator.dupeZ(u8, config.llm_url) catch "";
        gtk_editable_set_text(self.llm_url_entry, url_z);
        self.allocator.free(url_z);
        gtk_box_append(section, self.llm_url_entry);

        return section.?;
    }

    fn createAdvancedSection(self: *SettingsDialog, config: SettingsConfig) *GtkWidget {
        const section = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
        gtk_widget_add_css_class(section, "card-section");

        const label_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        gtk_box_append(section, label_box);

        const icon = gtk_label_new("⚡");
        gtk_box_append(label_box, icon);

        const title = gtk_label_new(null);
        gtk_label_set_markup(title, "<span weight='bold' size='large' foreground='#e0af68'>Performance</span>");
        gtk_box_append(label_box, title);

        const grid = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
        gtk_box_append(section, grid);

        // Timeout
        const t_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
        gtk_box_append(grid, t_row);
        const t_lbl = gtk_label_new("Connection Timeout (ms)");
        gtk_widget_set_hexpand(t_lbl, true);
        gtk_label_set_xalign(t_lbl, 0.0);
        gtk_box_append(t_row, t_lbl);

        self.timeout_entry = gtk_entry_new();
        gtk_widget_add_css_class(self.timeout_entry, "modern-entry-small");
        const t_str = std.fmt.allocPrintSentinel(self.allocator, "{d}", .{config.tts_timeout_ms}, 0) catch "200";
        gtk_editable_set_text(self.timeout_entry, t_str);
        self.allocator.free(t_str);
        gtk_box_append(t_row, self.timeout_entry);

        // Retries
        const r_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
        gtk_box_append(grid, r_row);
        const r_lbl = gtk_label_new("Network Retry Count");
        gtk_widget_set_hexpand(r_lbl, true);
        gtk_label_set_xalign(r_lbl, 0.0);
        gtk_box_append(r_row, r_lbl);

        self.retry_entry = gtk_entry_new();
        gtk_widget_add_css_class(self.retry_entry, "modern-entry-small");
        const r_str = std.fmt.allocPrintSentinel(self.allocator, "{d}", .{config.tts_retry_count}, 0) catch "3";
        gtk_editable_set_text(self.retry_entry, r_str);
        self.allocator.free(r_str);
        gtk_box_append(r_row, self.retry_entry);

        return section.?;
    }

    pub fn show(self: *SettingsDialog) void {
        if (self.window) |win| {
            gtk_window_present(win);
        }
    }

    pub fn destroy(self: *SettingsDialog) void {
        if (self.window) |win| {
            gtk_window_destroy(win);
            self.window = null;
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
        \\.modern-entry-small { 
        \\  background-color: #16161e; 
        \\  color: #c0caf5; 
        \\  border: 1px solid #414868; 
        \\  border-radius: 6px; 
        \\  padding: 4px 8px;
        \\  max-width: 80px;
        \\}
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
        \\
        \\.btn-accent-dim { 
        \\  background-color: rgba(122,162,247,0.1); 
        \\  color: #7aa2f7; 
        \\  border: 1px solid rgba(122,162,247,0.2); 
        \\  border-radius: 8px; 
        \\}
        \\.btn-accent-dim:hover { background-color: rgba(122,162,247,0.2); }
        \\
        \\.btn-small { 
        \\  font-size: 11px; 
        \\  padding: 4px 12px; 
        \\  border-radius: 6px; 
        \\  background-color: #24283b; 
        \\  color: #7aa2f7; 
        \\  border: 1px solid #414868;
        \\}
    ;

    const provider = gtk_css_provider_new();
    gtk_css_provider_load_from_data(provider, css, -1);
    const display = gdk_display_get_default();
    gtk_style_context_add_provider_for_display(display, provider, gtk.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
}

// Handlers (Simplified for refactor)
fn on_cancel_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const dialog: *SettingsDialog = @ptrCast(@alignCast(user_data));
    dialog.destroy();
}

fn on_reset_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const dialog: *SettingsDialog = @ptrCast(@alignCast(user_data));
    if (dialog.tts_url_entry) |e| gtk_editable_set_text(e, "http://127.0.0.1:8000");
    if (dialog.llm_url_entry) |e| gtk_editable_set_text(e, "http://127.0.0.1:11434");
    if (dialog.timeout_entry) |e| gtk_editable_set_text(e, "200");
    if (dialog.retry_entry) |e| gtk_editable_set_text(e, "3");
}

fn on_save_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    _ = btn;
    const dialog: *SettingsDialog = @ptrCast(@alignCast(user_data));

    // Pull values from entries
    if (dialog.tts_url_entry) |e| {
        const text = gtk_editable_get_text(e);
        dialog.config.tts_url = dialog.allocator.dupe(u8, std.mem.span(text)) catch dialog.config.tts_url;
    }
    if (dialog.llm_url_entry) |e| {
        const text = gtk_editable_get_text(e);
        dialog.config.llm_url = dialog.allocator.dupe(u8, std.mem.span(text)) catch dialog.config.llm_url;
    }
    if (dialog.timeout_entry) |e| {
        const text = gtk_editable_get_text(e);
        dialog.config.tts_timeout_ms = std.fmt.parseInt(u32, std.mem.span(text), 10) catch dialog.config.tts_timeout_ms;
    }
    if (dialog.retry_entry) |e| {
        const text = gtk_editable_get_text(e);
        dialog.config.tts_retry_count = std.fmt.parseInt(u8, std.mem.span(text), 10) catch dialog.config.tts_retry_count;
    }

    dialog.callbacks.onSave(dialog.config);
    dialog.destroy();
}

fn on_discover_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    const dialog: *SettingsDialog = @ptrCast(@alignCast(user_data));
    gtk_widget_set_sensitive(btn, false);
    gtk_button_set_label(btn, "Scanning...");

    const DiscoveryTask = struct {
        btn: ?*GtkButton,
        dialog: *SettingsDialog,
        allocator: std.mem.Allocator,

        fn run(p: gpointer) callconv(.c) gpointer {
            const self: *@This() = @ptrCast(@alignCast(p));
            var disc = network_discovery.NetworkDiscovery.init(self.allocator, self.dialog.io, .{});
            if (disc.discoverSync()) |result| {
                const UpdateUI = struct {
                    url: [*:0]u8,
                    d: *SettingsDialog,
                    b: ?*GtkButton,
                    fn update(ctx_p: gpointer) callconv(.c) bool {
                        const ctx: *@This() = @ptrCast(@alignCast(ctx_p));
                        if (ctx.d.tts_url_entry) |e| gtk_editable_set_text(e, ctx.url);
                        gtk_widget_set_sensitive(ctx.b, true);
                        gtk_button_set_label(ctx.b, "Find Server");
                        ctx.d.allocator.free(std.mem.span(ctx.url));
                        ctx.d.allocator.destroy(ctx);
                        return false;
                    }
                };
                const u_ctx = self.allocator.create(UpdateUI) catch return null;
                u_ctx.* = .{ .url = self.allocator.dupeZ(u8, result.url) catch return null, .d = self.dialog, .b = self.btn };
                _ = g_idle_add(&UpdateUI.update, u_ctx);
            } else {
                const ResetUI = struct {
                    b: ?*GtkButton,
                    fn reset(b_p: gpointer) callconv(.c) bool {
                        const b: ?*GtkButton = @ptrCast(b_p);
                        gtk_widget_set_sensitive(b, true);
                        gtk_button_set_label(b, "Find Server");
                        return false;
                    }
                };
                _ = g_idle_add(&ResetUI.reset, self.btn);
            }
            self.allocator.destroy(self);
            return null;
        }
    };

    const task = dialog.allocator.create(DiscoveryTask) catch return;
    task.* = .{ .btn = btn, .dialog = dialog, .allocator = dialog.allocator };
    _ = g_thread_new("discovery", &DiscoveryTask.run, task);
}

fn on_test_clicked(btn: ?*GtkButton, user_data: gpointer) callconv(.c) void {
    const dialog: *SettingsDialog = @ptrCast(@alignCast(user_data));
    _ = btn;
    if (dialog.test_status_label) |l| gtk_label_set_markup(l, "<span foreground='#e0af68'>⏳ Pinging...</span>");

    const TestTask = struct {
        url: []const u8,
        d: *SettingsDialog,
        fn run(p: gpointer) callconv(.c) gpointer {
            const self: *@This() = @ptrCast(@alignCast(p));
            const test_url = std.fmt.allocPrint(self.d.allocator, "{s}/system_info", .{self.url}) catch "";
            defer self.d.allocator.free(test_url);

            var child = std.process.spawn(self.d.io, .{
                .argv = &.{ "curl", "-s", "--connect-timeout", "2", "-f", test_url },
                .stdout = .pipe,
            }) catch {
                return null;
            };
            const term = child.wait(self.d.io) catch std.process.Child.Term{ .exited = 1 };
            const success = term == .exited and term.exited == 0;

            const Update = struct {
                ok: bool,
                d: *SettingsDialog,
                fn update(ctx_p: gpointer) callconv(.c) bool {
                    const ctx: *@This() = @ptrCast(@alignCast(ctx_p));
                    if (ctx.d.test_status_label) |l| {
                        if (ctx.ok) gtk_label_set_markup(l, "<span foreground='#9ece6a'>✅ Online</span>")
                        else gtk_label_set_markup(l, "<span foreground='#f7768e'>❌ Offline</span>");
                    }
                    ctx.d.allocator.destroy(ctx);
                    return false;
                }
            };
            const u = self.d.allocator.create(Update) catch return null;
            u.* = .{ .ok = success, .d = self.d };
            _ = g_idle_add(&Update.update, u);
            self.d.allocator.free(self.url);
            self.d.allocator.destroy(self);
            return null;
        }
    };
    const task = dialog.allocator.create(TestTask) catch return;
    const url = gtk_editable_get_text(dialog.tts_url_entry.?);
    task.* = .{ .url = dialog.allocator.dupe(u8, std.mem.span(url)) catch "", .d = dialog };
    _ = g_thread_new("test", &TestTask.run, task);
}

// Logic Tests
test "URL Validation" {
    const testing = std.testing;
    try testing.expect(isValidUrl("http://localhost:8000"));
    try testing.expect(isValidUrl("https://metanoia.ai:443"));
    try testing.expect(!isValidUrl("not-a-url"));
    try testing.expect(!isValidUrl("ftp://localhost:21"));
}

fn isValidUrl(url: []const u8) bool {
    if (url.len < 7) return false;
    if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) return false;
    
    // Check if it has a host part after ://
    const proto_end = std.mem.indexOf(u8, url, "://") orelse return false;
    if (url.len <= proto_end + 3) return false;
    
    return true;
}
