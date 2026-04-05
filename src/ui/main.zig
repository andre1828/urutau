//! Urutau History Picker UI - GTK4/Libadwaita Application
//!
//! Provides a native GNOME interface for viewing, searching, and managing
//! clipboard history. Communicates with the Urutau Daemon via D-Bus.
//!
//! ## Architecture
//! - AdwApplicationWindow as the main container
//! - AdwToolbarView with search functionality
//! - GtkListView with AdwActionRow for history display
//! - D-Bus client for daemon communication

const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const HistoryCollection = @import("models/history_data.zig").HistoryCollection;
const HistoryItem = @import("models/history_data.zig").HistoryItem;
const SelectionHandler = @import("models/history_data.zig").SelectionHandler;
const SelectionAction = @import("models/history_data.zig").SelectionAction;

/// Application context
const AppContext = struct {
    allocator: std.mem.Allocator,
    window: ?*c.GtkWindow = null,
    history: ?*HistoryCollection = null,
    selection: ?*SelectionHandler = null,
    list_box: ?*c.GtkListBox = null,
    search_entry: ?*c.GtkWidget = null,
    // TODO: Add D-Bus client connection
};

/// Application entry point
pub fn main() !void {
    std.log.info("Urutau UI starting...", .{});

    // Initialize GTK4
    _ = c.gtk_init();

    // Create GtkApplication
    const app = c.gtk_application_new(
        "org.urutau.HistoryPicker",
        0,
    );
    
    if (app == null) {
        std.log.err("Failed to create GtkApplication", .{});
        return error.ApplicationCreationFailed;
    }

    // Create application context
    var ctx = AppContext{
        .allocator = std.heap.c_allocator,
    };

    // Connect activate signal with context pointer
    _ = c.g_signal_connect_data(
        app,
        "activate",
        @ptrCast(&activateCallback),
        @ptrCast(&ctx),
        null,
        0,
    );

    // Run the application
    const status = c.g_application_run(@as(*c.GApplication, @ptrCast(app)), 0, null);
    
    std.log.info("Urutau UI exited with status: {d}", .{status});
}

/// Activate callback - creates and shows the main window
fn activateCallback(app: ?*c.GtkApplication, user_data: ?*anyopaque) callconv(.c) void {
    const ctx = @as(*AppContext, @ptrCast(@alignCast(user_data orelse return)));
    _ = app orelse return;
    
    // Create the main application window
    const window = c.gtk_application_window_new(app);
    if (window == null) {
        std.log.err("Failed to create application window", .{});
        return;
    }

    ctx.window = @as(?*c.GtkWindow, @ptrCast(window));

    // Set window properties
    c.gtk_window_set_title(ctx.window.?, "Urutau - Clipboard History");
    c.gtk_window_set_default_size(ctx.window.?, 600, 700);

    // Initialize history collection with sample data (heap allocated)
    const history = ctx.allocator.create(HistoryCollection) catch {
        std.log.err("Failed to allocate history", .{});
        return;
    };
    history.* = HistoryCollection.init(ctx.allocator);
    ctx.history = history;

    // Initialize selection handler (heap allocated)
    const selection = ctx.allocator.create(SelectionHandler) catch {
        std.log.err("Failed to allocate selection handler", .{});
        return;
    };
    selection.* = SelectionHandler.init(ctx.allocator);
    ctx.selection = selection;

    // Add sample data for testing
    history.addItem(1, "Hello World - Sample clipboard content", "text/plain", 1234567890) catch {};
    history.addItem(2, "https://example.com/some-url", "text/plain", 1234567891) catch {};
    history.addItem(3, "Code snippet: fn main() { println!(\"Hello\"); }", "text/plain", 1234567892) catch {};

    // Build the UI with history
    buildUI(window, ctx);

    // Show the window
    c.gtk_window_present(ctx.window.?);
}

/// Build the complete UI structure
fn buildUI(window: ?*c.GtkWidget, ctx: *AppContext) void {
    if (window == null) return;

    // Create a vertical box layout
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    if (box == null) return;

    // Create header bar with search
    const header_bar = createHeaderBar(ctx);
    if (header_bar != null) {
        c.gtk_box_append(@as(*c.GtkBox, @ptrCast(box)), header_bar);
    }

    // Create history list
    const history_list = createHistoryList(ctx);
    if (history_list != null) {
        c.gtk_box_append(@as(*c.GtkBox, @ptrCast(box)), history_list);
    }

    // Set as window content
    c.gtk_window_set_child(@as(*c.GtkWindow, @ptrCast(window)), box);
    
    // Connect search signal
    if (ctx.search_entry != null) {
        _ = c.g_signal_connect_data(
            ctx.search_entry,
            "changed",
            @ptrCast(&onSearchChanged),
            @ptrCast(ctx),
            null,
            0,
        );
    }
}

/// Create the header bar with search functionality
fn createHeaderBar(ctx: *AppContext) ?*c.GtkWidget {
    // Create GtkHeaderBar
    const header = c.gtk_header_bar_new();
    c.gtk_header_bar_set_show_title_buttons(@as(*c.GtkHeaderBar, @ptrCast(header)), 1);
    
    // Create and add search entry
    const search = createSearchEntry(ctx);
    if (search != null) {
        c.gtk_header_bar_set_title_widget(@as(*c.GtkHeaderBar, @ptrCast(header)), search);
    }

    return header;
}

/// Create search entry widget
fn createSearchEntry(ctx: *AppContext) ?*c.GtkWidget {
    const search = c.gtk_entry_new();
    if (search == null) return null;

    c.gtk_entry_set_placeholder_text(@as(*c.GtkEntry, @ptrCast(search)), "Search clipboard history...");
    c.gtk_widget_set_hexpand(search, 1);
    
    // Store reference in context
    ctx.search_entry = search;

    return search;
}

/// Create the history list widget
fn createHistoryList(ctx: *AppContext) ?*c.GtkWidget {
    // Create a GtkScrolledWindow
    const scrolled = c.gtk_scrolled_window_new();
    if (scrolled == null) return null;

    c.gtk_scrolled_window_set_policy(
        @as(*c.GtkScrolledWindow, @ptrCast(scrolled)),
        c.GTK_POLICY_NEVER,
        c.GTK_POLICY_AUTOMATIC,
    );

    // Create a GtkListBox for history items
    const list_box = c.gtk_list_box_new();
    if (list_box == null) return scrolled;

    c.gtk_list_box_set_selection_mode(@as(*c.GtkListBox, @ptrCast(list_box)), c.GTK_SELECTION_SINGLE);
    c.gtk_list_box_set_show_separators(@as(*c.GtkListBox, @ptrCast(list_box)), 1);

    // Store reference in context
    ctx.list_box = @as(*c.GtkListBox, @ptrCast(list_box));

    // Populate with history items
    populateHistoryList(ctx);

    // Connect row-activated signal for item selection
    _ = c.g_signal_connect_data(
        ctx.list_box,
        "row-activated",
        @ptrCast(&onRowActivated),
        @ptrCast(ctx),
        null,
        0,
    );

    c.gtk_scrolled_window_set_child(@as(*c.GtkScrolledWindow, @ptrCast(scrolled)), list_box);

    return scrolled;
}

/// Row activated callback - handles item selection
fn onRowActivated(list_box: ?*c.GtkListBox, row: ?*c.GtkListBoxRow, user_data: ?*anyopaque) callconv(.c) void {
    const ctx = @as(*AppContext, @ptrCast(@alignCast(user_data orelse return)));
    if (ctx.selection == null or ctx.history == null) return;
    
    _ = row; // Row parameter not needed for now
    
    // Get the selected item from the list box
    const selected_row = c.gtk_list_box_get_selected_row(list_box);
    if (selected_row == null) return;
    
    // For now, we'll use a simplified approach - get the first item
    // In a real implementation, we'd map the row to the history item
    if (ctx.history.?.count() > 0) {
        const item = ctx.history.?.getItem(0);
        if (item) |hist_item| {
            ctx.selection.?.selectItem(hist_item);
            
            // Perform the action
            const action = ctx.selection.?.getAction();
            performSelectionAction(ctx, action);
        }
    }
}

/// Perform the selection action (restore clipboard, optionally paste)
fn performSelectionAction(ctx: *AppContext, action: SelectionAction) void {
    if (ctx.selection.?.selected_item == null) return;
    
    const item = ctx.selection.?.selected_item.?;
    
    std.log.info("Selected item: {s} ({s})", .{ item.content[0..@min(item.content.len, 50)], item.mime_type });
    
    switch (action) {
        .restore_only => {
            std.log.info("Restoring to clipboard only", .{});
            restoreToClipboard(ctx, item);
        },
        .restore_and_paste => {
            std.log.info("Restoring and simulating paste", .{});
            restoreToClipboard(ctx, item);
            // TODO: Simulate paste via D-Bus to extension
            // simulatePaste(ctx);
        },
        .none => {
            std.log.info("No action to perform", .{});
        },
    }
    
    // Clear selection after action
    ctx.selection.?.clearSelection();
    
    // Close window after selection (optional behavior)
    // c.gtk_window_close(ctx.window.?);
}

/// Restore item content to system clipboard
fn restoreToClipboard(ctx: *AppContext, item: *const HistoryItem) void {
    _ = ctx;
    // TODO: Call daemon via D-Bus to set clipboard content
    // For now, just log the action
    std.log.info("Would restore to clipboard: {s}", .{item.content});
    
    // Future implementation:
    // 1. Call D-Bus method SetClipboard on daemon
    // 2. Daemon calls extension to set system clipboard
    // 3. Extension confirms clipboard was set
}

/// Simulate paste operation in focused application
fn simulatePaste(ctx: *AppContext) void {
    _ = ctx;
    // TODO: Call daemon via D-Bus to simulate paste
    // For now, just log the action
    std.log.info("Would simulate paste in focused app", .{});
    
    // Future implementation:
    // 1. Call D-Bus method SimulatePaste on daemon
    // 2. Daemon calls extension to send Ctrl+V to focused app
    // 3. Extension confirms paste was simulated
}

/// Populate history list with items
fn populateHistoryList(ctx: *AppContext) void {
    if (ctx.list_box == null or ctx.history == null) return;
    
    // Clear existing rows
    c.gtk_list_box_invalidate_filter(ctx.list_box);
    
    // Remove all children (simplified approach)
    var child = c.gtk_widget_get_first_child(@as(*c.GtkWidget, @alignCast(@ptrCast(ctx.list_box))));
    while (child != null) {
        const next = c.gtk_widget_get_next_sibling(child.?);
        c.gtk_list_box_remove(ctx.list_box.?, child.?);
        child = next;
    }
    
    // Add history items in reverse chronological order (newest first)
    const history = ctx.history.?;
    var i: isize = @as(isize, @intCast(history.count())) - 1;
    while (i >= 0) : (i -= 1) {
        const item = history.getItem(@as(usize, @intCast(i)));
        if (item) |hist_item| {
            const row = createHistoryRowWidget(hist_item);
            if (row != null) {
                c.gtk_list_box_insert(ctx.list_box.?, row, -1);
            }
        }
    }
    
    // If no items, show placeholder
    if (history.count() == 0) {
        addPlaceholderMessage(ctx.list_box);
    }
}

/// Search changed callback - filters history list
fn onSearchChanged(search_entry: ?*c.GtkWidget, user_data: ?*anyopaque) callconv(.c) void {
    const ctx = @as(*AppContext, @ptrCast(@alignCast(user_data orelse return)));
    if (ctx.history == null or ctx.list_box == null or search_entry == null) return;

    // Get search text safely
    const text_ptr = c.gtk_editable_get_text(@as(*c.GtkEditable, @ptrCast(search_entry.?)));
    if (text_ptr == null) return;

    // Convert C string to Zig slice safely
    const query = std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr)));
    
    std.log.info("Search query: '{s}'", .{query});

    // Filter history items
    const history = ctx.history.?;
    var filtered = history.filterByQuery(query, ctx.allocator) catch |err| {
        std.log.err("Filter failed: {}", .{err});
        return;
    };
    defer filtered.deinit(ctx.allocator);
    
    std.log.info("Found {d} matches", .{filtered.items.len});
    
    // Clear existing rows
    var child = c.gtk_widget_get_first_child(@as(*c.GtkWidget, @alignCast(@ptrCast(ctx.list_box))));
    while (child != null) {
        const next = c.gtk_widget_get_next_sibling(child.?);
        c.gtk_list_box_remove(ctx.list_box.?, child.?);
        child = next;
    }
    
    // Add filtered items
    for (filtered.items) |item| {
        const row = createHistoryRowWidget(item);
        if (row != null) {
            c.gtk_list_box_insert(ctx.list_box.?, row, -1);
        }
    }
    
    // Show no-results message if empty
    if (filtered.items.len == 0 and query.len > 0) {
        const label = c.gtk_label_new("No results found");
        if (label != null) {
            c.gtk_widget_set_halign(label, c.GTK_ALIGN_CENTER);
            c.gtk_widget_set_valign(label, c.GTK_ALIGN_CENTER);
            c.gtk_widget_set_margin_top(label, 50);
            c.gtk_widget_set_margin_bottom(label, 50);
            
            const row = c.gtk_list_box_row_new();
            if (row != null) {
                c.gtk_list_box_row_set_child(@as(*c.GtkListBoxRow, @ptrCast(row)), label);
                c.gtk_list_box_insert(ctx.list_box.?, row, -1);
            }
        }
    }
}

/// Create a GTK list box row widget for a history item
fn createHistoryRowWidget(item: *const HistoryItem) ?*c.GtkWidget {
    const row = c.gtk_list_box_row_new();
    if (row == null) return null;

    // Create a vertical box for the row
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    if (box == null) return row;

    c.gtk_widget_set_margin_start(box, 10);
    c.gtk_widget_set_margin_end(box, 10);
    c.gtk_widget_set_margin_top(box, 6);
    c.gtk_widget_set_margin_bottom(box, 6);

    // Create content label (truncated if too long)
    // GTK copies the string internally, so we can pass a temporary buffer
    var content_buf: [1024]u8 = undefined;
    const content_text = truncateText(item.content, 200, &content_buf);
    const content_label = c.gtk_label_new(content_text.ptr);
    if (content_label != null) {
        c.gtk_label_set_wrap(@as(*c.GtkLabel, @ptrCast(content_label)), 1);
        c.gtk_label_set_xalign(@as(*c.GtkLabel, @ptrCast(content_label)), 0.0);
        c.gtk_widget_set_halign(content_label, c.GTK_ALIGN_FILL);
        c.gtk_box_append(@as(*c.GtkBox, @ptrCast(box)), content_label);
    }

    // Create metadata label
    var meta_buf: [256]u8 = undefined;
    const meta_text = formatMetadata(item.mime_type, item.timestamp, item.is_current_clipboard, &meta_buf);
    const meta_label = c.gtk_label_new(meta_text.ptr);
    if (meta_label != null) {
        c.gtk_label_set_xalign(@as(*c.GtkLabel, @ptrCast(meta_label)), 0.0);
        c.gtk_widget_set_halign(meta_label, c.GTK_ALIGN_FILL);
        c.gtk_box_append(@as(*c.GtkBox, @ptrCast(box)), meta_label);
    }

    c.gtk_list_box_row_set_child(@as(*c.GtkListBoxRow, @ptrCast(row)), box);

    // Highlight if this is the current clipboard
    if (item.is_current_clipboard) {
        c.gtk_widget_set_opacity(row, 0.7);
    }

    return row;
}

/// Truncate text to max_length characters
fn truncateText(text: []const u8, max_length: usize, buf: *[1024]u8) [:0]const u8 {
    const len = @min(text.len, max_length);

    @memcpy(buf[0..len], text[0..len]);

    if (text.len > max_length and len + 3 <= 1024) {
        buf[len] = '.';
        buf[len + 1] = '.';
        buf[len + 2] = '.';
        buf[len + 3] = 0;
        return buf[0 .. len + 3 :0];
    }

    buf[len] = 0;
    return buf[0..len :0];
}

/// Format metadata text
fn formatMetadata(mime_type: []const u8, timestamp: i64, is_current: bool, buf: *[256]u8) [:0]const u8 {
    var pos: usize = 0;
    
    // Add mime type
    const mime_len = @min(mime_type.len, 200);
    @memcpy(buf[pos .. pos + mime_len], mime_type[0..mime_len]);
    pos += mime_len;
    
    // Add timestamp
    const ts_prefix = " | ";
    @memcpy(buf[pos .. pos + ts_prefix.len], ts_prefix);
    pos += ts_prefix.len;
    
    var ts_buf: [32]u8 = undefined;
    const ts_str = std.fmt.bufPrint(&ts_buf, "{d}", .{timestamp}) catch "<time>";
    const ts_len = @min(ts_str.len, 256 - pos - 10);
    @memcpy(buf[pos .. pos + ts_len], ts_str[0..ts_len]);
    pos += ts_len;
    
    // Add current clipboard indicator
    if (is_current and pos + 10 < 256) {
        const indicator = " [CURRENT]";
        @memcpy(buf[pos .. pos + indicator.len], indicator);
        pos += indicator.len;
    }
    
    buf[pos] = 0;
    return buf[0..pos :0];
}

/// Add a placeholder message when history is empty
fn addPlaceholderMessage(list_box: ?*c.GtkListBox) void {
    if (list_box == null) return;

    const label = c.gtk_label_new("No clipboard history yet.\nCopied items will appear here.");
    if (label == null) return;

    c.gtk_widget_set_halign(label, c.GTK_ALIGN_CENTER);
    c.gtk_widget_set_valign(label, c.GTK_ALIGN_CENTER);
    c.gtk_widget_set_margin_top(label, 50);
    c.gtk_widget_set_margin_bottom(label, 50);

    const row = c.gtk_list_box_row_new();
    if (row == null) return;

    c.gtk_list_box_row_set_child(@as(*c.GtkListBoxRow, @ptrCast(row)), label);
    c.gtk_list_box_insert(list_box, row, -1);
}
