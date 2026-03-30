# Zig Language Reference (0.15.2)

Quick reference for Zig development in this project.

---

## 1. Syntax

### Variables
```zig
const x = 1234;          // Immutable
var y: i32 = 5678;       // Mutable
var z: i32 = undefined;  // Uninitialized
```

### Primitive Types
| Type | Description |
|------|-------------|
| `i8`-`i128`, `u8`-`u128` | Signed/unsigned integers |
| `isize`, `usize` | Pointer-sized integers |
| `f32`, `f64` | Floating point |
| `bool` | true/false |
| `void` | Zero-bit type |
| `anyopaque` | Type-erased pointers |

### Operators
| Operator | Description |
|----------|-------------|
| `+`, `-`, `*`, `/` | Arithmetic (can overflow) |
| `+%`, `-%`, `*%` | Wrapping arithmetic |
| `&`, `|`, `^`, `~` | Bitwise |
| `<<`, `>>` | Bit shifts |
| `orelse` | Optional unwrap with default |
| `catch` | Error unwrap with default |
| `try` | Error propagation |

---

## 2. Built-in Functions

### Import & Compilation
```zig
@import("std")           // Import Zig module
@cImport("header")       // Import C header
@cInclude("header")      // Include C header
@compileError("msg")     // Trigger compile error
```

### Type Operations
```zig
@as(Type, value)         // Cast to type
@TypeOf(value)           // Get type of value
@typeInfo(Type)          // Get type information
@sizeOf(Type)            // Get size in bytes
@ptrFromInt(addr)        // Integer to pointer
@intFromPtr(ptr)         // Pointer to integer
@bitCast(value)          // Reinterpret bits
```

### Memory
```zig
@memcpy(dest, src)       // Copy memory
@memset(ptr, value, len) // Set memory
```

### Math
```zig
@min(a, b)               // Minimum
@max(a, b)               // Maximum
@sqrt(x)                 // Square root
```

---

## 3. Error Handling

### Error Sets
```zig
const MyError = error{
    FileNotFound,
    PermissionDenied,
};
```

### Error Unions
```zig
fn readFile() ![]const u8 {
    // Can return value or error
}

// Handle errors
const result = try readFile();           // Propagate on error
const value = readFile() catch default;  // Default on error
const value = readFile() catch |err| {   // Handle specific error
    if (err == error.FileNotFound) return default;
    return err;
};
```

### Error Cleanup
```zig
errdefer cleanup();  // Only runs if function returns error
```

---

## 4. Generics (Compile-Time)

### Generic Functions
```zig
fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}
```

### Generic Structs
```zig
fn LinkedList(comptime T: type) type {
    return struct {
        pub const Node = struct {
            data: T,
            next: ?*Node,
        };
        first: ?*Node,
        len: usize,
    };
}

const IntList = LinkedList(i32);
```

### Compile-Time Code
```zig
comptime {
    // Executed at compile-time
}

comptime var counter: i32 = 0;

inline for (.{ 1, 2, 3 }) |i| {
    // Unrolled at compile-time
}
```

---

## 5. Memory Management

### Allocators
```zig
const std = @import("std");

// General purpose allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer gpa.deinit();
const allocator = gpa.allocator();

// Allocate
const ptr = try allocator.create(i32);
defer allocator.destroy(ptr);

const slice = try allocator.alloc(u8, 100);
defer allocator.free(slice);

// Testing allocator (detects leaks)
const allocator = std.testing.allocator;
```

### Pointer Types
```zig
const ptr: *i32 = &value;        // Single-item pointer
const ptr: [*]i32 = array;       // Many-item pointer
const ptr: ?*i32 = null;         // Optional pointer
const ptr: *const i32 = &value;  // Const pointer
```

### Slices
```zig
const slice = array[start..end];  // Create slice
const len = slice.len;            // Length
const ptr = slice.ptr;            // Pointer to data
```

---

## 6. Control Flow

### if/else
```zig
if (condition) { } else { }
if (optional) |value| { }       // Unwrap optional
if (result) |value| { } catch |err| { }  // Unwrap error union
```

### while
```zig
while (condition) { }
while (condition) : (increment) { }
while (optional) |value| { }
```

### for
```zig
for (array) |item| { }
for (array, 0..) |item, index| { }
```

### switch
```zig
switch (value) {
    1 => { },
    2, 3 => { },
    else => { },
}
```

### defer
```zig
defer cleanup();           // Execute at scope end
errdefer cleanup();        // Execute on error return
```

---

## 7. Data Structures

### Struct
```zig
const Point = struct {
    x: f32,
    y: f32,
    
    pub fn init(x: f32, y: f32) Point {
        return .{ .x = x, .y = y };
    }
};
```

### Enum
```zig
const Color = enum { red, green, blue };
```

### Union
```zig
const Value = union {
    int: i32,
    float: f32,
};

// Tagged Union
const Value = union(enum) {
    int: i32,
    float: f32,
};
```

### Array
```zig
const arr = [_]i32{ 1, 2, 3 };  // Inferred length
const fixed: [3]i32 = .{ 1, 2, 3 };
```

---

## 8. Testing

### Basic Test
```zig
test "addition" {
    try std.testing.expectEqual(4, 2 + 2);
}
```

### Test with Allocator
```zig
test "allocation" {
    const allocator = std.testing.allocator;
    const ptr = try allocator.create(i32);
    defer allocator.destroy(ptr);
}
```

### Error Testing
```zig
test "error handling" {
    try std.testing.expectError(error.SomeError, result);
}
```

### String Testing
```zig
test "strings" {
    try std.testing.expectEqualStrings("expected", actual);
}
```

---

## 9. Build System

### build.zig Template
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = .{ .path = "main.zig" },
            .target = target,
            .optimize = optimize,
        }),
    });
    
    b.installArtifact(exe);
    
    // Tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = .{ .path = "tests.zig" },
            .target = target,
            .optimize = optimize,
        }),
    });
    
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
```

---

## 10. C Interop

### Import C
```zig
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("dbus/dbus.h");
});
```

### Export to C
```zig
export fn myFunction() void {
    // Callable from C
}
```

---

## 11. Common Patterns

### Resource Cleanup
```zig
fn process() !void {
    const resource = try acquire();
    defer release(resource);
    // ... use resource
}
```

### Error Propagation
```zig
fn caller() !void {
    try callee();  // Returns early on error
}
```

### Optional Pattern
```zig
const value: ?i32 = null;
if (value) |v| { /* v is i32 */ }
const result = value orelse 0;
```

### String Handling
```zig
const str: []const u8 = "hello";  // UTF-8 slice
std.debug.print("Value: {}\n", .{value});
std.debug.print("String: {s}\n", .{"hello"});
```

---

## 12. Project Conventions (Urutau)

### File Naming
- Zig files: `kebab_case.zig`
- Test files: `*_test.zig`

### Error Handling
- Use error unions (`!T`) for fallible operations
- Use `try` for propagation, `catch` for recovery
- Always clean up resources with `defer`/`errdefer`

### Memory
- Use `std.testing.allocator` in tests
- Always pair `alloc` with `free`, `create` with `destroy`
- Document ownership of allocated memory

### D-Bus Integration
- Use `dbus_client.zig` for all D-Bus communication
- Handle `error.NotConnected` gracefully
- Implement exponential backoff for reconnection

---

**Key Principles:**
1. **Explicit over implicit** - No hidden allocations
2. **Compile-time execution** - Maximize comptime work
3. **Safety first** - Bounds checking in Debug/ReleaseSafe
4. **No hidden control flow** - All errors explicit
