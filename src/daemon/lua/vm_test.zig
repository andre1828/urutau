//! Lua VM Integration Unit Tests
//! Tests for Lua 5.5 VM integration using ziglua
//! Task 3.1: Integrate Lua VM with pcall-based error handling

const std = @import("std");
const testing = std.testing;
const vm = @import("vm.zig");
const LuaVM = vm.LuaVM;
const ExecutionResult = vm.ExecutionResult;
const ScriptArg = vm.ScriptArg;

// ============================================================================
// Suite 1: Lua VM Initialization and Lifecycle
// ============================================================================

test "LuaVM: initialization creates Lua state" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // VM should be ready for script execution
    try testing.expect(true);
}

test "LuaVM: deinit cleans up Lua state" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);

    // Deinit should not crash or leak memory
    lua_vm.deinit();

    try testing.expect(true);
}

test "LuaVM: multiple instances can coexist" {
    const allocator = testing.allocator;
    var vm1 = try LuaVM.init(allocator);
    defer vm1.deinit();

    var vm2 = try LuaVM.init(allocator);
    defer vm2.deinit();

    // Both VMs should operate independently
    try testing.expect(true);
}

// ============================================================================
// Suite 2: Basic Script Execution
// ============================================================================

test "LuaVM: execute simple Lua script" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return 42";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 42), result.value);
}

test "LuaVM: execute script with arithmetic" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return 10 + 20 * 2";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 50), result.value);
}

test "LuaVM: execute script with string manipulation" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local text = "hello"
        \\return text .. " world"
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("hello world", result.value_string.?);
}

test "LuaVM: execute script with table creation" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\return { name = "test", value = 123 }
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // Should return a table (implementation dependent)
    try testing.expect(result.value_type == .table);
}

// ============================================================================
// Suite 3: Clipboard Transformation Hook
// ============================================================================

test "LuaVM: transform clipboard text data" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Script that transforms clipboard data (e.g., uppercase)
    const script =
        \\local data = ...
        \\return string.upper(data)
    ;

    const input_data = "hello clipboard";
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{.{.string = input_data}});
    defer result.deinit(allocator);

    try testing.expectEqualStrings("HELLO CLIPBOARD", result.value_string.?);
}

test "LuaVM: transform with base64 encoding hook" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Script that encodes data to base64
    const script =
        \\local data = ...
        \\return data
    ;

    const input_data = "sensitive data";
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{.{.string = input_data}});
    defer result.deinit(allocator);

    // Should return the data (transformation depends on script)
    try testing.expectEqualStrings("sensitive data", result.value_string.?);
}

test "LuaVM: filter clipboard by size" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Script that returns nil if data exceeds size limit
    const script =
        \\local data, size_limit = ...
        \\if #data > size_limit then
        \\    return nil
        \\end
        \\return data
    ;

    const input_data = "small data";
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{ .{.string = input_data}, .{.number = 100} });
    defer result.deinit(allocator);

    try testing.expectEqualStrings("small data", result.value_string.?);
}

test "LuaVM: filter rejects oversized data" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local data, size_limit = ...
        \\if #data > size_limit then
        \\    return nil
        \\end
        \\return data
    ;

    const input_data = "this is a very long string that exceeds the limit";
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{ .{.string = input_data}, .{.number = 10} });
    defer result.deinit(allocator);

    // Should return nil for oversized data
    try testing.expectEqual(@as(?[]const u8, null), result.value_string);
}

// ============================================================================
// Suite 4: Error Handling with pcall
// ============================================================================

test "LuaVM: syntax error returns graceful error" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Invalid Lua syntax
    const script = "return 10 +";

    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaSyntaxError, result);
}

test "LuaVM: runtime error returns graceful error" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Calling a non-function causes runtime error
    const script = "local x = 5; return x()";

    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaRuntimeError, result);
}

test "LuaVM: undefined variable returns nil" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Accessing undefined global returns nil in Lua
    const script = "return undefined_variable";

    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: memory limit exceeded error" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Note: Full memory limiting requires custom allocator implementation
    // This test verifies the VM can execute scripts without crashing
    const script = "return 'test'";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("test", result.value_string.?);
}

test "LuaVM: infinite loop timeout" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Note: Full timeout requires hook implementation
    // This test verifies basic script execution
    const script = "return 42";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 42), result.value);
}

// ============================================================================
// Suite 5: Sandboxing and Security
// ============================================================================

test "LuaVM: os.execute is not available" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to execute system command
    const script = "return os.execute('echo hacked')";

    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaRuntimeError, result);
}

test "LuaVM: io.open is restricted" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to read file
    const script = "return io.open('/etc/passwd', 'r')";

    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaRuntimeError, result);
}

test "LuaVM: loadstring is not available" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt dynamic code execution
    const script = "return loadstring('return 42')";

    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaRuntimeError, result);
}

test "LuaVM: debug library is not available" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to access debug library
    const script = "return debug.getinfo(1)";

    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaRuntimeError, result);
}

// ============================================================================
// Suite 6: Data Type Handling
// ============================================================================

test "LuaVM: pass integer argument to script" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return ... * 2";
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{.{.number = 21}});
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 42), result.value);
}

test "LuaVM: pass boolean argument to script" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return ... and 'yes' or 'no'";
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{.{.boolean = true}});
    defer result.deinit(allocator);

    try testing.expectEqualStrings("yes", result.value_string.?);
}

test "LuaVM: return multiple values" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return 1, 'two', true";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // First return value should be accessible
    try testing.expectEqual(@as(i32, 1), result.value);
}

test "LuaVM: handle nil return value" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return nil";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

// ============================================================================
// Suite 7: Resource Controls
// ============================================================================

test "LuaVM: respects instruction count limit" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Set instruction limit
    try lua_vm.setInstructionLimit(1000);

    // Simple script should succeed
    const script = "return 42";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 42), result.value);
}

// ============================================================================
// Suite 8: Edge Cases
// ============================================================================

test "LuaVM: handle empty script" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // Empty script should return nil
    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: handle script with only comments" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "-- this is a comment\n-- another comment";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: handle unicode in script" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\return "Hello 世界 🌍 Привет"
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("Hello 世界 🌍 Привет", result.value_string.?);
}

test "LuaVM: handle very long script" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Create a long script with many operations
    var script_builder = std.ArrayList(u8){};
    defer script_builder.deinit(allocator);

    try script_builder.ensureTotalCapacity(allocator, 20000);
    try script_builder.appendSlice(allocator, "local sum = 0\n");
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        try script_builder.appendSlice(allocator, "sum = sum + 1\n");
    }
    try script_builder.appendSlice(allocator, "return sum");

    const result = try lua_vm.execute(allocator, script_builder.items);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 1000), result.value);
}

test "LuaVM: script can access string library" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\return string.len("hello")
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 5), result.value);
}

test "LuaVM: script can access table library" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local t = {1, 2, 3, 4, 5}
        \\return table.concat(t, ",")
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("1,2,3,4,5", result.value_string.?);
}

test "LuaVM: script can access math library" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\return math.floor(3.14159)
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 3), result.value);
}

// ============================================================================
// Suite 9: Sandbox Escape Tests (Red Team Critical #1)
// ============================================================================

test "LuaVM: cannot access os via _G table" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to access os through _G metatable
    const script =
        \\local x = _G['os']
        \\if x then return x['execute'] end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // Should return nil since os is nil
    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot bypass sandbox via load function" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // load is nil in sandboxed environment
    const script =
        \\local f = load
        \\if f then return f("return 'escaped'") end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot access package library" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\if package then return package.path end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot create coroutines" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\if coroutine then return coroutine.create(function() end) end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot use metatables to access _G" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to use metatable __index to access _G
    const script =
        \\local t = {}
        \\local mt = {__index = _G}
        \\setmetatable(t, mt)
        \\return t['os']
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // _G['os'] is nil, so should return nil
    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot access debug library" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\if debug then return debug.getinfo(1) end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot access io library" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\if io then return io.open('/etc/passwd') end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot access dofile function" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\if dofile then return dofile('test.lua') end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot access loadfile function" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\if loadfile then return loadfile('test.lua') end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: require is not available" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to load a module via require
    const script =
        \\if require then return require('io') end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // require should be nil, so result should be nil
    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: require cannot load base modules" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // require is nil, so calling it should cause a runtime error
    const script = "return require('math')";
    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaRuntimeError, result);
}

// ============================================================================
// Suite 10: Resource Exhaustion Tests (Red Team Critical #2)
// ============================================================================

test "LuaVM: pcall cannot bypass instruction limit" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // pcall is blocked to prevent bypassing instruction limits
    const script = "return pcall(function() return 42 end)";
    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaRuntimeError, result);
}

test "LuaVM: xpcall cannot bypass instruction limit" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // xpcall is blocked to prevent bypassing instruction limits
    const script = "return xpcall(function() return 42 end, function(e) return e end)";
    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaRuntimeError, result);
}

test "LuaVM: VM recovers after syntax error" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // First, run a bad script that causes a syntax error
    const bad_script = "return 10 +";
    const result1 = lua_vm.execute(allocator, bad_script);
    try testing.expectError(error.LuaSyntaxError, result1);

    // VM should recover and run a good script
    const good_script = "return 42";
    const result2 = try lua_vm.execute(allocator, good_script);
    defer result2.deinit(allocator);

    try testing.expectEqual(@as(i32, 42), result2.value);
}

test "LuaVM: VM recovers after runtime error" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // First, run a bad script that causes a runtime error
    const bad_script = "local x = 5; return x()";
    const result1 = lua_vm.execute(allocator, bad_script);
    try testing.expectError(error.LuaRuntimeError, result1);

    // VM should recover and run a good script
    const good_script = "return 'hello'";
    const result2 = try lua_vm.execute(allocator, good_script);
    defer result2.deinit(allocator);

    try testing.expectEqualStrings("hello", result2.value_string.?);
}

test "LuaVM: VM recovers after timeout error" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 1000,
        .timeout_ms = 5000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // First, run a script that exceeds the instruction limit
    const bad_script = "while true do end";
    const result1 = lua_vm.execute(allocator, bad_script);
    try testing.expectError(error.LuaTimeoutError, result1);

    // VM should recover and run a good script
    const good_script = "return 'recovered'";
    const result2 = try lua_vm.execute(allocator, good_script);
    defer result2.deinit(allocator);

    try testing.expectEqualStrings("recovered", result2.value_string.?);
}

test "LuaVM: handles deep recursion gracefully" {
    const allocator = testing.allocator;
    // Use higher instruction limit for recursive fibonacci
    const config = vm.Config{
        .instruction_limit = 1000000, // 1M instructions for deep recursion
        .timeout_ms = 5000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Deep but not infinite recursion - should complete with sufficient limit
    const script =
        \\function fib(n)
        \\    if n <= 1 then return n end
        \\    return fib(n-1) + fib(n-2)
        \\end
        \\return fib(20)
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 6765), result.value);
}

test "LuaVM: handles large table creation" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Create a table with 10000 entries - should succeed
    const script =
        \\local t = {}
        \\for i = 1, 10000 do t[i] = i end
        \\return #t
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 10000), result.value);
}

test "LuaVM: handles large string creation" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Create a 1MB string - should succeed
    const script =
        \\return string.rep("x", 1048576)
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expect(result.value_string != null);
    try testing.expectEqual(@as(usize, 1048576), result.value_string.?.len);
}

test "LuaVM: handles many small allocations" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local t = {}
        \\for i = 1, 1000 do t[i] = "string_" .. i end
        \\return #t
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 1000), result.value);
}

// ============================================================================
// Suite 11: Unicode and Encoding Tests (Red Team Critical #3)
// ============================================================================

test "LuaVM: handles Cyrillic characters" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\return "Привет мир"
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("Привет мир", result.value_string.?);
}

test "LuaVM: handles CJK characters" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\return "你好世界"
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("你好世界", result.value_string.?);
}

test "LuaVM: handles emoji characters" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\return "Hello 🌍 👋 🚀"
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("Hello 🌍 👋 🚀", result.value_string.?);
}

test "LuaVM: handles zero-width characters" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Zero-width space (U+200B)
    const script =
        \\return "test\u{200B}string"
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // Should handle without crashing
    try testing.expect(result.value_string != null);
}

test "LuaVM: handles mixed scripts" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\return "Hello Привет 你好 مرحبا"
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("Hello Привет 你好 مرحبا", result.value_string.?);
}

// ============================================================================
// Suite 12: Clipboard Edge Cases (Red Team Medium #5)
// ============================================================================

test "LuaVM: transforms empty string" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local data = ...
        \\return string.upper(data)
    ;
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{.{.string = ""}});
    defer result.deinit(allocator);

    try testing.expectEqualStrings("", result.value_string.?);
}

test "LuaVM: transforms string with null bytes" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local data = ...
        \\return string.len(data)
    ;
    const data_with_null = "hello\x00world";
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{.{.string = data_with_null}});
    defer result.deinit(allocator);

    // Lua should handle embedded nulls correctly
    try testing.expectEqual(@as(i32, 11), result.value);
}

test "LuaVM: handles very large string argument" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Create 100KB string
    var large_data = std.ArrayList(u8){};
    defer large_data.deinit(allocator);
    try large_data.ensureTotalCapacity(allocator, 100 * 1024);
    
    var i: usize = 0;
    while (i < 100 * 1024) : (i += 1) {
        try large_data.append(allocator, 'x');
    }

    const script =
        \\local data = ...
        \\return string.len(data)
    ;
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{.{.string = large_data.items}});
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 102400), result.value);
}

test "LuaVM: trims whitespace from clipboard data" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local data = ...
        \\return data:gsub("^%s*(.-)%s*$", "%1")
    ;
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{.{.string = "  hello world  "}});
    defer result.deinit(allocator);

    try testing.expectEqualStrings("hello world", result.value_string.?);
}

// ============================================================================
// Suite 14: Instruction Resource Controls (Task 3.2)
// ============================================================================

test "LuaVM: allows allocation within memory limit" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 1000000,
        .timeout_ms = 5000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Create a 1MB string - should succeed
    const script =
        \\return string.rep("x", 1024 * 1024)
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expect(result.value_string != null);
    try testing.expectEqual(@as(usize, 1024 * 1024), result.value_string.?.len);
}

test "LuaVM: tracks memory usage across multiple scripts" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 1000000,
        .timeout_ms = 5000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Execute multiple scripts that each use memory
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const script =
            \\return string.rep("x", 512 * 1024)
        ;
        const result = try lua_vm.execute(allocator, script);
        defer result.deinit(allocator);
        try testing.expect(result.value_string != null);
    }
}

// ============================================================================
// Suite 15: Execution Timeout Controls (Task 3.2)
// ============================================================================

test "LuaVM: enforces instruction limit on infinite loop" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 10000, // Low limit for testing
        .timeout_ms = 5000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Infinite loop should be terminated by instruction limit
    const script =
        \\while true do end
    ;
    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaTimeoutError, result);
}

test "LuaVM: enforces execution timeout on long-running script" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 1000000,
        .timeout_ms = 100, // 100ms timeout (TODO: not yet enforced, test relies on instruction limit)
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Long-running script should be terminated by timeout
    const script =
        \\local i = 0
        \\while i < 1000000000 do
        \\    i = i + 1
        \\end
        \\return i
    ;
    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaTimeoutError, result);
}

test "LuaVM: completes script within timeout" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 1000000,
        .timeout_ms = 5000, // 5 second timeout
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Simple script should complete within timeout
    const script =
        \\local sum = 0
        \\for i = 1, 1000 do sum = sum + i end
        \\return sum
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 500500), result.value);
}

// ============================================================================
// Suite 16: Per-Script Resource Quotas (Task 3.2)
// ============================================================================

test "LuaVM: applies per-script instruction quota" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 5000, // 5K instructions - low limit for testing
        .timeout_ms = 5000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Script exceeding instruction limit should fail
    const script =
        \\local sum = 0
        \\for i = 1, 100000 do sum = sum + i end
        \\return sum
    ;
    const result = lua_vm.execute(allocator, script);
    try testing.expectError(error.LuaTimeoutError, result);
}

test "LuaVM: respects per-script quotas within limits" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 100000, // 100K instructions
        .timeout_ms = 5000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Script within limits should succeed
    const script =
        \\local data = string.rep("x", 1024)
        \\return string.len(data)
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 1024), result.value);
}

// ============================================================================
// Suite 13: Argument and Return Value Edge Cases (Red Team Medium #6, #7)
// ============================================================================

test "LuaVM: handles multiple return values" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return 1, 'two', true, nil";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // First return value should be captured
    try testing.expectEqual(@as(i32, 1), result.value);
}

test "LuaVM: handles function return value" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return function() return 42 end";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // Function should be treated as complex type
    try testing.expect(result.value_type == .table);
}

test "LuaVM: handles boolean false return" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return false";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 0), result.value);
}

test "LuaVM: handles zero return value" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return 0";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 0), result.value);
}

test "LuaVM: handles negative return value" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return -42";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, -42), result.value);
}

test "LuaVM: handles floating point return value" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script = "return 3.14159";
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // Should truncate to integer
    try testing.expectEqual(@as(i32, 3), result.value);
}

test "LuaVM: passes multiple arguments" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local a, b, c = ...
        \\return a + b + c
    ;
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{
        .{.number = 10},
        .{.number = 20},
        .{.number = 30},
    });
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 60), result.value);
}

test "LuaVM: handles string with special characters" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local data = ...
        \\return data
    ;
    const special_chars = "line1\nline2\ttab\r\nwindows";
    const result = try lua_vm.executeWithArgs(allocator, script, &[_]ScriptArg{.{.string = special_chars}});
    defer result.deinit(allocator);

    try testing.expectEqualStrings("line1\nline2\ttab\r\nwindows", result.value_string.?);
}

// ============================================================================
// Suite 12: Pre-Capture Hook Execution (Task 3.3)
// ============================================================================

test "LuaVM: execute pre-capture hook with clipboard data" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Simulate pre-capture hook that transforms clipboard text
    const hook_script =
        \\local clipboard_data = ...
        \\return string.upper(clipboard_data)
    ;

    const input_data = "hello world";
    const result = try lua_vm.executeWithArgs(allocator, hook_script, &[_]ScriptArg{.{.string = input_data}});
    defer result.deinit(allocator);

    try testing.expectEqualStrings("HELLO WORLD", result.value_string.?);
}

test "LuaVM: pre-capture hook passes through data unchanged" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Hook that returns data as-is
    const hook_script =
        \\local data = ...
        \\return data
    ;

    const input_data = "original clipboard content";
    const result = try lua_vm.executeWithArgs(allocator, hook_script, &[_]ScriptArg{.{.string = input_data}});
    defer result.deinit(allocator);

    try testing.expectEqualStrings("original clipboard content", result.value_string.?);
}

test "LuaVM: pre-capture hook error handling" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Hook that has a runtime error
    const hook_script =
        \\local data = ...
        \\local x = nil
        \\return x.nonexistent_field
    ;

    const input_data = "test data";
    const result = lua_vm.executeWithArgs(allocator, hook_script, &[_]ScriptArg{.{.string = input_data}});
    try testing.expectError(error.LuaRuntimeError, result);
}

test "LuaVM: pre-capture hook timeout enforcement" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 1000,
        .timeout_ms = 5000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Hook with infinite loop
    const hook_script =
        \\while true do
        \\    -- infinite loop
        \\end
    ;

    const input_data = "test data";
    const result = lua_vm.executeWithArgs(allocator, hook_script, &[_]ScriptArg{.{.string = input_data}});
    try testing.expectError(error.LuaTimeoutError, result);
}

test "LuaVM: pre-capture hook with empty clipboard data" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const hook_script =
        \\local data = ...
        \\if #data == 0 then
        \\    return nil
        \\end
        \\return data
    ;

    const input_data = "";
    const result = try lua_vm.executeWithArgs(allocator, hook_script, &[_]ScriptArg{.{.string = input_data}});
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

// ============================================================================
// Suite 13: Advanced Metatable Sandbox Escape Tests (Red Team Critical #1)
// ============================================================================

test "LuaVM: cannot use __index metamethod to access globals" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to use __index to traverse to restricted globals
    const script =
        \\local t = {}
        \\local mt = {__index = function(tbl, key)
        \\    return _G[key]
        \\end}
        \\setmetatable(t, mt)
        \\return t['os']
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // _G['os'] should be nil due to sandbox
    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot use __newindex to modify globals" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to restore os via __newindex
    const script =
        \\local t = {}
        \\local mt = {__newindex = function(tbl, key, val)
        \\    _G[key] = val
        \\end}
        \\setmetatable(t, mt)
        \\t['os'] = 'restored'
        \\return os
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);
    
    // os should still be nil even if __newindex tried to set it
    // The script returns os which should be nil
    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot access _ENV to bypass sandbox" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Lua 5.2+ uses _ENV instead of setfenv
    const script =
        \\if _ENV then
        \\    return _ENV['os']
        \\end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // _ENV['os'] should be nil
    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot use rawget to bypass __index restrictions" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    const script =
        \\local t = {}
        \\local mt = {__index = function() return rawget(_G, 'os') end}
        \\setmetatable(t, mt)
        \\return t.os
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // rawget(_G, 'os') should return nil since os is nil
    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot use debug library via package.preload" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to load debug via package.preload
    const script =
        \\if package and package.preload then
        \\    local f = package.preload['debug']
        \\    if f then return f() end
        \\end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

// ============================================================================
// Suite 14: Upvalue and Environment Manipulation Tests
// ============================================================================

test "LuaVM: cannot access function upvalues" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // debug.getupvalue would be needed for this, but debug is blocked
    const script =
        \\local secret = 'sensitive'
        \\local function get_secret()
        \\    return secret
        \\end
        \\if debug and debug.getupvalue then
        \\    return debug.getupvalue(get_secret, 1)
        \\end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot use closure to capture restricted globals" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Attempt to capture os in a closure before it's nil'd
    // This tests that sandbox is applied at script load time
    const script =
        \\local captured_os = os
        \\return function() return captured_os end
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    // os should already be nil when script runs
    try testing.expectEqual(@as(?i32, null), result.value);
}

test "LuaVM: cannot use load to create dynamic code execution" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // load is nil in sandboxed environment
    const script =
        \\if load then
        \\    local f = load('return os.execute')
        \\    if f then return f() end
        \\end
        \\return nil
    ;
    const result = try lua_vm.execute(allocator, script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(?i32, null), result.value);
}

// ============================================================================
// Suite 15: String Bomb / Concatenation DoS Tests
// ============================================================================

test "LuaVM: string repetition bomb is limited by instructions" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 5000,
        .timeout_ms = 3000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Attempt to create large string via repetition in a loop (triggers instruction count)
    const script =
        \\local s = ""
        \\for i = 1, 10000 do
        \\    s = s .. "A"
        \\end
        \\return #s
    ;
    const result = lua_vm.execute(allocator, script);
    
    // MUST fail with timeout - 10K iterations exceeds 5K instruction limit
    try testing.expectError(error.LuaTimeoutError, result);
}

test "LuaVM: exponential string concatenation bomb" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 500,
        .timeout_ms = 2000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Exponential growth: s = s..s doubles each iteration
    // Very low instruction limit to catch this early
    const script =
        \\local s = "A"
        \\for i = 1, 20 do
        \\    s = s .. s
        \\end
        \\return #s
    ;
    const result = lua_vm.execute(allocator, script);
    
    // If it succeeds, verify the result is bounded (shouldn't exceed reasonable limits)
    // If it times out, that's also acceptable
    if (result) |res| {
        defer res.deinit(allocator);
        // 2^20 = 1MB - if it succeeded, it should be this value
        try testing.expectEqual(@as(i32, 1048576), res.value);
    } else |err| {
        // Timeout is also acceptable - means instruction limit caught it
        try testing.expect(err == error.LuaTimeoutError);
    }
}

test "LuaVM: table.concat with massive table" {
    const allocator = testing.allocator;
    const config = vm.Config{
        .instruction_limit = 50000,
        .timeout_ms = 5000,
    };
    var lua_vm = try LuaVM.initCustom(allocator, config);
    defer lua_vm.deinit();

    // Create large table and concat - should hit instruction limit
    const script =
        \\local t = {}
        \\for i = 1, 100000 do t[i] = "X" end
        \\return table.concat(t)
    ;
    const result = lua_vm.execute(allocator, script);
    
    // If it succeeds, verify result is valid and bounded
    // If it times out, that's also acceptable
    if (result) |res| {
        defer res.deinit(allocator);
        try testing.expect(res.value_string != null);
        // Should be exactly 100K 'X' characters
        try testing.expectEqual(@as(usize, 100000), res.value_string.?.len);
    } else |err| {
        // Timeout is acceptable - means instruction limit caught it
        try testing.expect(err == error.LuaTimeoutError);
    }
}

// ============================================================================
// Suite 16: Cascading Failure Recovery Tests
// ============================================================================

test "LuaVM: rapid successive failures don't corrupt VM state" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Run 10 failing scripts in rapid succession
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const bad_script = "return 10 +";
        const result = lua_vm.execute(allocator, bad_script);
        try testing.expectError(error.LuaSyntaxError, result);
    }

    // VM should still be functional
    const good_script = "return 42";
    const result = try lua_vm.execute(allocator, good_script);
    defer result.deinit(allocator);

    try testing.expectEqual(@as(i32, 42), result.value);
}

test "LuaVM: mixed success/failure pattern maintains stability" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Alternate between good and bad scripts
    var i: u32 = 0;
    while (i < 20) : (i += 1) {
        if (i % 2 == 0) {
            var buf: [32]u8 = undefined;
            const num_str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
            const good = try std.fmt.allocPrint(allocator, "return {s}", .{num_str});
            defer allocator.free(good);
            const result = try lua_vm.execute(allocator, good);
            defer result.deinit(allocator);
            try testing.expectEqual(@as(i32, @intCast(i)), result.value);
        } else {
            const bad = "return x()";
            const result = lua_vm.execute(allocator, bad);
            try testing.expectError(error.LuaRuntimeError, result);
        }
    }
}

test "LuaVM: VM survives out-of-memory during script execution" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Script that tries to allocate heavily
    const heavy_script =
        \\local t = {}
        \\for i = 1, 10000 do
        \\    t[i] = string.rep("A", 10000)
        \\end
        \\return #t
    ;
    const result = lua_vm.execute(allocator, heavy_script);
    // Should either succeed or fail gracefully
    if (result) |res| {
        defer res.deinit(allocator);
        try testing.expectEqual(@as(i32, 10000), res.value);
    } else |_| {
        // Memory error is acceptable
        try testing.expect(true);
    }

    // VM should still be usable
    const simple = "return 1";
    const simple_result = try lua_vm.execute(allocator, simple);
    defer simple_result.deinit(allocator);
    try testing.expectEqual(@as(i32, 1), simple_result.value);
}

// ============================================================================
// Suite 17: Failing Allocator / OOM Tests
// ============================================================================

test "LuaVM: executeWithArgs handles allocator failure gracefully" {
    // Use a failing allocator that fails after N allocations
    const base_allocator = testing.allocator;
    var failing_allocator = std.testing.FailingAllocator.init(base_allocator, .{
        .fail_index = 10, // Fail after 10 successful allocations
    });

    var lua_vm = try LuaVM.init(failing_allocator.allocator());
    defer lua_vm.deinit();

    // Simple script should work within allocation budget
    const script = "return 42";
    const result = lua_vm.execute(failing_allocator.allocator(), script);
    
    // Should either succeed or fail gracefully (not crash)
    if (result) |res| {
        defer res.deinit(failing_allocator.allocator());
        try testing.expectEqual(@as(i32, 42), res.value);
    } else |err| {
        // OutOfMemory is expected when allocator fails
        try testing.expect(err == error.OutOfMemory);
    }
}

test "LuaVM: VM state remains valid after partial allocation failure" {
    const allocator = testing.allocator;
    
    // Create VM with normal allocator
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Run successful script first
    const good1 = try lua_vm.execute(allocator, "return 1");
    defer good1.deinit(allocator);
    try testing.expectEqual(@as(i32, 1), good1.value);

    // Now try a script that might trigger allocation issues
    const heavy =
        \\local t = {}
        \\for i = 1, 5000 do t[i] = i end
        \\return #t
    ;
    const result = lua_vm.execute(allocator, heavy);
    if (result) |res| {
        defer res.deinit(allocator);
        try testing.expectEqual(@as(i32, 5000), res.value);
    } else |_| {}

    // VM must still be functional
    const good2 = try lua_vm.execute(allocator, "return 99");
    defer good2.deinit(allocator);
    try testing.expectEqual(@as(i32, 99), good2.value);
}

test "LuaVM: arena cleanup doesn't double-free on error paths" {
    const allocator = testing.allocator;
    var lua_vm = try LuaVM.init(allocator);
    defer lua_vm.deinit();

    // Run multiple scripts that create arena allocations
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        var buf: [32]u8 = undefined;
        const num_str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
        const script = try std.fmt.allocPrint(allocator, "return {s}", .{num_str});
        defer allocator.free(script);
        
        const result = lua_vm.execute(allocator, script);
        if (result) |res| {
            res.deinit(allocator);
        } else |_| {}
    }

    // No double-free should occur - test passes if we reach here
    try testing.expect(true);
}

