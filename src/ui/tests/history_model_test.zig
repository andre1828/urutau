//! Tests for History Data Model

const std = @import("std");
const HistoryCollection = @import("history_model").HistoryCollection;
const SelectionHandler = @import("history_model").SelectionHandler;
const SelectionAction = @import("history_model").SelectionAction;

test "HistoryCollection can be initialized and deinitialized" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try std.testing.expectEqual(@as(usize, 0), collection.count());
}

test "HistoryCollection can add items" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Hello World", "text/plain", 1234567890);
    try std.testing.expectEqual(@as(usize, 1), collection.count());
    
    const item = collection.getItem(0);
    try std.testing.expect(item != null);
    try std.testing.expectEqual(@as(u64, 1), item.?.id);
    try std.testing.expectEqualStrings("Hello World", item.?.content);
    try std.testing.expectEqualStrings("text/plain", item.?.mime_type);
}

test "HistoryCollection can clear items" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Item 1", "text/plain", 1234567890);
    try collection.addItem(2, "Item 2", "text/plain", 1234567891);
    try std.testing.expectEqual(@as(usize, 2), collection.count());
    
    collection.clear();
    try std.testing.expectEqual(@as(usize, 0), collection.count());
}

test "HistoryCollection updateCurrentClipboard marks matching item" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "First", "text/plain", 1234567890);
    try collection.addItem(2, "Second", "text/plain", 1234567891);
    
    // Mark "Second" as current clipboard
    collection.updateCurrentClipboard("Second");
    
    const item0 = collection.getItem(0);
    const item1 = collection.getItem(1);
    
    try std.testing.expect(item0 != null);
    try std.testing.expect(item1 != null);
    
    try std.testing.expectEqual(false, item0.?.is_current_clipboard);
    try std.testing.expectEqual(true, item1.?.is_current_clipboard);
}

test "HistoryCollection getItem returns null for out of bounds" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Test", "text/plain", 1234567890);
    
    try std.testing.expect(collection.getItem(1) == null);
    try std.testing.expect(collection.getItem(100) == null);
}

test "HistoryCollection filterByQuery returns all items when query is empty" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Hello World", "text/plain", 1234567890);
    try collection.addItem(2, "Foo Bar", "text/plain", 1234567891);
    try collection.addItem(3, "Test Item", "text/plain", 1234567892);
    
    var filtered = try collection.filterByQuery("", std.testing.allocator);
    defer filtered.deinit(std.testing.allocator);
    
    try std.testing.expectEqual(@as(usize, 3), filtered.items.len);
}

test "HistoryCollection filterByQuery filters by content" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Hello World", "text/plain", 1234567890);
    try collection.addItem(2, "Foo Bar", "text/plain", 1234567891);
    try collection.addItem(3, "Hello Test", "text/plain", 1234567892);
    
    var filtered = try collection.filterByQuery("Hello", std.testing.allocator);
    defer filtered.deinit(std.testing.allocator);
    
    try std.testing.expectEqual(@as(usize, 2), filtered.items.len);
    try std.testing.expectEqualStrings("Hello World", filtered.items[0].content);
    try std.testing.expectEqualStrings("Hello Test", filtered.items[1].content);
}

test "HistoryCollection filterByQuery is case-insensitive" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "HELLO World", "text/plain", 1234567890);
    try collection.addItem(2, "hello test", "text/plain", 1234567891);
    try collection.addItem(3, "Foo Bar", "text/plain", 1234567892);
    
    var filtered = try collection.filterByQuery("hello", std.testing.allocator);
    defer filtered.deinit(std.testing.allocator);
    
    try std.testing.expectEqual(@as(usize, 2), filtered.items.len);
}

test "HistoryCollection filterByQuery returns empty when no match" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Hello World", "text/plain", 1234567890);
    try collection.addItem(2, "Foo Bar", "text/plain", 1234567891);
    
    var filtered = try collection.filterByQuery("NotFound", std.testing.allocator);
    defer filtered.deinit(std.testing.allocator);
    
    try std.testing.expectEqual(@as(usize, 0), filtered.items.len);
}

// SelectionHandler tests

test "SelectionHandler can be initialized" {
    const handler = SelectionHandler.init(std.testing.allocator);
    
    try std.testing.expect(handler.selected_item == null);
    try std.testing.expectEqual(false, handler.auto_paste_enabled);
}

test "SelectionHandler selectItem sets selected item" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Test Content", "text/plain", 1234567890);
    const item = collection.getItem(0);
    try std.testing.expect(item != null);
    
    var handler = SelectionHandler.init(std.testing.allocator);
    handler.selectItem(item.?);
    
    try std.testing.expect(handler.selected_item != null);
    try std.testing.expectEqualStrings("Test Content", handler.selected_item.?.content);
}

test "SelectionHandler getAction returns restore_only when auto-paste is off" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Test", "text/plain", 1234567890);
    const item = collection.getItem(0);
    
    var handler = SelectionHandler.init(std.testing.allocator);
    handler.selectItem(item.?);
    
    const action = handler.getAction();
    try std.testing.expectEqual(SelectionAction.restore_only, action);
}

test "SelectionHandler getAction returns restore_and_paste when auto-paste is on" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Test", "text/plain", 1234567890);
    const item = collection.getItem(0);
    
    var handler = SelectionHandler.init(std.testing.allocator);
    handler.selectItem(item.?);
    handler.toggleAutoPaste();
    
    const action = handler.getAction();
    try std.testing.expectEqual(SelectionAction.restore_and_paste, action);
}

test "SelectionHandler getAction returns none when no item selected" {
    var handler = SelectionHandler.init(std.testing.allocator);
    
    const action = handler.getAction();
    try std.testing.expectEqual(SelectionAction.none, action);
}

test "SelectionHandler toggleAutoPaste toggles state" {
    var handler = SelectionHandler.init(std.testing.allocator);
    
    try std.testing.expectEqual(false, handler.auto_paste_enabled);
    
    handler.toggleAutoPaste();
    try std.testing.expectEqual(true, handler.auto_paste_enabled);
    
    handler.toggleAutoPaste();
    try std.testing.expectEqual(false, handler.auto_paste_enabled);
}

test "SelectionHandler clearSelection clears selected item" {
    var collection = HistoryCollection.init(std.testing.allocator);
    defer collection.deinit();
    
    try collection.addItem(1, "Test", "text/plain", 1234567890);
    const item = collection.getItem(0);
    
    var handler = SelectionHandler.init(std.testing.allocator);
    handler.selectItem(item.?);
    try std.testing.expect(handler.selected_item != null);
    
    handler.clearSelection();
    try std.testing.expect(handler.selected_item == null);
}
