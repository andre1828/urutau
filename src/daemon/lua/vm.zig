//! Lua VM Integration for Urutau Daemon
//! Integrates Lua 5.5 VM using ziglua for user-defined clipboard transformations
//! Task 3.1: Integrate Lua VM with pcall-based error handling

const std = @import("std");
const lua = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

const Allocator = std.mem.Allocator;

/// Lua VM errors
pub const LuaError = error{
    LuaInitializationFailed,
    LuaSyntaxError,
    LuaRuntimeError,
    LuaMemoryError,
    LuaTimeoutError,
};

/// Execution result from Lua script
pub const ExecutionResult = struct {
    value: ?i32 = null,
    value_string: ?[]const u8 = null,
    value_type: ValueType = .nil,
    arena: ?*std.heap.ArenaAllocator = null,

    pub const ValueType = enum { nil, number, string, boolean, table };

    pub fn deinit(self: *const ExecutionResult, allocator: Allocator) void {
        if (self.arena) |arena_ptr| {
            arena_ptr.deinit();
            allocator.destroy(arena_ptr);
        }
    }
};

/// Script argument types
pub const ScriptArg = union(enum) {
    number: f64,
    string: []const u8,
    boolean: bool,
};

/// Lua VM configuration
pub const Config = struct {
    instruction_limit: u32 = 100000, // 100K instructions
    timeout_ms: u32 = 5000, // 5 second timeout (TODO: not yet enforced)
    max_script_instructions: ?u32 = null, // Per-script instruction limit (optional)
};

/// Lua VM instance
pub const LuaVM = struct {
    allocator: Allocator,
    config: Config,
    state: *lua.lua_State,
    instruction_count: u32 = 0,

    const Self = @This();

    /// Initialize Lua VM with custom allocator
    pub fn init(allocator: Allocator) !Self {
        return initCustom(allocator, Config{});
    }

    /// Initialize Lua VM with custom configuration
    pub fn initCustom(allocator: Allocator, config: Config) !Self {
        // Create Lua state with default allocator (uses malloc internally)
        const state = lua.luaL_newstate() orelse return error.LuaInitializationFailed;

        // Open standard libraries
        lua.luaL_openlibs(state);

        var vm = Self{
            .allocator = allocator,
            .config = config,
            .state = state,
            .instruction_count = 0,
        };

        // Apply sandboxing
        try vm.sandbox();

        // Set up hook for instruction counting and timeout
        try vm.setInstructionLimit(config.instruction_limit);

        return vm;
    }

    /// Apply security sandbox to restrict dangerous operations
    fn sandbox(self: *Self) !void {
        // Remove dangerous globals
        const dangerous = [_][]const u8{
            "os",
            "io",
            "debug",
            "loadfile",
            "load",
            "dofile",
            "loadstring",
            "require", // Block module loading to prevent C module injection
            "pcall", // Block pcall to prevent bypassing instruction limits
            "xpcall", // Block xpcall to prevent bypassing instruction limits
        };

        for (&dangerous) |name| {
            lua.lua_pushnil(self.state);
            lua.lua_setglobal(self.state, name.ptr);
        }

        // Also restrict package library to prevent loading C modules
        _ = lua.lua_getglobal(self.state, "package");
        if (!lua.lua_isnil(self.state, -1)) {
            // Remove package.loadlib to prevent loading external C modules
            lua.lua_pushnil(self.state);
            lua.lua_setfield(self.state, -2, "loadlib");
            // Remove package.searchers to prevent require from finding modules
            lua.lua_pushnil(self.state);
            lua.lua_setfield(self.state, -2, "searchers");
            lua.lua_setglobal(self.state, "package");
        } else {
            lua.lua_pop(self.state, 1);
        }

        // Restrict coroutine to prevent complex control flow
        _ = lua.lua_getglobal(self.state, "coroutine");
        if (!lua.lua_isnil(self.state, -1)) {
            lua.lua_pop(self.state, 1);
            lua.lua_pushnil(self.state);
            lua.lua_setglobal(self.state, "coroutine");
        } else {
            lua.lua_pop(self.state, 1);
        }
    }

    /// Set instruction count limit for timeout protection
    pub fn setInstructionLimit(self: *Self, limit: u32) !void {
        self.config.instruction_limit = limit;
        
        // Set up Lua hook for instruction counting
        // LUA_MASKCOUNT triggers hook every N instructions
        // When hook is called, it means N instructions have been executed
        lua.lua_sethook(
            self.state,
            hookCallback,
            lua.LUA_MASKCOUNT,
            @intCast(limit),
        );
    }

    /// Set execution timeout in milliseconds
    pub fn setTimeout(self: *Self, timeout_ms: u32) !void {
        self.config.timeout_ms = timeout_ms;
    }

    /// Lua hook callback for instruction counting and timeout
    fn hookCallback(state: ?*lua.lua_State, ar: [*c]lua.lua_Debug) callconv(.c) void {
        _ = ar;
        // Hook is called every `limit` instructions
        // When called, the script has exceeded its instruction limit
        lua.lua_sethook(state, null, 0, 0);
        _ = lua.lua_pushstring(state, "Script execution limit exceeded");
        _ = lua.lua_error(state);
    }

    /// Execute Lua script and return result
    pub fn execute(self: *Self, allocator: Allocator, script: []const u8) !ExecutionResult {
        return self.executeWithArgs(allocator, script, &.{});
    }

    /// Execute Lua script with arguments
    pub fn executeWithArgs(
        self: *Self,
        allocator: Allocator,
        script: []const u8,
        args: []const ScriptArg,
    ) !ExecutionResult {
        // Load script first (before any allocations)
        const load_result = lua.luaL_loadbufferx(
            self.state,
            script.ptr,
            script.len,
            "script",
            null,
        );

        if (load_result != lua.LUA_OK) {
            _ = lua.lua_tolstring(self.state, -1, null);
            lua.lua_pop(self.state, 1);
            return error.LuaSyntaxError;
        }

        // Create arena on heap so it survives return
        var arena_ptr = try allocator.create(std.heap.ArenaAllocator);
        arena_ptr.* = std.heap.ArenaAllocator.init(allocator);

        // Push arguments onto stack
        for (args) |arg| {
            switch (arg) {
                .number => |n| {
                    lua.lua_pushnumber(self.state, n);
                },
                .string => |s| {
                    _ = lua.lua_pushlstring(self.state, s.ptr, s.len);
                },
                .boolean => |b| {
                    lua.lua_pushboolean(self.state, if (b) 1 else 0);
                },
            }
        }

        // Execute with pcall for runtime error handling
        const nargs: c_int = @intCast(args.len);
        const nresults: c_int = 1;
        const pcall_result = lua.lua_pcallk(self.state, nargs, nresults, 0, 0, null);

        if (pcall_result != lua.LUA_OK) {
            const err_msg = lua.lua_tolstring(self.state, -1, null);
            const err_str = if (err_msg != null) std.mem.sliceTo(err_msg, 0) else "";
            lua.lua_pop(self.state, 1);

            // Clean up arena before returning error
            arena_ptr.deinit();
            allocator.destroy(arena_ptr);

            // Check if this is a timeout/limit error
            if (std.mem.indexOf(u8, err_str, "limit exceeded") != null or
                std.mem.indexOf(u8, err_str, "timeout") != null)
            {
                return error.LuaTimeoutError;
            }

            return switch (pcall_result) {
                lua.LUA_ERRMEM => error.LuaMemoryError,
                lua.LUA_ERRRUN => error.LuaRuntimeError,
                lua.LUA_ERRERR => error.LuaRuntimeError,
                else => error.LuaRuntimeError,
            };
        }

        // Extract result
        var result = ExecutionResult{
            .arena = arena_ptr,
        };

        const result_type = lua.lua_type(self.state, -1);
        result.value_type = switch (result_type) {
            lua.LUA_TNIL => .nil,
            lua.LUA_TNUMBER => .number,
            lua.LUA_TSTRING => .string,
            lua.LUA_TBOOLEAN => .boolean,
            lua.LUA_TTABLE => .table,
            lua.LUA_TFUNCTION => .table, // Treat function as complex type
            lua.LUA_TUSERDATA => .table,
            lua.LUA_TTHREAD => .table,
            else => .nil,
        };

        switch (result_type) {
            lua.LUA_TNUMBER => {
                const num = lua.lua_tonumberx(self.state, -1, null);
                // Check for valid number range before conversion
                if (num >= -2147483648.0 and num <= 2147483647.0) {
                    result.value = @intFromFloat(num);
                } else {
                    result.value = null;
                }
            },
            lua.LUA_TSTRING => {
                var len: usize = 0;
                const str_ptr = lua.lua_tolstring(self.state, -1, &len);
                if (str_ptr != null) {
                    const str_slice = arena_ptr.allocator().dupe(u8, str_ptr[0..len]) catch "";
                    result.value_string = str_slice;
                }
            },
            lua.LUA_TBOOLEAN => {
                // Boolean results stored as value
                result.value = if (lua.lua_toboolean(self.state, -1) != 0) 1 else 0;
            },
            lua.LUA_TNIL => {
                result.value = null;
            },
            else => {},
        }

        lua.lua_pop(self.state, 1);

        return result;
    }

    /// Clean up Lua VM resources
    pub fn deinit(self: *Self) void {
        // Disable hook before closing to prevent callback during cleanup
        lua.lua_sethook(self.state, null, 0, 0);
        lua.lua_close(self.state);
    }
};
