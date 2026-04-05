//! Pre-Capture Hook Execution for Urutau Daemon
//! Manages Lua hook execution for clipboard transformation before storage
//! Task 3.3: Implement pre-capture hook execution

const std = @import("std");
const vm = @import("lua/vm.zig");
const LuaVM = vm.LuaVM;
const ExecutionResult = vm.ExecutionResult;
const ScriptArg = vm.ScriptArg;

const Allocator = std.mem.Allocator;

/// Hook execution errors
pub const HookError = error{
    HookExecutionFailed,
    HookTimeout,
    HookResourceExhausted,
};

/// Result of hook execution
pub const HookResult = union(enum) {
    /// Hook transformed the data successfully
    transformed: []const u8,
    /// Hook rejected the data (returned nil)
    rejected,
    /// Hook execution failed
    failed: HookError,

    pub fn deinit(self: *const HookResult, allocator: Allocator) void {
        switch (self.*) {
            .transformed => |str| {
                allocator.free(str);
            },
            .rejected, .failed => {},
        }
    }
};

/// Pre-capture hook manager
pub const HookManager = struct {
    allocator: Allocator,
    lua_vm: ?*LuaVM = null,
    hook_script: ?[]const u8 = null,

    const Self = @This();

    /// Initialize hook manager with Lua VM
    pub fn init(allocator: Allocator, lua_vm: *LuaVM) Self {
        return Self{
            .allocator = allocator,
            .lua_vm = lua_vm,
            .hook_script = null,
        };
    }

    /// Set the user-defined hook script
    pub fn setHookScript(self: *Self, script: []const u8) !void {
        // Free previous script if exists
        if (self.hook_script) |old_script| {
            self.allocator.free(old_script);
        }

        // Duplicate and store new script
        self.hook_script = try self.allocator.dupe(u8, script);
    }

    /// Execute pre-capture hook on clipboard data
    /// Returns transformed data or error
    pub fn executeHook(self: *const Self, clipboard_data: []const u8) !HookResult {
        // If no hook is configured, pass through data unchanged
        if (self.hook_script == null) {
            const passthrough = try self.allocator.dupe(u8, clipboard_data);
            return HookResult{ .transformed = passthrough };
        }

        const lua_vm = self.lua_vm orelse return HookResult{ .failed = HookError.HookExecutionFailed };

        // Execute hook with clipboard data as argument
        var result = lua_vm.executeWithArgs(
            self.allocator,
            self.hook_script.?,
            &[_]ScriptArg{.{ .string = clipboard_data }},
        ) catch |err| {
            std.log.debug("Hook execution failed: {}", .{err});
            return HookResult{ .failed = switch (err) {
                error.LuaTimeoutError => HookError.HookTimeout,
                error.LuaRuntimeError, error.LuaSyntaxError => HookError.HookExecutionFailed,
                else => HookError.HookExecutionFailed,
            } };
        };
        defer result.deinit(self.allocator);

        // Process hook result
        return switch (result.value_type) {
            .string => {
                if (result.value_string) |transformed| {
                    // Hook returned transformed data
                    const data_copy = try self.allocator.dupe(u8, transformed);
                    return HookResult{ .transformed = data_copy };
                } else {
                    return HookResult{ .failed = HookError.HookExecutionFailed };
                }
            },
            .nil => {
                // Hook returned nil - reject the data
                return HookResult{ .rejected = {} };
            },
            else => {
                std.log.debug("Hook returned unexpected type: {}", .{result.value_type});
                return HookResult{ .failed = HookError.HookExecutionFailed };
            },
        };
    }

    /// Clean up hook manager resources
    pub fn deinit(self: *Self) void {
        if (self.hook_script) |script| {
            self.allocator.free(script);
            self.hook_script = null;
        }
        // Note: lua_vm is not owned by HookManager, so we don't deinit it here
    }
};
