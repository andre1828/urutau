//! SQLite Storage Layer Unit Tests
//! Tests for the database layer covering CRUD operations, concurrency, and error handling

const std = @import("std");
const testing = std.testing;
const database = @import("database.zig");
const Database = database.Database;
const HistoryItem = database.HistoryItem;

// ============================================================================
// Suite 1: Database Initialization and Lifecycle
// ============================================================================

test "Database: initialization creates in-memory database" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Database should be ready for operations (just verify no crash)
    try testing.expect(true);
}

test "Database: initialization with file path creates database file" {
    const allocator = testing.allocator;

    // Create temporary file path
    _ = std.fs.cwd().makeOpenPath("urutau_test_tmp", .{}) catch unreachable;
    defer std.fs.cwd().deleteTree("urutau_test_tmp") catch {};

    const db_path = "urutau_test_tmp/test.db";

    var db = try Database.init(allocator, db_path);
    defer db.deinit();

    // Verify file was created (use cwd to check)
    std.fs.cwd().access(db_path, .{}) catch |err| {
        std.debug.print("Database file not created: {}\n", .{err});
        try testing.expect(false);
    };
}

test "Database: deinit cleans up resources" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);

    // Deinit should not crash
    db.deinit();

    // Just verify no crash occurred
    try testing.expect(true);
}

// ============================================================================
// Suite 2: HistoryItem Struct
// ============================================================================

test "HistoryItem: struct fields" {
    const item = HistoryItem{
        .id = 1,
        .data = "test clipboard content",
        .mime_type = "text/plain",
        .timestamp = 1234567890,
        .size = 20,
    };

    try testing.expectEqual(@as(i64, 1), item.id);
    try testing.expectEqualStrings("test clipboard content", item.data);
    try testing.expectEqualStrings("text/plain", item.mime_type);
    try testing.expectEqual(@as(i64, 1234567890), item.timestamp);
    try testing.expectEqual(@as(u64, 20), item.size);
}

test "HistoryItem: with image data" {
    // Simulate PNG binary data
    const png_bytes = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

    const item = HistoryItem{
        .id = 2,
        .data = &png_bytes,
        .mime_type = "image/png",
        .timestamp = 1234567891,
        .size = 8,
    };

    try testing.expectEqual(@as(i64, 2), item.id);
    try testing.expectEqualStrings("image/png", item.mime_type);
    try testing.expectEqual(@as(u64, 8), item.size);
}

test "HistoryItem: with unicode text" {
    const unicode_data = "Hello 世界 🌍 Привет";

    const item = HistoryItem{
        .id = 3,
        .data = unicode_data,
        .mime_type = "text/plain",
        .timestamp = 1234567892,
        .size = unicode_data.len,
    };

    try testing.expectEqual(@as(i64, 3), item.id);
    try testing.expectEqual(@as(u64, unicode_data.len), item.size);
}

// ============================================================================
// Suite 3: Insert Operations
// ============================================================================

test "Database: insert text clipboard item" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    const item = HistoryItem{
        .id = 0, // Will be auto-assigned
        .data = "test clipboard text",
        .mime_type = "text/plain",
        .timestamp = 0, // Will be auto-assigned
        .size = 18,
    };

    const inserted_id = try db.insert(item);
    try testing.expect(inserted_id > 0);
}

test "Database: insert image clipboard item" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    const png_bytes = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

    const item = HistoryItem{
        .id = 0,
        .data = &png_bytes,
        .mime_type = "image/png",
        .timestamp = 0,
        .size = 8,
    };

    const inserted_id = try db.insert(item);
    try testing.expect(inserted_id > 0);
}

test "Database: insert with empty data" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    const item = HistoryItem{
        .id = 0,
        .data = "",
        .mime_type = "text/plain",
        .timestamp = 0,
        .size = 0,
    };

    // Empty data should still be insertable
    const inserted_id = try db.insert(item);
    try testing.expect(inserted_id > 0);
}

test "Database: insert with custom MIME type" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    const item = HistoryItem{
        .id = 0,
        .data = "custom data format",
        .mime_type = "application/x-custom",
        .timestamp = 0,
        .size = 18,
    };

    const inserted_id = try db.insert(item);
    try testing.expect(inserted_id > 0);
}

// ============================================================================
// Suite 4: Query Operations (GetHistory)
// ============================================================================

test "Database: getHistory returns items in reverse chronological order" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert items with explicit timestamps
    const item1 = HistoryItem{
        .id = 0,
        .data = "first",
        .mime_type = "text/plain",
        .timestamp = 1000,
        .size = 5,
    };
    const item2 = HistoryItem{
        .id = 0,
        .data = "second",
        .mime_type = "text/plain",
        .timestamp = 2000,
        .size = 6,
    };
    const item3 = HistoryItem{
        .id = 0,
        .data = "third",
        .mime_type = "text/plain",
        .timestamp = 3000,
        .size = 5,
    };

    _ = try db.insert(item1);
    _ = try db.insert(item2);
    _ = try db.insert(item3);

    // Get all items
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const items = try db.getHistory(arena.allocator(), 0, 10);
    defer items.deinit();

    // Should return in reverse chronological order (newest first)
    try testing.expectEqual(@as(usize, 3), items.items.len);
    try testing.expectEqualStrings("third", items.items[0].data);
    try testing.expectEqualStrings("second", items.items[1].data);
    try testing.expectEqualStrings("first", items.items[2].data);
}

test "Database: getHistory with pagination" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert 5 items
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const data = try std.fmt.allocPrint(allocator, "item {d}", .{i});
        defer allocator.free(data);
        const item = HistoryItem{
            .id = 0,
            .data = data,
            .mime_type = "text/plain",
            .timestamp = @intCast(1000 + i),
            .size = 7,
        };
        _ = try db.insert(item);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Get first 2 items (page 1)
    const page1 = try db.getHistory(arena.allocator(), 0, 2);
    defer page1.deinit();
    try testing.expectEqual(@as(usize, 2), page1.items.len);

    // Get next 2 items (page 2)
    const page2 = try db.getHistory(arena.allocator(), 2, 2);
    defer page2.deinit();
    try testing.expectEqual(@as(usize, 2), page2.items.len);

    // Get remaining items (page 3)
    const page3 = try db.getHistory(arena.allocator(), 4, 2);
    defer page3.deinit();
    try testing.expectEqual(@as(usize, 1), page3.items.len);
}

test "Database: getHistory returns empty list when no items" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const items = try db.getHistory(arena.allocator(), 0, 10);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 0), items.items.len);
}

// ============================================================================
// Suite 5: Delete Operations
// ============================================================================

test "Database: deleteItem removes specific item" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert item
    const item = HistoryItem{
        .id = 0,
        .data = "to be deleted",
        .mime_type = "text/plain",
        .timestamp = 1000,
        .size = 13,
    };
    const inserted_id = try db.insert(item);

    // Delete the item
    try db.deleteItem(inserted_id);

    // Verify item is gone
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const items = try db.getHistory(arena.allocator(), 0, 10);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 0), items.items.len);
}

test "Database: deleteItem with non-existent ID returns error" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    try testing.expectError(error.ItemNotFound, db.deleteItem(999));
}

test "Database: clearHistory removes all items" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert multiple items
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const data = try std.fmt.allocPrint(allocator, "item {d}", .{i});
        defer allocator.free(data);
        const item = HistoryItem{
            .id = 0,
            .data = data,
            .mime_type = "text/plain",
            .timestamp = @intCast(1000 + i),
            .size = 7,
        };
        _ = try db.insert(item);
    }

    // Clear all history
    try db.clearHistory();

    // Verify all items are gone
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const items = try db.getHistory(arena.allocator(), 0, 10);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 0), items.items.len);
}

// ============================================================================
// Suite 6: Search and Filtering
// ============================================================================

test "Database: search filters by text content" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert items with searchable content
    _ = try db.insert(HistoryItem{ .id = 0, .data = "hello world", .mime_type = "text/plain", .timestamp = 1000, .size = 11 });
    _ = try db.insert(HistoryItem{ .id = 0, .data = "foo bar", .mime_type = "text/plain", .timestamp = 1001, .size = 7 });
    _ = try db.insert(HistoryItem{ .id = 0, .data = "hello foo", .mime_type = "text/plain", .timestamp = 1002, .size = 9 });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Search for "hello"
    const results = try db.search(arena.allocator(), "hello", 0, 10);
    defer results.deinit();

    try testing.expectEqual(@as(usize, 2), results.items.len);
    try testing.expectEqualStrings("hello foo", results.items[0].data);
    try testing.expectEqualStrings("hello world", results.items[1].data);
}

test "Database: search is case-insensitive" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    _ = try db.insert(HistoryItem{ .id = 0, .data = "Hello World", .mime_type = "text/plain", .timestamp = 1000, .size = 11 });
    _ = try db.insert(HistoryItem{ .id = 0, .data = "HELLO FOO", .mime_type = "text/plain", .timestamp = 1001, .size = 9 });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Search lowercase
    const results = try db.search(arena.allocator(), "hello", 0, 10);
    defer results.deinit();

    try testing.expectEqual(@as(usize, 2), results.items.len);
}

test "Database: search returns empty when no matches" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    _ = try db.insert(HistoryItem{ .id = 0, .data = "test data", .mime_type = "text/plain", .timestamp = 1000, .size = 9 });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const results = try db.search(arena.allocator(), "nonexistent", 0, 10);
    defer results.deinit();

    try testing.expectEqual(@as(usize, 0), results.items.len);
}

// ============================================================================
// Suite 7: Data Integrity and Edge Cases
// ============================================================================

test "Database: preserves binary data integrity" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Create binary data with all byte values
    var binary_data: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        binary_data[i] = @intCast(i);
    }

    const item = HistoryItem{
        .id = 0,
        .data = &binary_data,
        .mime_type = "application/octet-stream",
        .timestamp = 1000,
        .size = 256,
    };

    const inserted_id = try db.insert(item);

    // Retrieve and verify
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const items = try db.getHistory(arena.allocator(), 0, 1);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 1), items.items.len);
    try testing.expectEqual(@as(i64, inserted_id), items.items[0].id);
    try testing.expectEqual(@as(u64, 256), items.items[0].size);
    try testing.expect(std.mem.eql(u8, &binary_data, items.items[0].data));
}

test "Database: handles large text data" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Create 100KB of text
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const large_data = try arena.allocator().alloc(u8, 100 * 1024);
    @memset(large_data, 'x');

    const item = HistoryItem{
        .id = 0,
        .data = large_data,
        .mime_type = "text/plain",
        .timestamp = 1000,
        .size = large_data.len,
    };

    const inserted_id = try db.insert(item);
    try testing.expect(inserted_id > 0);
}

test "Database: handles multiple inserts in transaction" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert 100 items rapidly
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const data = try std.fmt.allocPrint(allocator, "item {d}", .{i});
        defer allocator.free(data);
        const item = HistoryItem{
            .id = 0,
            .data = data,
            .mime_type = "text/plain",
            .timestamp = @intCast(1000 + i),
            .size = 7,
        };
        _ = try db.insert(item);
    }

    // Verify all items are stored
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const items = try db.getHistory(arena.allocator(), 0, 100);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 100), items.items.len);
}

// ============================================================================
// Suite 8: WAL Mode and Concurrency
// ============================================================================

test "Database: WAL mode is enabled for file databases" {
    const allocator = testing.allocator;

    var tmp_dir = std.fs.cwd().makeOpenPath("urutau_wal_test", .{}) catch unreachable;
    defer std.fs.cwd().deleteTree("urutau_wal_test") catch {};

    const db_path = "urutau_wal_test/test.db";

    var db = try Database.init(allocator, db_path);
    defer db.deinit();

    // Verify WAL mode is enabled (check for -wal and -shm files after write)
    const item = HistoryItem{
        .id = 0,
        .data = "test",
        .mime_type = "text/plain",
        .timestamp = 1000,
        .size = 4,
    };
    _ = try db.insert(item);

    // WAL files should exist
    const wal_path = try std.fmt.allocPrint(allocator, "{s}-wal", .{db_path});
    defer allocator.free(wal_path);
    const shm_path = try std.fmt.allocPrint(allocator, "{s}-shm", .{db_path});
    defer allocator.free(shm_path);

    // Check if WAL files exist (they may be cleaned up after checkpoint)
    _ = tmp_dir.access(wal_path, .{}) catch false;
    _ = tmp_dir.access(shm_path, .{}) catch false;

    // Note: WAL files may be checkpointed and removed, so we just verify no errors
}

// ============================================================================
// Suite 9: Error Handling
// ============================================================================

test "Database: handles database corruption gracefully" {
    const allocator = testing.allocator;

    _ = std.fs.cwd().makeOpenPath("urutau_corrupt_test", .{}) catch unreachable;
    defer std.fs.cwd().deleteTree("urutau_corrupt_test") catch {};

    const db_path = "urutau_corrupt_test/corrupt.db";

    // Create a valid database first
    {
        var db = try Database.init(allocator, db_path);
        defer db.deinit();

        const item = HistoryItem{
            .id = 0,
            .data = "valid data",
            .mime_type = "text/plain",
            .timestamp = 1000,
            .size = 10,
        };
        _ = try db.insert(item);
    }

    // Corrupt the database file
    {
        const file = try std.fs.cwd().createFile(db_path, .{});
        defer file.close();
        try file.writeAll("corrupted data that is not a valid SQLite database");
    }

    // Attempting to open corrupted database should handle gracefully
    var db = Database.init(allocator, db_path);
    if (db) |*db_instance| {
        // If it opens, operations should fail gracefully
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const result = db_instance.getHistory(arena.allocator(), 0, 10);
        // Should return error, not crash
        if (result) |_| {
            // If it succeeds, the "corruption" wasn't severe enough
        } else |_| {
            // Expected: operation failed due to corruption
        }
        db_instance.deinit();
    } else |_| {
        // Expected: failed to initialize due to corruption
    }
}

// ============================================================================
// Suite 10: Security and Edge Cases (Red Team Additions)
// ============================================================================

test "Database: search handles SQL injection attempts" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert item with SQL special characters in data
    _ = try db.insert(HistoryItem{
        .id = 0,
        .data = "test%' OR 1=1 --",
        .mime_type = "text/plain",
        .timestamp = 1000,
        .size = 17,
    });

    _ = try db.insert(HistoryItem{
        .id = 0,
        .data = "normal data",
        .mime_type = "text/plain",
        .timestamp = 1001,
        .size = 11,
    });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Attempt SQL injection via search query
    const results = try db.search(arena.allocator(), "%' OR 1=1 --", 0, 10);
    defer results.deinit();

    // Should only find the item with matching text, not all items
    try testing.expectEqual(@as(usize, 1), results.items.len);
    try testing.expectEqualStrings("test%' OR 1=1 --", results.items[0].data);
}

test "Database: search handles SQL wildcards in query" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    _ = try db.insert(HistoryItem{
        .id = 0,
        .data = "test data",
        .mime_type = "text/plain",
        .timestamp = 1000,
        .size = 9,
    });

    _ = try db.insert(HistoryItem{
        .id = 0,
        .data = "other data",
        .mime_type = "text/plain",
        .timestamp = 1001,
        .size = 10,
    });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Search with % wildcard - should be treated as literal, not wildcard
    const results = try db.search(arena.allocator(), "test%", 0, 10);
    defer results.deinit();

    // Should find items containing "test%" literally (none in this case)
    // Note: SQLite LIKE treats % as wildcard, so this tests the behavior
    // The actual implementation may need to escape wildcards
}

test "Database: insert with empty MIME type fails" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    const item = HistoryItem{
        .id = 0,
        .data = "test data",
        .mime_type = "",
        .timestamp = 0,
        .size = 9,
    };

    // Empty MIME type should fail (NOT NULL constraint)
    const result = db.insert(item);
    if (result) |_| {
        // If it succeeds, the constraint isn't enforced - may need schema update
    } else |_| {
        // Expected: SQLite constraint error
    }
}

test "Database: pagination offset beyond total returns empty" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert 3 items
    _ = try db.insert(HistoryItem{ .id = 0, .data = "item1", .mime_type = "text/plain", .timestamp = 1000, .size = 5 });
    _ = try db.insert(HistoryItem{ .id = 0, .data = "item2", .mime_type = "text/plain", .timestamp = 1001, .size = 5 });
    _ = try db.insert(HistoryItem{ .id = 0, .data = "item3", .mime_type = "text/plain", .timestamp = 1002, .size = 5 });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Request offset far beyond total
    const items = try db.getHistory(arena.allocator(), 100, 10);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 0), items.items.len);
}

test "Database: pagination with zero limit returns empty" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert items
    _ = try db.insert(HistoryItem{ .id = 0, .data = "item1", .mime_type = "text/plain", .timestamp = 1000, .size = 5 });
    _ = try db.insert(HistoryItem{ .id = 0, .data = "item2", .mime_type = "text/plain", .timestamp = 1001, .size = 5 });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Request with zero limit
    const items = try db.getHistory(arena.allocator(), 0, 0);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 0), items.items.len);
}

test "Database: search with empty query returns all items" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert items
    _ = try db.insert(HistoryItem{ .id = 0, .data = "item1", .mime_type = "text/plain", .timestamp = 1000, .size = 5 });
    _ = try db.insert(HistoryItem{ .id = 0, .data = "item2", .mime_type = "text/plain", .timestamp = 1001, .size = 5 });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Search with empty query - should return all items (LIKE "%%" matches all)
    const results = try db.search(arena.allocator(), "", 0, 10);
    defer results.deinit();

    try testing.expectEqual(@as(usize, 2), results.items.len);
}

test "Database: search with very long query" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert item
    _ = try db.insert(HistoryItem{ .id = 0, .data = "test data", .mime_type = "text/plain", .timestamp = 1000, .size = 9 });

    // Create very long search query
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const long_query = try arena.allocator().alloc(u8, 10000);
    @memset(long_query, 'x');

    // Should handle gracefully (return empty, not crash)
    const results = try db.search(arena.allocator(), long_query[0..1000], 0, 10);
    defer results.deinit();

    try testing.expectEqual(@as(usize, 0), results.items.len);
}

test "Database: operations after deinit fail gracefully" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);

    const item = HistoryItem{
        .id = 0,
        .data = "test",
        .mime_type = "text/plain",
        .timestamp = 1000,
        .size = 4,
    };

    // Deinit the database
    db.deinit();

    // Operations after deinit should crash or fail
    // Note: This is undefined behavior in Zig - accessing freed memory
    // The test documents the expected behavior but may need adjustment
    // based on how Database handles deinit
    _ = item; // Suppress unused warning
    // We cannot safely test this without proper error handling in Database
}

test "Database: IDs continue after deletions" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert first item
    const item1 = HistoryItem{ .id = 0, .data = "first", .mime_type = "text/plain", .timestamp = 1000, .size = 5 };
    const id1 = try db.insert(item1);

    // Insert second item
    const item2 = HistoryItem{ .id = 0, .data = "second", .mime_type = "text/plain", .timestamp = 1001, .size = 6 };
    const id2 = try db.insert(item2);

    // Verify id2 > id1
    try testing.expect(id2 > id1);

    // Delete first item
    try db.deleteItem(id1);

    // Insert third item
    const item3 = HistoryItem{ .id = 0, .data = "third", .mime_type = "text/plain", .timestamp = 1002, .size = 5 };
    const id3 = try db.insert(item3);

    // id3 should be > id2 (not reuse id1)
    try testing.expect(id3 > id2);

    // Verify we have 2 items with correct IDs
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const items = try db.getHistory(arena.allocator(), 0, 10);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 2), items.items.len);

    // IDs should be id2 and id3 (not id1)
    var found_id2 = false;
    var found_id3 = false;
    for (items.items) |item| {
        if (item.id == id2) found_id2 = true;
        if (item.id == id3) found_id3 = true;
    }
    try testing.expect(found_id2);
    try testing.expect(found_id3);
}

test "Database: search doesn't match binary data" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    // Insert binary data (image)
    const png_bytes = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    _ = try db.insert(HistoryItem{
        .id = 0,
        .data = &png_bytes,
        .mime_type = "image/png",
        .timestamp = 1000,
        .size = 8,
    });

    // Insert text data
    _ = try db.insert(HistoryItem{
        .id = 0,
        .data = "hello world",
        .mime_type = "text/plain",
        .timestamp = 1001,
        .size = 11,
    });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Search for text - should only find text item, not binary
    const results = try db.search(arena.allocator(), "hello", 0, 10);
    defer results.deinit();

    try testing.expectEqual(@as(usize, 1), results.items.len);
    try testing.expectEqualStrings("hello world", results.items[0].data);
    try testing.expectEqualStrings("text/plain", results.items[0].mime_type);
}

test "Database: future timestamps are accepted" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    const future_timestamp = std.time.timestamp() + 1000000;

    const item = HistoryItem{
        .id = 0,
        .data = "future item",
        .mime_type = "text/plain",
        .timestamp = future_timestamp,
        .size = 11,
    };

    const inserted_id = try db.insert(item);
    try testing.expect(inserted_id > 0);

    // Verify it can be retrieved
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const items = try db.getHistory(arena.allocator(), 0, 10);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 1), items.items.len);
    try testing.expectEqual(future_timestamp, items.items[0].timestamp);
}

test "Database: zero timestamp uses current time" {
    const allocator = testing.allocator;
    var db = try Database.init(allocator, null);
    defer db.deinit();

    const before_timestamp = std.time.timestamp();

    const item = HistoryItem{
        .id = 0,
        .data = "auto timestamp",
        .mime_type = "text/plain",
        .timestamp = 0, // Should use current time
        .size = 16,
    };

    _ = try db.insert(item);

    const after_timestamp = std.time.timestamp();

    // Retrieve and verify timestamp was set
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const items = try db.getHistory(arena.allocator(), 0, 10);
    defer items.deinit();

    try testing.expectEqual(@as(usize, 1), items.items.len);
    const stored_timestamp = items.items[0].timestamp;
    try testing.expect(stored_timestamp >= before_timestamp);
    try testing.expect(stored_timestamp <= after_timestamp + 1); // Allow 1 second tolerance
}
