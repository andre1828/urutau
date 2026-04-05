const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main UI executable
    const ui_exe = b.addExecutable(.{
        .name = "urutau-ui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link GTK4
    ui_exe.linkSystemLibrary("gtk4");
    ui_exe.linkLibC();

    b.installArtifact(ui_exe);

    // Run command
    const ui_run = b.addRunArtifact(ui_exe);
    if (b.args) |args| {
        ui_run.addArgs(args);
    }

    const run_step = b.step("run", "Run the UI application");
    run_step.dependOn(&ui_run.step);

    // Unit tests
    const ui_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ui_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ui_tests.linkSystemLibrary("gtk4");
    ui_tests.linkLibC();

    const run_ui_tests = b.addRunArtifact(ui_tests);
    const test_step = b.step("test", "Run UI tests");
    test_step.dependOn(&run_ui_tests.step);

    // History model module (pure logic, no GTK)
    const history_model_module = b.createModule(.{
        .root_source_file = b.path("models/history_data.zig"),
        .target = target,
        .optimize = optimize,
    });

    // History model tests (pure logic, no GTK)
    const history_model_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/history_model_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    history_model_test.root_module.addImport("history_model", history_model_module);

    const run_history_model_test = b.addRunArtifact(history_model_test);
    const test_history_model_step = b.step("test-history-model", "Run history model tests");
    test_history_model_step.dependOn(&run_history_model_test.step);
}
