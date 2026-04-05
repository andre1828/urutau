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
const vm = @import("lua/vm.zig");
const hooks = @import("hooks.zig");
const LuaVM = vm.LuaVM;
const HookManager = hooks.HookManager;
const HookResult = hooks.HookResult;
const HookError = hooks.HookError;

/// Application entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Urutau Daemon starting...", .{});
    std.log.info("Version: 0.1.0", .{});

    // Initialize Lua VM
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();
    std.log.info("Lua VM initialized", .{});

    // Initialize Hook Manager
    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // TODO: Load user hook script from configuration
    // For now, no hook is configured (passthrough mode)

    // Initialize D-Bus connection
    var dbus_client = try dbus.Client.init(allocator);
    defer dbus_client.deinit();

    // Connect to D-Bus session bus
    try dbus_client.connect();
    std.log.info("Connected to D-Bus session bus", .{});

    // Register signal handler for clipboard changes
    var app_ctx = ApplicationContext{
        .allocator = allocator,
        .hook_manager = &hook_manager,
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
    hook_manager: *HookManager,
    // TODO: Add database connection, config, etc.
};

/// Signal handler for ClipboardChanged events
fn handleClipboardChanged(ctx: *anyopaque, data: dbus.ClipboardData) void {
    const app_ctx = @as(*ApplicationContext, @ptrFromInt(@intFromPtr(ctx)));
    const allocator = app_ctx.allocator;

    std.log.info("Clipboard changed: {s} ({d} bytes)", .{ data.mime_type, data.size });

    // Execute pre-capture hook to transform clipboard data
    const hook_result = app_ctx.hook_manager.executeHook(data.data) catch |err| {
        std.log.err("Pre-capture hook failed: {}", .{err});
        return;
    };
    defer hook_result.deinit(allocator);

    switch (hook_result) {
        .transformed => |transformed_data| {
            std.log.info("Hook transformed data: {d} bytes -> {d} bytes", .{ data.size, transformed_data.len });

            // TODO:
            // 1. Store transformed_data in SQLite database
            // 2. Update UI if open
        },
        .rejected => {
            std.log.info("Hook rejected clipboard data", .{});
            // Data rejected by hook - skip storage
        },
        .failed => |err| {
            std.log.err("Hook execution failed: {}", .{err});
            // On hook failure, optionally store original data or skip
            // For now, log error and skip storage
        },
    }
}
