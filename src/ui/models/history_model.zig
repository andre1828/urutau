//! History Model - Manages clipboard history data
//!
//! Provides data structures and operations for displaying clipboard history
//! in the GTK4 UI. Communicates with the daemon via D-Bus to fetch history.

const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

/// Represents a single clipboard history item
pub const HistoryItem = struct {
    id: u64,
    content: []u8,
    mime_type: []u8,
    timestamp: i64,
    is_current_clipboard: bool = false,

    pub fn deinit(self: *HistoryItem, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        allocator.free(self.mime_type);
    }
};

/// History model that manages the list of clipboard items
pub const HistoryModel = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(HistoryItem),
    list_store: ?*c.GtkStringList = null,

    pub fn init(allocator: std.mem.Allocator) !HistoryModel {
        return HistoryModel{
            .allocator = allocator,
            .items = std.ArrayList(HistoryItem).init(allocator),
        };
    }

    pub fn deinit(self: *HistoryModel) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit();
    }

    /// Add a history item
    pub fn addItem(self: *HistoryModel, id: u64, content: []u8, mime_type: []u8, timestamp: i64) !void {
        const content_copy = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(content_copy);

        const mime_type_copy = try self.allocator.dupe(u8, mime_type);
        errdefer self.allocator.free(mime_type_copy);

        try self.items.append(HistoryItem{
            .id = id,
            .content = content_copy,
            .mime_type = mime_type_copy,
            .timestamp = timestamp,
        });
    }

    /// Clear all history items
    pub fn clear(self: *HistoryModel) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();
    }

    /// Get the number of items
    pub fn count(self: *HistoryModel) usize {
        return self.items.items.len;
    }

    /// Get item at index
    pub fn getItem(self: *HistoryModel, index: usize) ?*HistoryItem {
        if (index >= self.items.items.len) return null;
        return &self.items.items[index];
    }

    /// Mark the item matching the current clipboard as current
    pub fn updateCurrentClipboard(self: *HistoryModel, current_clipboard_content: []u8) void {
        for (self.items.items) |*item| {
            item.is_current_clipboard = std.mem.eql(u8, item.content, current_clipboard_content);
        }
    }

    /// Create a GTK list box widget populated with history items
    pub fn createListBox(self: *HistoryModel) ?*c.GtkWidget {
        const list_box = c.gtk_list_box_new();
        if (list_box == null) return null;

        c.gtk_list_box_set_selection_mode(
            @as(*c.GtkListBox, @ptrCast(list_box)),
            c.GTK_SELECTION_SINGLE,
        );
        c.gtk_list_box_set_show_separators(
            @as(*c.GtkListBox, @ptrCast(list_box)),
            1,
        );

        // Add history items in reverse chronological order (newest first)
        var i: isize = @as(isize, self.items.items.len) - 1;
        while (i >= 0) : (i -= 1) {
            const item = &self.items.items[@as(usize, @intCast(i))];
            const row = createHistoryRow(item);
            if (row != null) {
                c.gtk_list_box_insert(@as(*c.GtkListBox, @ptrCast(list_box)), row, -1);
            }
        }

        // If no items, show placeholder
        if (self.items.items.len == 0) {
            addPlaceholderMessage(@as(*c.GtkListBox, @ptrCast(list_box)));
        }

        return list_box;
    }
};

/// Create a GTK list box row widget for a history item
fn createHistoryRow(item: *const HistoryItem) ?*c.GtkWidget {
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
    const content_text = truncateText(item.content, 200);
    const content_label = c.gtk_label_new(content_text.ptr);
    if (content_label != null) {
        c.gtk_label_set_wrap(c.GTK_LABEL(content_label), true);
        c.gtk_label_set_xalign(c.GTK_LABEL(content_label), 0.0);
        c.gtk_widget_set_halign(content_label, c.GTK_ALIGN_FILL);
        c.gtk_box_append(c.GTK_BOX(box), content_label);
    }

    // Create metadata label (mime type and timestamp)
    const meta_text = formatMetadata(item.mime_type, item.timestamp, item.is_current_clipboard);
    const meta_label = c.gtk_label_new(meta_text.ptr);
    if (meta_label != null) {
        c.gtk_label_set_xalign(c.GTK_LABEL(meta_label), 0.0);
        c.gtk_widget_set_halign(meta_label, c.GTK_ALIGN_FILL);
        
        // Style metadata label as smaller, gray text
        const provider = c.gtk_css_provider_new();
        if (provider != null) {
            c.gtk_css_provider_load_from_data(
                c.GTK_CSS_PROVIDER(provider),
                "label { color: #666666; font-size: 11px; }",
                -1,
                null,
            );
            c.gtk_style_context_add_provider(
                c.gtk_widget_get_style_context(meta_label),
                c.GTK_STYLE_PROVIDER(provider),
                c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
            );
        }
        
        c.gtk_box_append(c.GTK_BOX(box), meta_label);
    }

    c.gtk_list_box_row_set_child(@as(*c.GtkListBoxRow, @ptrCast(row)), box);

    // Highlight if this is the current clipboard
    if (item.is_current_clipboard) {
        c.gtk_widget_set_opacity(row, 0.7);
    }

    return row;
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

/// Truncate text to max_length characters
fn truncateText(text: []const u8, max_length: usize) std.BoundedArray(u8, 1024) {
    var result = std.BoundedArray(u8, 1024).init(0) catch unreachable;
    
    const len = @min(text.len, max_length);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        result.append(text[i]) catch break;
    }
    
    if (text.len > max_length) {
        const suffix = "...";
        var j: usize = 0;
        while (j < suffix.len) : (j += 1) {
            result.append(suffix[j]) catch break;
        }
    }
    
    return result;
}

/// Format metadata text (mime type, timestamp, current indicator)
fn formatMetadata(mime_type: []const u8, timestamp: i64, is_current: bool) std.BoundedArray(u8, 256) {
    var result = std.BoundedArray(u8, 256).init(0) catch unreachable;
    
    // Add mime type
    var i: usize = 0;
    while (i < mime_type.len) : (i += 1) {
        result.append(mime_type[i]) catch break;
    }
    
    // Add timestamp (simplified - just show the raw value for now)
    const ts_prefix = " | ";
    var j: usize = 0;
    while (j < ts_prefix.len) : (j += 1) {
        result.append(ts_prefix[j]) catch break;
    }
    
    var ts_buf: [32]u8 = undefined;
    const ts_str = std.fmt.bufPrint(&ts_buf, "{d}", .{timestamp}) catch "&lt;time&gt;";
    var k: usize = 0;
    while (k < ts_str.len) : (k += 1) {
        result.append(ts_str[k]) catch break;
    }
    
    // Add current clipboard indicator
    if (is_current) {
        const indicator = " [CURRENT]";
        var m: usize = 0;
        while (m < indicator.len) : (m += 1) {
            result.append(indicator[m]) catch break;
        }
    }
    
    return result;
}
