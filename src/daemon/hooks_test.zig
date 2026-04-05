//! Pre-Capture Hook Execution Tests
//! Tests for hook manager and clipboard transformation
//! Task 3.3: Implement pre-capture hook execution

const std = @import("std");
const testing = std.testing;
const vm = @import("lua/vm.zig");
const hooks = @import("hooks.zig");
const HookManager = hooks.HookManager;
const HookResult = hooks.HookResult;
const HookError = hooks.HookError;

// ============================================================================
// Suite 1: Hook Manager Basic Operations
// ============================================================================

test "HookManager: initialization with Lua VM" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    try testing.expect(true);
}

test "HookManager: set hook script successfully" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script = "return string.upper(...)";
    try hook_manager.setHookScript(script);

    try testing.expect(hook_manager.hook_script != null);
}

test "HookManager: update hook script replaces previous" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Set first script
    try hook_manager.setHookScript("return 1");
    try testing.expect(hook_manager.hook_script != null);

    // Replace with second script
    try hook_manager.setHookScript("return 2");
    try testing.expect(hook_manager.hook_script != null);
}

// ============================================================================
// Suite 2: Hook Execution - Success Cases
// ============================================================================

test "HookManager: execute hook with no script passes through data" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const input_data = "clipboard content";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings("clipboard content", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: execute hook transforms data" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script =
        \\local data = ...
        \\return string.upper(data)
    ;
    try hook_manager.setHookScript(script);

    const input_data = "hello world";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings("HELLO WORLD", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: execute hook with complex transformation" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Hook that trims whitespace and normalizes
    const script =
        \\local data = ...
        \\return data:gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
    ;
    try hook_manager.setHookScript(script);

    const input_data = "  hello   world  ";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings("hello world", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: execute hook with URL cleaning" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Hook that cleans URLs
    const script =
        \\local url = ...
        \\return url:gsub("https?://", ""):gsub("^www%.", "")
    ;
    try hook_manager.setHookScript(script);

    const input_data = "https://www.example.com/page";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings("example.com/page", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

// ============================================================================
// Suite 3: Hook Execution - Rejection Cases
// ============================================================================

test "HookManager: execute hook rejects data by returning nil" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Hook that rejects data longer than 100 chars
    const script =
        \\local data = ...
        \\if #data > 100 then return nil end
        \\return data
    ;
    try hook_manager.setHookScript(script);

    const input_data = "x";
    var i: usize = 0;
    while (i < 101) : (i += 1) {}
    const long_data = try allocator.dupe(u8, input_data ** 102);
    defer allocator.free(long_data);

    const result = try hook_manager.executeHook(long_data);
    defer result.deinit(allocator);

    switch (result) {
        .rejected => {
            try testing.expect(true);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: execute hook accepts data within limits" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script =
        \\local data = ...
        \\if #data > 100 then return nil end
        \\return data
    ;
    try hook_manager.setHookScript(script);

    const input_data = "short data";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings("short data", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

// ============================================================================
// Suite 4: Hook Execution - Error Cases
// ============================================================================

test "HookManager: execute hook with syntax error" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const bad_script = "return 10 +";
    try hook_manager.setHookScript(bad_script);

    const input_data = "test data";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .failed => |err| {
            try testing.expect(err == HookError.HookExecutionFailed);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: execute hook with runtime error" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const bad_script =
        \\local data = ...
        \\return data.nonexistent_method()
    ;
    try hook_manager.setHookScript(bad_script);

    const input_data = "test data";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .failed => |err| {
            try testing.expect(err == HookError.HookExecutionFailed);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: execute hook with timeout" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 1000,
        .timeout_ms = 5000,
    };
    var lua_vm = try vm.LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const bad_script = "while true do end";
    try hook_manager.setHookScript(bad_script);

    const input_data = "test data";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .failed => |err| {
            try testing.expect(err == HookError.HookTimeout);
        },
        else => {
            try testing.expect(false);
        },
    }
}

// ============================================================================
// Suite 5: Hook Execution - Edge Cases
// ============================================================================

test "HookManager: execute hook with empty clipboard data" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script =
        \\local data = ...
        \\if #data == 0 then return nil end
        \\return data
    ;
    try hook_manager.setHookScript(script);

    const input_data = "";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .rejected => {
            try testing.expect(true);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: execute hook with unicode data" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script =
        \\local data = ...
        \\return data .. "_processed"
    ;
    try hook_manager.setHookScript(script);

    const input_data = "Привет мир";
    const result = try hook_manager.executeHook(input_data);
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings("Привет мир_processed", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: execute hook with binary data" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script =
        \\local data = ...
        \\return data
    ;
    try hook_manager.setHookScript(script);

    // Binary data with null bytes
    var binary_data = std.ArrayList(u8){};
    defer binary_data.deinit(allocator);
    try binary_data.appendSlice(allocator, &[_]u8{ 0x00, 0x01, 0x02, 0xFF, 0xFE });

    const result = try hook_manager.executeHook(binary_data.items);
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualSlices(u8, binary_data.items, data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: multiple hook executions with same script" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script =
        \\local data = ...
        \\return data .. "_processed"
    ;
    try hook_manager.setHookScript(script);

    // First execution
    const result1 = try hook_manager.executeHook("data1");
    defer result1.deinit(allocator);

    switch (result1) {
        .transformed => |data| {
            try testing.expectEqualStrings("data1_processed", data);
        },
        else => {
            try testing.expect(false);
        },
    }

    // Second execution
    const result2 = try hook_manager.executeHook("data2");
    defer result2.deinit(allocator);

    switch (result2) {
        .transformed => |data| {
            try testing.expectEqualStrings("data2_processed", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: hook manager cleanup doesn't affect Lua VM" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    {
        var hook_manager = HookManager.init(allocator, &lua_vm);
        const script = "return 42";
        try hook_manager.setHookScript(script);
        hook_manager.deinit();
    }

    // Lua VM should still be usable
    const result = try lua_vm.execute(allocator, "return 42");
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 42), result.value);
}

// ============================================================================
// Suite 6: Arena Allocator Safety Tests (Red Team Critical)
// ============================================================================

test "HookManager: result deinit doesn't cause use-after-free" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script = "return 'test_data'";
    try hook_manager.setHookScript(script);

    const result = try hook_manager.executeHook("input");
    defer result.deinit(allocator);

    // Access result after deinit should be safe (memory still valid)
    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings("test_data", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: multiple concurrent results don't corrupt memory" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script = "return ...";
    try hook_manager.setHookScript(script);

    // Execute multiple hooks and verify each result is independent
    var results: [5]HookResult = undefined;
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const input = try std.fmt.allocPrint(allocator, "data_{d}", .{i});
        defer allocator.free(input);
        results[i] = try hook_manager.executeHook(input);
    }

    // Verify all results are still valid
    i = 0;
    while (i < 5) : (i += 1) {
        defer results[i].deinit(allocator);
        const expected = try std.fmt.allocPrint(allocator, "data_{d}", .{i});
        defer allocator.free(expected);

        switch (results[i]) {
            .transformed => |data| {
                try testing.expectEqualStrings(expected, data);
            },
            else => {
                try testing.expect(false);
            },
        }
    }
}

// ============================================================================
// Suite 7: Hook Script Mutation Tests
// ============================================================================

test "HookManager: changing script mid-execution is safe" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Set initial script
    try hook_manager.setHookScript("return 'v1'");
    const result1 = try hook_manager.executeHook("input");
    defer result1.deinit(allocator);

    switch (result1) {
        .transformed => |data| {
            try testing.expectEqualStrings("v1", data);
        },
        else => {
            try testing.expect(false);
        },
    }

    // Change script while previous result still exists
    try hook_manager.setHookScript("return 'v2'");
    const result2 = try hook_manager.executeHook("input");
    defer result2.deinit(allocator);

    switch (result2) {
        .transformed => |data| {
            try testing.expectEqualStrings("v2", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: rapid script changes don't leak memory" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Rapidly change scripts 100 times
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const script = try std.fmt.allocPrint(allocator, "return '{d}'", .{i});
        defer allocator.free(script);
        try hook_manager.setHookScript(script);
    }

    // Final execution should work
    const result = try hook_manager.executeHook("input");
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings("99", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

// ============================================================================
// Suite 8: Binary Data with Embedded Lua Code Tests
// ============================================================================

test "HookManager: binary data with embedded Lua code is safe" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script = "return ...";
    try hook_manager.setHookScript(script);

    // Binary data that looks like Lua code
    const malicious_data = "return os.execute('rm -rf /')";
    const result = try hook_manager.executeHook(malicious_data);
    defer result.deinit(allocator);

    // Should return the data as-is (not execute it)
    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings(malicious_data, data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: null bytes in data don't cause buffer issues" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script = "return ...";
    try hook_manager.setHookScript(script);

    // Data with embedded null bytes
    var binary_data = std.ArrayList(u8){};
    defer binary_data.deinit(allocator);
    try binary_data.appendSlice(allocator, &[_]u8{ 0x00, 0x41, 0x00, 0x42, 0x00 });

    const result = try hook_manager.executeHook(binary_data.items);
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualSlices(u8, binary_data.items, data);
            try testing.expectEqual(@as(usize, 5), data.len);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: very large binary data handled safely" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script = "return ...";
    try hook_manager.setHookScript(script);

    // Create 100KB binary blob
    var large_data = std.ArrayList(u8){};
    defer large_data.deinit(allocator);
    try large_data.resize(allocator, 102400);
    @memset(large_data.items, 0xAB);

    const result = try hook_manager.executeHook(large_data.items);
    defer result.deinit(allocator);

    switch (result) {
        .transformed => |data| {
            try testing.expectEqualSlices(u8, large_data.items, data);
            try testing.expectEqual(@as(usize, 102400), data.len);
        },
        else => {
            try testing.expect(false);
        },
    }
}

// ============================================================================
// Suite 9: Failing Allocator / OOM Tests
// ============================================================================

test "HookManager: executeHook handles allocator failure gracefully" {
    const base_allocator = testing.allocator;
    var failing_allocator = std.testing.FailingAllocator.init(base_allocator, .{
        .fail_index = 15, // Fail after 15 successful allocations
    });

    var lua_vm = try vm.LuaVM.init(failing_allocator.allocator());
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(failing_allocator.allocator(), &lua_vm);
    defer hook_manager.deinit();

    const script = "return string.upper(...)";
    try hook_manager.setHookScript(script);

    const result = hook_manager.executeHook("test data");
    
    // Should either succeed or fail gracefully (not crash)
    if (result) |res| {
        defer res.deinit(failing_allocator.allocator());
        switch (res) {
            .transformed => |data| {
                try testing.expectEqualStrings("TEST DATA", data);
            },
            else => {
                try testing.expect(false);
            },
        }
    } else |err| {
        // OutOfMemory or HookError is acceptable
        try testing.expect(err == error.OutOfMemory or 
                          err == HookError.HookExecutionFailed or
                          err == HookError.HookTimeout);
    }
}

test "HookManager: setHookScript handles allocation failure" {
    const base_allocator = testing.allocator;
    var failing_allocator = std.testing.FailingAllocator.init(base_allocator, .{
        .fail_index = 5, // Fail early
    });

    var lua_vm = try vm.LuaVM.init(failing_allocator.allocator());
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(failing_allocator.allocator(), &lua_vm);
    defer hook_manager.deinit();

    // Try to set a hook script - may fail with OOM
    const script = "return ...";
    const set_result = hook_manager.setHookScript(script);
    
    if (set_result) {
        // If it succeeded, try executing
        const result = hook_manager.executeHook("test");
        if (result) |res| {
            defer res.deinit(failing_allocator.allocator());
        } else |_| {}
    } else |err| {
        // OutOfMemory is expected
        try testing.expect(err == error.OutOfMemory);
    }
}

test "HookManager: multiple hooks under memory pressure" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    const script = "return ...";
    try hook_manager.setHookScript(script);

    // Execute many hooks to stress-test memory
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        var buf: [32]u8 = undefined;
        const input = try std.fmt.bufPrint(&buf, "data_{d}", .{i});
        const result = try hook_manager.executeHook(input);
        defer result.deinit(allocator);

        switch (result) {
            .transformed => |data| {
                try testing.expectEqualStrings(input, data);
            },
            else => {
                try testing.expect(false);
            },
        }
    }
}

// ============================================================================
// Suite 10: HookResult Union Branch Coverage Tests
// ============================================================================

test "HookManager: hook returning empty string is .transformed" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Hook that returns empty string (distinct from nil)
    const script = "return \"\"";
    try hook_manager.setHookScript(script);

    const result = try hook_manager.executeHook("input");
    defer result.deinit(allocator);

    // Empty string should be .transformed, not .rejected
    switch (result) {
        .transformed => |data| {
            try testing.expectEqualStrings("", data);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: hook returning table is .failed" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Hook that returns table (unexpected type)
    const script = "return { key = 'value' }";
    try hook_manager.setHookScript(script);

    const result = try hook_manager.executeHook("input");
    defer result.deinit(allocator);

    // Table should be .failed (unexpected type)
    switch (result) {
        .failed => |err| {
            try testing.expect(err == HookError.HookExecutionFailed);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: hook returning number is .failed" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Hook that returns number (unexpected type for clipboard data)
    const script = "return 42";
    try hook_manager.setHookScript(script);

    const result = try hook_manager.executeHook("input");
    defer result.deinit(allocator);

    // Number should be .failed (unexpected type)
    switch (result) {
        .failed => |err| {
            try testing.expect(err == HookError.HookExecutionFailed);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: executeHook with null LuaVM returns .failed" {
    const allocator = testing.allocator;

    // Create hook manager without Lua VM (null pointer)
    var hook_manager = HookManager{
        .allocator = allocator,
        .lua_vm = null,
        .hook_script = try allocator.dupe(u8, "return ..."),
    };
    defer hook_manager.deinit();

    const result = try hook_manager.executeHook("input");
    defer result.deinit(allocator);

    // Should return .failed when LuaVM is null
    switch (result) {
        .failed => |err| {
            try testing.expect(err == HookError.HookExecutionFailed);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: setHookScript with empty string is valid no-op" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Set empty script
    try hook_manager.setHookScript("");

    // Execute should work (empty script returns nil)
    const result = try hook_manager.executeHook("input");
    defer result.deinit(allocator);

    // Empty script should return nil
    switch (result) {
        .transformed => |data| {
            // If it transformed, data should be from the passthrough (no script)
            try testing.expectEqualStrings("input", data);
        },
        .rejected => {
            // Or it might be rejected (empty script returns nil)
            try testing.expect(true);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: hook returning boolean is .failed" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Hook that returns boolean (unexpected type)
    const script = "return true";
    try hook_manager.setHookScript(script);

    const result = try hook_manager.executeHook("input");
    defer result.deinit(allocator);

    // Boolean should be .failed (unexpected type for clipboard transformation)
    switch (result) {
        .failed => |err| {
            try testing.expect(err == HookError.HookExecutionFailed);
        },
        else => {
            try testing.expect(false);
        },
    }
}

test "HookManager: hook returning function is .failed" {
    const allocator = testing.allocator;
    var lua_vm = try vm.LuaVM.init(allocator);
    defer lua_vm.deinit();

    var hook_manager = HookManager.init(allocator, &lua_vm);
    defer hook_manager.deinit();

    // Hook that returns function (unexpected type)
    const script = "return function() return 'test' end";
    try hook_manager.setHookScript(script);

    const result = try hook_manager.executeHook("input");
    defer result.deinit(allocator);

    // Function should be .failed (unexpected type)
    switch (result) {
        .failed => |err| {
            try testing.expect(err == HookError.HookExecutionFailed);
        },
        else => {
            try testing.expect(false);
        },
    }
}
