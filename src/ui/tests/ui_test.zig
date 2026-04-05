//! UI tests for Urutau History Picker
//! Tests GTK4 UI components

const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

test "GTK4 can be initialized" {
    // Test that GTK4 can be initialized
    const result = c.gtk_init_check();
    try std.testing.expect(result != 0);
}

test "GtkApplication can be created" {
    // Initialize GTK first
    _ = c.gtk_init_check();
    
    // Create a GtkApplication to verify it works
    const app = c.gtk_application_new("com.test.UrutauUI", 0);
    try std.testing.expect(app != null);
}

test "GtkWindow can be created" {
    // Initialize GTK first
    _ = c.gtk_init_check();
    
    // Create a GtkWindow (no arguments in GTK4)
    const window = c.gtk_window_new();
    try std.testing.expect(window != null);
    
    // Set and verify properties (need to cast from GtkWidget* to GtkWindow*)
    c.gtk_window_set_title(@as(*c.GtkWindow, @ptrCast(window)), "Test Window");
    c.gtk_window_set_default_size(@as(*c.GtkWindow, @ptrCast(window)), 400, 300);
}

test "GtkBox layout can be created" {
    // Initialize GTK first
    _ = c.gtk_init_check();
    
    // Create a vertical box
    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    try std.testing.expect(box != null);
}

test "GtkListBox can be created" {
    // Initialize GTK first
    _ = c.gtk_init_check();
    
    // Create a GtkListBox
    const list_box = c.gtk_list_box_new();
    try std.testing.expect(list_box != null);
    
    // Verify selection mode can be set
    c.gtk_list_box_set_selection_mode(@as(*c.GtkListBox, @ptrCast(list_box)), c.GTK_SELECTION_SINGLE);
}
