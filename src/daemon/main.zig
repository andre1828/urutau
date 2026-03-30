//! Urutau Daemon - Core clipboard manager engine
//! 
//! Manages D-Bus communication with the GNOME Shell Extension,
//! SQLite storage for history persistence, and Lua VM for user scripts.
//! 
//! ## Architecture
//! The daemon communicates with the GNOME Shell Extension via D-Bus:
//! - Receives ClipboardChanged signals when clipboard content changes
//! - Stores clipboard history in SQLite database
//! - Executes Lua hooks for clipboard transformation
//! - Provides history retrieval and restoration via D-Bus methods

const std = @import("std");
const dbus = @import("dbus/dbus_client.zig");

/// Application entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Urutau Daemon starting...", .{});
    std.log.info("Version: 0.1.0", .{});

    // Initialize D-Bus connection
    var dbus_client = try dbus.Client.init(allocator);
    defer dbus_client.deinit();

    // Connect to D-Bus session bus
    try dbus_client.connect();
    std.log.info("Connected to D-Bus session bus", .{});

    // Register signal handler for clipboard changes
    var app_ctx = ApplicationContext{
        .allocator = allocator,
    };
    
    try dbus_client.registerSignalHandler(handleClipboardChanged, &app_ctx);
    std.log.info("Registered clipboard change handler", .{});

    // Main event loop
    std.log.info("Starting event loop...", .{});
    try dbus_client.runEventLoop();
    
    std.log.info("Urutau Daemon shutting down", .{});
}

/// Application context passed to signal handlers
const ApplicationContext = struct {
    allocator: std.mem.Allocator,
    // TODO: Add database connection, config, etc.
};

/// Signal handler for ClipboardChanged events
fn handleClipboardChanged(ctx: *anyopaque, data: dbus.ClipboardData) void {
    const app_ctx = @as(*ApplicationContext, @ptrFromInt(@intFromPtr(ctx)));
    _ = app_ctx; // Will be used when storage is implemented

    std.log.info("Clipboard changed: {s} ({d} bytes)", .{ data.mime_type, data.size });
    
    // TODO: 
    // 1. Store in SQLite database
    // 2. Execute Lua pre-capture hooks
    // 3. Update UI if open
}
