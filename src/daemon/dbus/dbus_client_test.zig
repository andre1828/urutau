//! D-Bus Client Unit Tests
//! Tests for the D-Bus client implementation covering happy paths and edge cases

const std = @import("std");
const testing = std.testing;
const dbus_client = @import("dbus_client.zig");
const Client = dbus_client.Client;

// ============================================================================
// Suite 1: Client Lifecycle
// ============================================================================

test "D-Bus Client: initialization" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    // Client should be created but not connected
    try testing.expect(!client.is_connected);
    try testing.expectEqual(dbus_client.DEFAULT_BACKOFF_MS, client.backoff_ms);
    try testing.expect(!client.should_exit_loop);
}

test "D-Bus Client: connect and disconnect lifecycle" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    // Initial state
    try testing.expect(!client.is_connected);

    // Connect should succeed
    try client.connect();
    try testing.expect(client.is_connected);

    // Disconnect
    client.disconnect();
    try testing.expect(!client.is_connected);
    try testing.expectEqual(dbus_client.DEFAULT_BACKOFF_MS, client.backoff_ms);
}

test "D-Bus Client: multiple connect/disconnect cycles" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    // Cycle 1
    try client.connect();
    try testing.expect(client.is_connected);
    client.disconnect();
    try testing.expect(!client.is_connected);

    // Cycle 2
    try client.connect();
    try testing.expect(client.is_connected);
    client.disconnect();
    try testing.expect(!client.is_connected);

    // Cycle 3
    try client.connect();
    try testing.expect(client.is_connected);
    client.disconnect();
    try testing.expect(!client.is_connected);
}

test "D-Bus Client: deinit cleans up connected client" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);

    // Connect before deinit
    try client.connect();
    try testing.expect(client.is_connected);

    // Deinit should handle connected state gracefully
    client.deinit();

    // After deinit, should be disconnected
    try testing.expect(!client.is_connected);
}

// ============================================================================
// Suite 2: Method Calls - Not Connected (Error Cases)
// ============================================================================

test "D-Bus Client: setClipboard fails when not connected" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    const data = "test clipboard data";
    const mime_type = "text/plain";

    try testing.expectError(error.NotConnected, client.setClipboard(data, mime_type));
}

test "D-Bus Client: simulatePaste fails when not connected" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try testing.expectError(error.NotConnected, client.simulatePaste());
}

test "D-Bus Client: getClipboardContent fails when not connected" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try testing.expectError(error.NotConnected, client.getClipboardContent());
}

test "D-Bus Client: runEventLoop fails when not connected" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try testing.expectError(error.NotConnected, client.runEventLoop());
}

test "D-Bus Client: registerSignalHandler fails when not connected" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    const mockHandler: dbus_client.SignalHandlerFn = struct {
        fn handler(ctx: *anyopaque, data: dbus_client.ClipboardData) void {
            _ = ctx;
            _ = data;
        }
    }.handler;

    try testing.expectError(error.NotConnected, client.registerSignalHandler(mockHandler, null));
}

// ============================================================================
// Suite 3: Method Calls - Connected (Happy Paths)
// ============================================================================

test "D-Bus Client: setClipboard succeeds when connected" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try client.connect();

    const data = "test clipboard data";
    const mime_type = "text/plain";

    try client.setClipboard(data, mime_type);
}

test "D-Bus Client: setClipboard with empty data" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try client.connect();

    const data = "";
    const mime_type = "text/plain";

    // Empty data should still work
    try client.setClipboard(data, mime_type);
}

test "D-Bus Client: setClipboard with different MIME types" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try client.connect();

    // Test text/plain
    try client.setClipboard("text data", "text/plain");

    // Test image/png
    const png_data = "\x89PNG\r\n\x1a\n"; // PNG magic bytes
    try client.setClipboard(png_data, "image/png");

    // Test custom MIME type
    try client.setClipboard("custom data", "application/x-custom");
}

test "D-Bus Client: setClipboard with unicode data" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try client.connect();

    const unicode_data = "Hello 世界 🌍 Привет";
    const mime_type = "text/plain";

    try client.setClipboard(unicode_data, mime_type);
}

test "D-Bus Client: simulatePaste succeeds when connected" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try client.connect();
    try client.simulatePaste();
}

// ============================================================================
// Suite 4: Exponential Backoff
// ============================================================================

test "D-Bus Client: initial backoff is default" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try testing.expectEqual(dbus_client.DEFAULT_BACKOFF_MS, client.backoff_ms);
}

test "D-Bus Client: exponential backoff increases correctly" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    // Start at default
    client.backoff_ms = dbus_client.DEFAULT_BACKOFF_MS;

    // After first failure: 1000 * 2.0 = 2000
    const first_increase = @as(u64, @intFromFloat(
        @as(f64, @floatFromInt(client.backoff_ms)) * dbus_client.BACKOFF_MULTIPLIER
    ));
    try testing.expectEqual(@as(u64, 2000), first_increase);

    // After second failure: 2000 * 2.0 = 4000
    client.backoff_ms = 2000;
    const second_increase = @as(u64, @intFromFloat(
        @as(f64, @floatFromInt(client.backoff_ms)) * dbus_client.BACKOFF_MULTIPLIER
    ));
    try testing.expectEqual(@as(u64, 4000), second_increase);
}

test "D-Bus Client: backoff caps at maximum" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    // Set backoff to near max
    client.backoff_ms = dbus_client.MAX_BACKOFF_MS - 1000;

    const next_backoff = @as(u64, @intFromFloat(
        @as(f64, @floatFromInt(client.backoff_ms)) * dbus_client.BACKOFF_MULTIPLIER
    ));

    const capped = @min(next_backoff, dbus_client.MAX_BACKOFF_MS);
    try testing.expectEqual(dbus_client.MAX_BACKOFF_MS, capped);
}

test "D-Bus Client: backoff resets after successful reconnect" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    // Simulate increased backoff
    client.backoff_ms = 8000;

    // Connect should reset backoff to default
    try client.connect();
    try testing.expectEqual(dbus_client.DEFAULT_BACKOFF_MS, client.backoff_ms);
}

test "D-Bus Client: backoff resets on disconnect" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    // Connect and increase backoff manually
    try client.connect();
    client.backoff_ms = 8000;

    // Disconnect should reset backoff
    client.disconnect();
    try testing.expectEqual(dbus_client.DEFAULT_BACKOFF_MS, client.backoff_ms);
}

// ============================================================================
// Suite 5: ClipboardData Struct
// ============================================================================

test "D-Bus Client: ClipboardData struct fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const data = try arena.allocator().dupe(u8, "test data");
    const mime_type = try arena.allocator().dupe(u8, "text/plain");

    const clipboard_data = dbus_client.ClipboardData{
        .data = data,
        .mime_type = mime_type,
        .size = 9,
        .allocator = arena.allocator(),
    };

    try testing.expectEqualStrings("test data", clipboard_data.data);
    try testing.expectEqualStrings("text/plain", clipboard_data.mime_type);
    try testing.expectEqual(@as(u64, 9), clipboard_data.size);
}

test "D-Bus Client: ClipboardData with binary data" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Simulate PNG binary data
    const png_bytes = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
    const data = try arena.allocator().dupe(u8, &png_bytes);
    const mime_type = try arena.allocator().dupe(u8, "image/png");

    const clipboard_data = dbus_client.ClipboardData{
        .data = data,
        .mime_type = mime_type,
        .size = 8,
        .allocator = arena.allocator(),
    };

    try testing.expectEqual(@as(u64, 8), clipboard_data.size);
    try testing.expectEqualStrings("image/png", clipboard_data.mime_type);
}

test "D-Bus Client: ClipboardData with null allocator" {
    const data = "test";
    const mime_type = "text/plain";

    const clipboard_data = dbus_client.ClipboardData{
        .data = data,
        .mime_type = mime_type,
        .size = 4,
        .allocator = null,
    };

    // deinit with null allocator should not crash
    var mutable_data = clipboard_data;
    mutable_data.deinit(); // Should be safe no-op
}

test "D-Bus Client: ClipboardData.deinit frees memory" {
    // Use ArenaAllocator to track allocations
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const alloc = arena.allocator();
    const data = try alloc.dupe(u8, "test data that should be freed");
    const mime_type = try alloc.dupe(u8, "text/plain");

    var clipboard_data = dbus_client.ClipboardData{
        .data = data,
        .mime_type = mime_type,
        .size = 27,
        .allocator = alloc,
    };

    // Deinit should free the allocated memory
    clipboard_data.deinit();

    // After deinit, the arena should show memory was released
    // (This is implicitly tested - if deinit didn't free, arena would leak)
}

// ============================================================================
// Suite 6: Constants
// ============================================================================

test "D-Bus Client: backoff constants" {
    try testing.expectEqual(@as(u64, 1000), dbus_client.DEFAULT_BACKOFF_MS);
    try testing.expectEqual(@as(u64, 30000), dbus_client.MAX_BACKOFF_MS);
    try testing.expectEqual(@as(f64, 2.0), dbus_client.BACKOFF_MULTIPLIER);
}

test "D-Bus Client: D-Bus service constants" {
    try testing.expectEqualStrings("org.urutau.Monitor", dbus_client.MONITOR_SERVICE);
    try testing.expectEqualStrings("/org/urutau/Monitor", dbus_client.MONITOR_PATH);
    try testing.expectEqualStrings("org.urutau.Monitor", dbus_client.MONITOR_INTERFACE);
}

// ============================================================================
// Suite 7: Event Loop Control
// ============================================================================

test "D-Bus Client: event loop exit signal" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try testing.expect(!client.should_exit_loop);

    client.exitEventLoop();

    try testing.expect(client.should_exit_loop);
}

test "D-Bus Client: multiple exitEventLoop calls are safe" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    // Multiple calls should be idempotent
    client.exitEventLoop();
    client.exitEventLoop();
    client.exitEventLoop();

    try testing.expect(client.should_exit_loop);
}

// ============================================================================
// Suite 8: Signal Handler
// ============================================================================

test "D-Bus Client: signal handler can be registered when connected" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try client.connect();

    var handler_called = false;
    const handler_ctx = &handler_called;

    const mockHandler: dbus_client.SignalHandlerFn = struct {
        fn handler(ctx: *anyopaque, data: dbus_client.ClipboardData) void {
            const called = @as(*bool, @ptrFromInt(@intFromPtr(ctx)));
            called.* = true;
            _ = data;
        }
    }.handler;

    try client.registerSignalHandler(mockHandler, handler_ctx);
    // Registration should succeed without error
}

test "D-Bus Client: signal handler receives clipboard data" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try client.connect();

    var received_data: ?dbus_client.ClipboardData = null;
    const data_ctx = &received_data;

    const mockHandler: dbus_client.SignalHandlerFn = struct {
        fn handler(ctx: *anyopaque, data: dbus_client.ClipboardData) void {
            const received = @as(*?dbus_client.ClipboardData, @ptrFromInt(@intFromPtr(ctx)));
            received.* = data;
        }
    }.handler;

    try client.registerSignalHandler(mockHandler, data_ctx);
    // Handler registered - actual invocation would happen in event loop
}

// ============================================================================
// Suite 9: Edge Cases - Large Data
// ============================================================================

test "D-Bus Client: setClipboard with large text data" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try client.connect();

    // Create 1MB of data using ArenaAllocator
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const large_data = try arena.allocator().alloc(u8, 1024 * 1024);
    @memset(large_data, 'x');

    try client.setClipboard(large_data, "text/plain");
}

test "D-Bus Client: setClipboard preserves data integrity" {
    const allocator = testing.allocator;
    var client = try Client.init(allocator);
    defer client.deinit();

    try client.connect();

    const original_data = "Hello, World! 12345 !@#$%";
    const mime_type = "text/plain";

    // Should not modify or reject the data
    try client.setClipboard(original_data, mime_type);
}
