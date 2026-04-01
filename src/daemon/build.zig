const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // SQLite dependency
    const sqlite_dep = b.createModule(.{
        .root_source_file = b.path("storage/sqlite.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main daemon executable
    const daemon_exe = b.addExecutable(.{
        .name = "urutau-daemon",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Will link against libdbus and sqlite3 when implementation is complete
    daemon_exe.linkSystemLibrary("sqlite3");
    // daemon_exe.linkSystemLibrary("dbus-1");

    b.installArtifact(daemon_exe);

    // Run command
    const daemon_run = b.addRunArtifact(daemon_exe);
    if (b.args) |args| {
        daemon_run.addArgs(args);
    }

    const run_step = b.step("run", "Run the daemon");
    run_step.dependOn(&daemon_run.step);

    // Unit tests for dbus_client
    const dbus_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("dbus/dbus_client_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_dbus_test = b.addRunArtifact(dbus_test);
    const test_dbus_step = b.step("test-dbus", "Run D-Bus client tests");
    test_dbus_step.dependOn(&run_dbus_test.step);

    // Unit tests for storage/database
    const storage_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("storage/database_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    storage_test.root_module.addImport("sqlite", sqlite_dep);
    storage_test.linkSystemLibrary("sqlite3");
    storage_test.linkLibC();

    const run_storage_test = b.addRunArtifact(storage_test);
    const test_storage_step = b.step("test-storage", "Run storage layer tests");
    test_storage_step.dependOn(&run_storage_test.step);

    // All tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/all_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
