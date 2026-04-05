//! History Data Model - Pure data structures (no GTK dependencies)
//!
//! Provides data structures for clipboard history that can be tested independently.

const std = @import("std");

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

/// History collection that manages clipboard items
pub const HistoryCollection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(HistoryItem),

    pub fn init(allocator: std.mem.Allocator) HistoryCollection {
        return HistoryCollection{
            .allocator = allocator,
            .items = std.ArrayList(HistoryItem).empty,
        };
    }

    pub fn deinit(self: *HistoryCollection) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
    }

    /// Add a history item
    pub fn addItem(self: *HistoryCollection, id: u64, content: []const u8, mime_type: []const u8, timestamp: i64) !void {
        const content_copy = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(content_copy);

        const mime_type_copy = try self.allocator.dupe(u8, mime_type);
        errdefer self.allocator.free(mime_type_copy);

        try self.items.append(self.allocator, HistoryItem{
            .id = id,
            .content = content_copy,
            .mime_type = mime_type_copy,
            .timestamp = timestamp,
        });
    }

    /// Clear all history items
    pub fn clear(self: *HistoryCollection) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();
    }

    /// Get the number of items
    pub fn count(self: *HistoryCollection) usize {
        return self.items.items.len;
    }

    /// Get item at index
    pub fn getItem(self: *HistoryCollection, index: usize) ?*HistoryItem {
        if (index >= self.items.items.len) return null;
        return &self.items.items[index];
    }

    /// Mark the item matching the current clipboard as current
    pub fn updateCurrentClipboard(self: *HistoryCollection, current_clipboard_content: []const u8) void {
        for (self.items.items) |*item| {
            item.is_current_clipboard = std.mem.eql(u8, item.content, current_clipboard_content);
        }
    }

    /// Filter items by search query (case-insensitive)
    pub fn filterByQuery(self: *HistoryCollection, query: []const u8, allocator: std.mem.Allocator) !std.ArrayList(*HistoryItem) {
        var filtered = std.ArrayList(*HistoryItem).empty;
        errdefer filtered.deinit(allocator);

        if (query.len == 0) {
            // Return all items when query is empty
            for (self.items.items) |*item| {
                try filtered.append(allocator, item);
            }
            return filtered;
        }

        // Case-insensitive search
        const query_lower = try std.ascii.allocLowerString(allocator, query);
        defer allocator.free(query_lower);

        for (self.items.items) |*item| {
            const content_lower = try std.ascii.allocLowerString(allocator, item.content);
            defer allocator.free(content_lower);

            if (std.mem.indexOf(u8, content_lower, query_lower) != null) {
                try filtered.append(allocator, item);
            }
        }

        return filtered;
    }
};

/// Represents a selection action result
pub const SelectionAction = enum {
    restore_only,
    restore_and_paste,
    none,
};

/// Handles clipboard item selection and restoration
pub const SelectionHandler = struct {
    allocator: std.mem.Allocator,
    selected_item: ?*HistoryItem = null,
    auto_paste_enabled: bool = false,

    pub fn init(allocator: std.mem.Allocator) SelectionHandler {
        return SelectionHandler{
            .allocator = allocator,
        };
    }

    /// Select a history item for restoration
    pub fn selectItem(self: *SelectionHandler, item: *HistoryItem) void {
        self.selected_item = item;
    }

    /// Toggle auto-paste feature
    pub fn toggleAutoPaste(self: *SelectionHandler) void {
        self.auto_paste_enabled = !self.auto_paste_enabled;
    }

    /// Get the action to perform based on selection and auto-paste state
    pub fn getAction(self: *SelectionHandler) SelectionAction {
        if (self.selected_item == null) return .none;
        if (self.auto_paste_enabled) return .restore_and_paste;
        return .restore_only;
    }

    /// Clear the current selection
    pub fn clearSelection(self: *SelectionHandler) void {
        self.selected_item = null;
    }
};
