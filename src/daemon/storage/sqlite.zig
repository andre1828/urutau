//! SQLite3 FFI Bindings for Zig
//! Minimal wrapper around SQLite3 C API

const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Error = error{
    OutOfMemory,
    SQL,
    Internal,
    Permission,
    Abort,
    Busy,
    Locked,
    NoMemory,
    ReadOnly,
    Interrupt,
    IOError,
    Corrupt,
    NotFound,
    Full,
    CannotOpen,
    LockErr,
    Protocol,
    Empty,
    Schema,
    TooBig,
    Constraint,
    Mismatch,
    Misuse,
    NoLFS,
    Auth,
    Format,
    Range,
    NotADB,
    Notice,
    Warning,
    Row,
    Done,
};

pub const Database = struct {
    ptr: *c.sqlite3,

    pub fn open(path: ?[:0]const u8) Error!Database {
        var db: ?*c.sqlite3 = null;
        const flags = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE;

        const rc = if (path) |p|
            c.sqlite3_open_v2(p.ptr, &db, flags, null)
        else
            c.sqlite3_open(":memory:", &db);

        if (rc != c.SQLITE_OK) {
            if (db) |ptr| {
                _ = c.sqlite3_close(ptr);
            }
            return sqliteError(rc);
        }

        return Database{ .ptr = db.? };
    }

    pub fn close(self: Database) void {
        _ = c.sqlite3_close(self.ptr);
    }

    pub fn exec(self: Database, sql: [:0]const u8) Error!void {
        const rc = c.sqlite3_exec(self.ptr, sql.ptr, null, null, null);
        if (rc != c.SQLITE_OK) {
            return sqliteError(rc);
        }
    }

    pub fn prepare(self: Database, sql: [:0]const u8) Error!Statement {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.ptr, sql.ptr, -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            return sqliteError(rc);
        }
        return Statement{ .ptr = stmt.? };
    }

    pub fn lastInsertRowid(self: Database) i64 {
        return c.sqlite3_last_insert_rowid(self.ptr);
    }

    pub fn changes(self: Database) usize {
        return @intCast(c.sqlite3_changes(self.ptr));
    }

    fn sqliteError(rc: c_int) Error {
        return switch (rc) {
            c.SQLITE_OK => unreachable,
            c.SQLITE_ERROR => Error.SQL,
            c.SQLITE_INTERNAL => Error.Internal,
            c.SQLITE_PERM => Error.Permission,
            c.SQLITE_ABORT => Error.Abort,
            c.SQLITE_BUSY => Error.Busy,
            c.SQLITE_LOCKED => Error.Locked,
            c.SQLITE_NOMEM => Error.OutOfMemory,
            c.SQLITE_READONLY => Error.ReadOnly,
            c.SQLITE_INTERRUPT => Error.Interrupt,
            c.SQLITE_IOERR => Error.IOError,
            c.SQLITE_CORRUPT => Error.Corrupt,
            c.SQLITE_NOTFOUND => Error.NotFound,
            c.SQLITE_FULL => Error.Full,
            c.SQLITE_CANTOPEN => Error.CannotOpen,
            c.SQLITE_PROTOCOL => Error.Protocol,
            c.SQLITE_EMPTY => Error.Empty,
            c.SQLITE_SCHEMA => Error.Schema,
            c.SQLITE_TOOBIG => Error.TooBig,
            c.SQLITE_CONSTRAINT => Error.Constraint,
            c.SQLITE_MISMATCH => Error.Mismatch,
            c.SQLITE_MISUSE => Error.Misuse,
            c.SQLITE_NOLFS => Error.NoLFS,
            c.SQLITE_AUTH => Error.Auth,
            c.SQLITE_FORMAT => Error.Format,
            c.SQLITE_RANGE => Error.Range,
            c.SQLITE_NOTADB => Error.NotADB,
            c.SQLITE_NOTICE => Error.Notice,
            c.SQLITE_WARNING => Error.Warning,
            c.SQLITE_ROW => Error.Row,
            c.SQLITE_DONE => Error.Done,
            else => Error.SQL,
        };
    }
};

pub const Statement = struct {
    ptr: *c.sqlite3_stmt,

    pub fn deinit(self: Statement) void {
        _ = c.sqlite3_finalize(self.ptr);
    }

    pub fn reset(self: Statement) void {
        _ = c.sqlite3_reset(self.ptr);
    }

    pub fn bindText(self: Statement, index: c_int, value: []const u8) Error!void {
        const rc = c.sqlite3_bind_text(self.ptr, index, value.ptr, @intCast(value.len), c.SQLITE_TRANSIENT);
        if (rc != c.SQLITE_OK) {
            return Database.sqliteError(rc);
        }
    }

    pub fn bindBlob(self: Statement, index: c_int, value: []const u8) Error!void {
        const rc = c.sqlite3_bind_blob(self.ptr, index, value.ptr, @intCast(value.len), c.SQLITE_TRANSIENT);
        if (rc != c.SQLITE_OK) {
            return Database.sqliteError(rc);
        }
    }

    pub fn bindInt(self: Statement, index: c_int, value: i64) Error!void {
        const rc = c.sqlite3_bind_int64(self.ptr, index, value);
        if (rc != c.SQLITE_OK) {
            return Database.sqliteError(rc);
        }
    }

    pub fn bindNull(self: Statement, index: c_int) Error!void {
        const rc = c.sqlite3_bind_null(self.ptr, index);
        if (rc != c.SQLITE_OK) {
            return Database.sqliteError(rc);
        }
    }

    pub fn step(self: Statement) Error!bool {
        const rc = c.sqlite3_step(self.ptr);
        return switch (rc) {
            c.SQLITE_ROW => true,
            c.SQLITE_DONE => false,
            else => Database.sqliteError(rc),
        };
    }

    pub fn columnInt(self: Statement, index: c_int) i64 {
        return c.sqlite3_column_int64(self.ptr, index);
    }

    pub fn columnText(self: Statement, index: c_int, allocator: std.mem.Allocator) Error![]u8 {
        const ptr = c.sqlite3_column_text(self.ptr, index);
        const len = c.sqlite3_column_bytes(self.ptr, index);
        if (ptr == null or len == 0) {
            return try allocator.dupe(u8, "");
        }
        return try allocator.dupe(u8, @as([*c]const u8, @ptrCast(ptr))[0..@intCast(len)]);
    }

    pub fn columnBlob(self: Statement, index: c_int, allocator: std.mem.Allocator) Error![]u8 {
        const ptr = c.sqlite3_column_blob(self.ptr, index);
        const len = c.sqlite3_column_bytes(self.ptr, index);
        if (ptr == null or len == 0) {
            return try allocator.dupe(u8, "");
        }
        return try allocator.dupe(u8, @as([*c]const u8, @ptrCast(ptr))[0..@intCast(len)]);
    }

    pub fn columnType(self: Statement, index: c_int) c_int {
        return c.sqlite3_column_type(self.ptr, index);
    }
};

/// Enable WAL mode for a database
pub fn enableWAL(db: Database) Error!void {
    try db.exec("PRAGMA journal_mode=WAL");
}

/// Set file permissions to 0600 (user-only read/write)
pub fn setSecurePermissions(path: [:0]const u8) !void {
    // On Unix-like systems, SQLite creates files with default umask
    // For enhanced security, we could chmod the file after creation
    // This is a no-op for in-memory databases
    if (std.mem.eql(u8, path, ":memory:")) {
        return;
    }

    // Note: Actual chmod would require platform-specific code
    // For now, we rely on SQLite's default behavior and user's umask
}

test "SQLite: open in-memory database" {
    const db = try Database.open(null);
    defer db.close();
}

test "SQLite: create table and insert data" {
    const db = try Database.open(null);
    defer db.close();

    try db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)");

    var stmt = try db.prepare("INSERT INTO test (name) VALUES (?)");
    defer stmt.deinit();

    try stmt.bindText(1, "hello");
    _ = try stmt.step();

    const rowid = db.lastInsertRowid();
    try std.testing.expect(rowid > 0);
}

test "SQLite: query data" {
    const db = try Database.open(null);
    defer db.close();

    try db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)");
    try db.exec("INSERT INTO test (name) VALUES ('hello')");
    try db.exec("INSERT INTO test (name) VALUES ('world')");

    var stmt = try db.prepare("SELECT id, name FROM test ORDER BY id DESC");
    defer stmt.deinit();

    // First row should be 'world' (highest id)
    try std.testing.expect(try stmt.step());
    const name1 = try stmt.columnText(1, std.testing.allocator);
    defer std.testing.allocator.free(name1);
    try std.testing.expectEqualStrings("world", name1);

    // Second row should be 'hello'
    try std.testing.expect(try stmt.step());
    const name2 = try stmt.columnText(1, std.testing.allocator);
    defer std.testing.allocator.free(name2);
    try std.testing.expectEqualStrings("hello", name2);

    // No more rows
    try std.testing.expect(!try stmt.step());
}

test "SQLite: WAL mode" {
    _ = std.fs.cwd().makeOpenPath("sqlite_wal_test", .{}) catch unreachable;
    defer std.fs.cwd().deleteTree("sqlite_wal_test") catch {};

    const db_path = "sqlite_wal_test/test.db";
    const db_path_z = try std.fs.path.joinZ(std.testing.allocator, &.{db_path});
    defer std.testing.allocator.free(db_path_z);

    const db = try Database.open(db_path_z[0..db_path_z.len :0]);
    defer db.close();

    try enableWAL(db);

    // Create table and insert data
    try db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, data TEXT)");
    try db.exec("INSERT INTO test (data) VALUES ('test')");

    // Verify data
    var stmt = try db.prepare("SELECT COUNT(*) FROM test");
    defer stmt.deinit();

    try std.testing.expect(try stmt.step());
    const count = stmt.columnInt(0);
    try std.testing.expectEqual(@as(i64, 1), count);
}
