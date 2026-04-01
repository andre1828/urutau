//! SQLite Storage Layer for Urutau Clipboard History
//! Implements CRUD operations with WAL mode for concurrency

const std = @import("std");
const sqlite = @import("sqlite.zig");
const SqliteDb = sqlite.Database;
const Statement = sqlite.Statement;

/// Represents a single clipboard history item
pub const HistoryItem = struct {
    id: i64,
    data: []const u8,
    mime_type: []const u8,
    timestamp: i64,
    size: u64,

    /// Free allocated memory
    pub fn deinit(self: *HistoryItem, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        allocator.free(self.mime_type);
    }
};

/// Result set for history queries
pub const HistoryResult = struct {
    items: []HistoryItem,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const HistoryResult) void {
        for (self.items) |*item| {
            item.deinit(self.allocator);
        }
        self.allocator.free(self.items);
    }
};

/// Main database manager
pub const Database = struct {
    allocator: ?std.mem.Allocator,
    db: SqliteDb,

    /// Initialize database connection
    /// If path is null, creates in-memory database
    pub fn init(allocator: std.mem.Allocator, path: ?[:0]const u8) !Database {
        const db = try SqliteDb.open(path);

        // Enable WAL mode for concurrent access (only for file-based databases)
        if (path != null) {
            try sqlite.enableWAL(db);
        }

        // Create schema if not exists
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS history (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    content BLOB NOT NULL,
            \\    mime_type TEXT NOT NULL,
            \\    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            \\    search_text TEXT
            \\)
        );

        // Create index for search optimization
        try db.exec(
            \\CREATE INDEX IF NOT EXISTS idx_history_created_at ON history (created_at DESC)
        );

        return Database{
            .allocator = allocator,
            .db = db,
        };
    }

    /// Close database connection and free resources
    pub fn deinit(self: *Database) void {
        self.db.close();
        self.allocator = null;
    }

    /// Insert a new clipboard item into history
    /// Returns the inserted item's ID
    pub fn insert(self: *Database, item: HistoryItem) !i64 {
        _ = self.allocator orelse return error.AllocatorNotSet;

        var stmt = try self.db.prepare(
            \\INSERT INTO history (content, mime_type, search_text, created_at)
            \\VALUES (?, ?, ?, ?)
        );
        defer stmt.deinit();

        // Bind content as blob
        try stmt.bindBlob(1, item.data);

        // Bind MIME type
        try stmt.bindText(2, item.mime_type);

        // Extract searchable text (strip non-text for binary data)
        const search_text = if (std.mem.startsWith(u8, item.mime_type, "text/"))
            item.data
        else
            "";
        try stmt.bindText(3, search_text);

        // Bind timestamp (use provided or current time)
        if (item.timestamp > 0) {
            try stmt.bindInt(4, item.timestamp);
        } else {
            try stmt.bindInt(4, @intCast(std.time.timestamp()));
        }

        _ = try stmt.step();

        return self.db.lastInsertRowid();
    }

    /// Get history items with pagination
    /// Returns items in reverse chronological order (newest first)
    pub fn getHistory(self: *Database, allocator: std.mem.Allocator, offset: u32, limit: u32) !HistoryResult {
        var stmt = try self.db.prepare(
            \\SELECT id, content, mime_type, created_at as timestamp, LENGTH(content) as size
            \\FROM history
            \\ORDER BY created_at DESC
            \\LIMIT ? OFFSET ?
        );
        defer stmt.deinit();

        try stmt.bindInt(1, @intCast(limit));
        try stmt.bindInt(2, @intCast(offset));

        var items = std.ArrayList(HistoryItem).empty;
        items.ensureTotalCapacity(allocator, limit) catch return error.OutOfMemory;
        errdefer {
            for (items.items) |*item| {
                item.deinit(allocator);
            }
            items.deinit(allocator);
        }

        while (try stmt.step()) {
            const id = stmt.columnInt(0);
            const data = try stmt.columnBlob(1, allocator);
            const mime_type = try stmt.columnText(2, allocator);
            const timestamp = stmt.columnInt(3);
            const size = @as(u64, @intCast(stmt.columnInt(4)));

            try items.append(allocator, HistoryItem{
                .id = id,
                .data = data,
                .mime_type = mime_type,
                .timestamp = timestamp,
                .size = size,
            });
        }

        return HistoryResult{
            .items = try items.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    /// Delete a specific history item by ID
    pub fn deleteItem(self: *Database, id: i64) !void {
        var stmt = try self.db.prepare("DELETE FROM history WHERE id = ?");
        defer stmt.deinit();

        try stmt.bindInt(1, id);
        _ = try stmt.step();

        if (self.db.changes() == 0) {
            return error.ItemNotFound;
        }
    }

    /// Clear all history items
    pub fn clearHistory(self: *Database) !void {
        try self.db.exec("DELETE FROM history");
    }

    /// Search history by text content (case-insensitive)
    pub fn search(self: *Database, allocator: std.mem.Allocator, query: []const u8, offset: u32, limit: u32) !HistoryResult {
        var stmt = try self.db.prepare(
            \\SELECT id, content, mime_type, created_at as timestamp, LENGTH(content) as size
            \\FROM history
            \\WHERE search_text LIKE ?
            \\ORDER BY created_at DESC
            \\LIMIT ? OFFSET ?
        );
        defer stmt.deinit();

        // Build search pattern (case-insensitive LIKE)
        const pattern = try std.fmt.allocPrint(allocator, "%{s}%", .{query});
        defer allocator.free(pattern);

        try stmt.bindText(1, pattern);
        try stmt.bindInt(2, @intCast(limit));
        try stmt.bindInt(3, @intCast(offset));

        var items = std.ArrayList(HistoryItem).empty;
        items.ensureTotalCapacity(allocator, limit) catch return error.OutOfMemory;
        errdefer {
            for (items.items) |*item| {
                item.deinit(allocator);
            }
            items.deinit(allocator);
        }

        while (try stmt.step()) {
            const id = stmt.columnInt(0);
            const data = try stmt.columnBlob(1, allocator);
            const mime_type = try stmt.columnText(2, allocator);
            const timestamp = stmt.columnInt(3);
            const size = @as(u64, @intCast(stmt.columnInt(4)));

            try items.append(allocator, HistoryItem{
                .id = id,
                .data = data,
                .mime_type = mime_type,
                .timestamp = timestamp,
                .size = size,
            });
        }

        return HistoryResult{
            .items = try items.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }
};

test "Database: basic insert and query" {
    const allocator = std.testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    const item = HistoryItem{
        .id = 0,
        .data = "test data",
        .mime_type = "text/plain",
        .timestamp = 0,
        .size = 9,
    };

    const inserted_id = try db.insert(item);
    try std.testing.expect(inserted_id > 0);

    const result = try db.getHistory(allocator, 0, 10);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqualStrings("test data", result.items[0].data);
}
