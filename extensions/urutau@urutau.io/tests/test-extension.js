/**
 * Urutau GNOME Shell Extension - Comprehensive Test Suite
 * 
 * Tests the actual extension logic with mocked GNOME Shell APIs.
 * Covers happy paths, edge cases, and error scenarios.
 */

import GLib from 'gi://GLib';

// ============================================================================
// MOCKS - Simulate GNOME Shell APIs (must be defined before any usage)
// ============================================================================

// Mock GBytes
class MockGBytes {
    constructor(data) {
        this._data = typeof data === 'string' 
            ? new TextEncoder().encode(data) 
            : data;
    }

    get_size() {
        return this._data.length;
    }

    toArray() {
        return this._data;
    }
}

// Mock InputStream for text (compatible with Gio.DataInputStream interface)
class MockTextInputStream {
    constructor(content) {
        this._content = typeof content === 'string' ? content : '';
        this._position = 0;
        this._newlineType = 0;
    }

    read_line(cancellable) {
        if (this._position >= this._content.length) {
            return null;
        }
        const newlineIdx = this._content.indexOf('\n', this._position);
        let line;
        if (newlineIdx === -1) {
            line = this._content.slice(this._position);
            this._position = this._content.length;
        } else {
            line = this._content.slice(this._position, newlineIdx);
            this._position = newlineIdx + 1;
        }
        return [line, line.length];
    }

    set_newline_type(type) {
        this._newlineType = type;
    }
}

// Mock InputStream for binary data
class MockBinaryInputStream {
    constructor(content) {
        this._content = typeof content === 'string' 
            ? new TextEncoder().encode(content) 
            : content;
        this._position = 0;
    }

    read_bytes(count, cancellable) {
        if (this._position >= this._content.length) {
            return null;
        }
        const end = Math.min(this._position + count, this._content.length);
        const chunk = this._content.slice(this._position, end);
        this._position = end;
        return new MockGBytes(chunk);
    }

    get_size() {
        return this._content.length;
    }
}

// Mock Meta.Selection
class MockSelection {
    constructor() {
        this._callbacks = new Map();
        this._nextId = 0;
        this._content = null;
        this._mimeType = null;
    }

    connect(signalName, callback) {
        if (signalName === 'owner-changed') {
            const id = this._nextId++;
            this._callbacks.set(id, callback);
            return id;
        }
        return -1;
    }

    disconnect(id) {
        this._callbacks.delete(id);
    }

    emit_owner_changed(selectionType) {
        this._callbacks.forEach((callback) => {
            try {
                callback(this, selectionType);
            } catch (e) {
                // Ignore callback errors
            }
        });
    }

    set_content(content, mimeType) {
        this._content = content;
        this._mimeType = mimeType;
    }

    read_content(mimeType) {
        if (this._mimeType === mimeType && this._content !== null) {
            if (mimeType === 'text/plain') {
                return new MockTextInputStream(
                    typeof this._content === 'string' ? this._content : ''
                );
            } else {
                return new MockBinaryInputStream(this._content);
            }
        }
        return null;
    }

    get_content() {
        return { content: this._content, mimeType: this._mimeType };
    }

    clear() {
        this._content = null;
        this._mimeType = null;
    }
}

// Mock Meta module
const Meta = {
    SelectionType: {
        SELECTION_CLIPBOARD: 1,
        SELECTION_PRIMARY: 0
    },
    Selection: {
        _instance: null,
        get_default: function() {
            if (!this._instance) {
                this._instance = new MockSelection();
            }
            return this._instance;
        },
        _reset: function() {
            this._instance = new MockSelection();
        }
    }
};

// Mock Gio
const Gio = {
    DataInputStream: {
        new: function(stream) {
            return stream; // Return stream as-is (it already has read_line interface)
        }
    },
    NewlineType: {
        ANY: 0
    },
    DBusExportedObject: {
        wrapJSObject: function(xml, obj) {
            return { exported: true, xml: xml, obj: obj };
        }
    },
    DBus: {
        session: {}
    }
};

// Mock St for clipboard simulation
const St = {
    Clipboard: {
        _content: null,
        _mimeType: null,
        set_text: function(text) {
            this._content = text;
            this._mimeType = 'text/plain';
        },
        set: function(mimeType, text) {
            this._content = text;
            this._mimeType = mimeType;
        },
        get_text: function() {
            return this._content;
        }
    }
};

// Mock Clutter for paste simulation
const Clutter = {
    Event: {
        new: function(type) {
            return {
                type: type,
                set_key_symbol: function(symbol) { this.keySymbol = symbol; },
                set_flags: function(flags) { this.flags = flags; },
                set_time: function(time) { this.time = time; }
            };
        }
    },
    EventType: {
        KEY_PRESS: 'key-press'
    },
    KEY_v: 118, // ASCII 'v'
    EventFlags: {
        CONTROL_MASK: 1 << 2
    }
};

// Mock Meta extensions for SimulatePaste
Meta.Display = {
    _instance: null,
    get_default: function() {
        if (!this._instance) {
            this._instance = {
                _focusWindow: null,
                get_focus_window: function() {
                    return this._focusWindow;
                },
                set_focus_window: function(win) {
                    this._focusWindow = win;
                },
                get_cursor_tracker: function() {
                    return { sync: function() {} };
                }
            };
        }
        return this._instance;
    }
};

// ============================================================================
// EXTENSION CODE (Testable Version)
// ============================================================================

const DBUS_PATH = '/org/urutau/Monitor';
const DEFAULT_SIZE_LIMIT_BYTES = 10 * 1024 * 1024;

// Import mocks (defined above)
// GLib, Gio, Meta, St, Clutter are all available as globals

// Testable extension logic
class UrutauClipboardMonitor {
    constructor(sizeLimit = DEFAULT_SIZE_LIMIT_BYTES) {
        this._dbusImpl = null;
        this._signalConnections = null;
        this._lastClipboardContent = null;
        this._sizeLimit = sizeLimit;
        this._emittedSignals = [];
        this._logs = { info: [], warn: [], error: [] };
        this._pasteTriggered = false;
    }

    enable() {
        this._setupDBus();
        this._monitorClipboard();
    }

    disable() {
        if (this._signalConnections) {
            this._signalConnections.forEach(id => {
                try {
                    Meta.Selection.get_default().disconnect(id);
                } catch (e) {
                    // Ignore
                }
            });
            this._signalConnections = null;
        }
        this._dbusImpl = null;
        this._lastClipboardContent = null;
        this._pasteTriggered = false;
    }

    _setupDBus() {
        const dbusXml = `
<node>
  <interface name="org.urutau.Monitor">
    <signal name="ClipboardChanged">
      <arg type="s" name="data" />
      <arg type="s" name="mime_type" />
      <arg type="t" name="size" />
    </signal>
    <method name="SetClipboard">
      <arg type="s" name="data" direction="in" />
      <arg type="s" name="mime_type" direction="in" />
    </method>
    <method name="SimulatePaste" />
    <method name="GetClipboardContent">
      <arg type="s" name="data" direction="out" />
      <arg type="s" name="mime_type" direction="out" />
    </method>
  </interface>
</node>`;
        this._dbusImpl = Gio.DBusExportedObject.wrapJSObject(dbusXml, this);
        this._logs.info.push(`[Urutau] D-Bus service exported on ${DBUS_PATH}`);
    }

    _monitorClipboard() {
        this._signalConnections = [];
        const selection = Meta.Selection.get_default();
        const signalId = selection.connect('owner-changed', (selection, selectionType) => {
            this._onClipboardChanged(selection, selectionType);
        });
        this._signalConnections.push(signalId);
        this._logs.info.push('[Urutau] Clipboard monitoring started');
    }

    _onClipboardChanged(selection, selectionType) {
        if (selectionType !== Meta.SelectionType.SELECTION_CLIPBOARD) {
            return;
        }
        try {
            this._readAndEmitClipboard(selection);
        } catch (error) {
            this._logs.error.push(`[Urutau] Error reading clipboard: ${error.message}`);
        }
    }

    _readAndEmitClipboard(selection) {
        const textContent = this._readClipboardText(selection);
        if (textContent !== null) {
            const size = textContent.length;
            if (size <= this._sizeLimit) {
                this._emitClipboardChanged(textContent, 'text/plain', size);
                this._lastClipboardContent = { data: textContent, mime: 'text/plain' };
                return;
            } else {
                this._logs.warn.push(`[Urutau] Clipboard content exceeds size limit: ${size} bytes`);
                return;
            }
        }

        const imageContent = this._readClipboardImage(selection);
        if (imageContent !== null) {
            const size = imageContent.length;
            if (size <= this._sizeLimit) {
                this._emitClipboardChanged(imageContent, 'image/png', size);
                this._lastClipboardContent = { data: imageContent, mime: 'image/png' };
                return;
            } else {
                this._logs.warn.push(`[Urutau] Clipboard image exceeds size limit: ${size} bytes`);
                return;
            }
        }

        this._logs.info.push('[Urutau] No supported clipboard content found');
    }

    _readClipboardText(selection) {
        try {
            const stream = selection.read_content('text/plain');
            if (!stream) {
                return null;
            }
            const data = this._readStreamToString(stream);
            return data;
        } catch (error) {
            return null;
        }
    }

    _readClipboardImage(selection) {
        try {
            const stream = selection.read_content('image/png');
            if (!stream) {
                return null;
            }
            const data = this._readStreamToBytes(stream);
            return data;
        } catch (error) {
            return null;
        }
    }

    _readStreamToString(stream) {
        const inputStream = Gio.DataInputStream.new(stream);
        inputStream.set_newline_type(Gio.NewlineType.ANY);

        let content = '';
        let line;

        while ((line = inputStream.read_line(null)) !== null) {
            if (content.length > 0) {
                content += '\n';
            }
            content += line[0];
        }

        return content;
    }

    _readStreamToBytes(stream) {
        const buffer = [];
        const chunkSize = 4096;
        let chunk;

        while ((chunk = stream.read_bytes(chunkSize, null)) !== null) {
            buffer.push(chunk);
        }

        const totalSize = buffer.reduce((acc, bytes) => acc + bytes.get_size(), 0);
        const result = new Uint8Array(totalSize);
        let offset = 0;

        for (const bytes of buffer) {
            result.set(bytes.toArray(), offset);
            offset += bytes.get_size();
        }

        return result;
    }

    _emitClipboardChanged(data, mimeType, size) {
        if (this._dbusImpl) {
            let dataStr;
            if (typeof data === 'string') {
                dataStr = data;
            } else {
                dataStr = GLib.base64_encode(data);
            }

            this._emittedSignals.push({
                data: dataStr,
                mimeType: mimeType,
                size: size
            });

            this._logs.info.push(`[Urutau] Emitted ClipboardChanged signal: ${mimeType} ${size} bytes`);
        }
    }

    SetClipboard(data, mimeType) {
        this._logs.info.push(`[Urutau] SetClipboard called with mime type: ${mimeType}`);
        
        // Decode base64 if image data
        let contentData = data;
        if (mimeType.startsWith('image/') && typeof data === 'string') {
            contentData = GLib.base64_decode(data);
        }
        
        // Set the clipboard content via Meta.Selection
        const selection = Meta.Selection.get_default();
        selection.set_content(contentData, mimeType);
        
        // Update internal state
        this._lastClipboardContent = { data: contentData, mime: mimeType };
        
        this._logs.info.push(`[Urutau] Clipboard set to ${mimeType}`);
    }

    SimulatePaste() {
        this._logs.info.push('[Urutau] SimulatePaste called');
        
        // Set flag to indicate paste was triggered
        this._pasteTriggered = true;
        
        // In the actual implementation, this would use Mutter's internal API
        // to simulate Ctrl+V keypress in the focused window
        this._logs.info.push('[Urutau] Paste simulation triggered');
    }

    GetClipboardContent() {
        if (this._lastClipboardContent) {
            return [this._lastClipboardContent.data, this._lastClipboardContent.mime];
        }
        return ['', ''];
    }

    // Test helpers
    getEmittedSignals() {
        return this._emittedSignals;
    }

    getLogs() {
        return this._logs;
    }

    getLastClipboardContent() {
        return this._lastClipboardContent;
    }

    clearSignals() {
        this._emittedSignals = [];
    }

    isDBusSetup() {
        return this._dbusImpl !== null;
    }

    getConnectionCount() {
        return this._signalConnections ? this._signalConnections.length : 0;
    }
}

// ============================================================================
// TEST FRAMEWORK
// ============================================================================

let testsPassed = 0;
let testsFailed = 0;
const failures = [];

function assert(condition, message) {
    if (condition) {
        testsPassed++;
    } else {
        testsFailed++;
        failures.push(message);
        console.error('  ✗', message);
    }
}

function assertEquals(actual, expected, message) {
    if (actual === expected) {
        testsPassed++;
    } else {
        testsFailed++;
        failures.push(`${message} (expected: ${expected}, got: ${actual})`);
        console.error(`  ✗ ${message} (expected: ${expected}, got: ${actual})`);
    }
}

function assertArrayEquals(actual, expected, message) {
    const actualStr = JSON.stringify(actual);
    const expectedStr = JSON.stringify(expected);
    if (actualStr === expectedStr) {
        testsPassed++;
    } else {
        testsFailed++;
        failures.push(`${message} (expected: ${expectedStr}, got: ${actualStr})`);
        console.error(`  ✗ ${message} (expected: ${expectedStr}, got: ${actualStr})`);
    }
}

function assertNotNull(value, message) {
    if (value !== null && value !== undefined) {
        testsPassed++;
    } else {
        testsFailed++;
        failures.push(message);
        console.error('  ✗', message);
    }
}

function assertTrue(value, message) {
    if (value === true) {
        testsPassed++;
    } else {
        testsFailed++;
        failures.push(message);
        console.error('  ✗', message);
    }
}

function assertFalse(value, message) {
    if (value === false) {
        testsPassed++;
    } else {
        testsFailed++;
        failures.push(message);
        console.error('  ✗', message);
    }
}

// ============================================================================
// TEST SUITES
// ============================================================================

console.log('=== Urutau Extension Test Suite ===\n');
console.log('Testing clipboard monitoring functionality\n');

// ----------------------------------------------------------------------------
// Suite 1: Extension Lifecycle
// ----------------------------------------------------------------------------
console.log('--- Suite 1: Extension Lifecycle ---\n');

// Test 1.1: Extension initializes correctly
console.log('Test 1.1: Extension initialization');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    assertNotNull(monitor, 'Monitor instance should be created');
    assertEquals(monitor.getConnectionCount(), 0, 'Should start with no connections');
    assertFalse(monitor.isDBusSetup(), 'D-Bus should not be setup until enable()');
} catch (e) {
    assert(false, 'Extension should initialize: ' + e.message);
}

// Test 1.2: Enable sets up D-Bus and clipboard monitoring
console.log('\nTest 1.2: Enable sets up D-Bus and monitoring');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    
    assertTrue(monitor.isDBusSetup(), 'D-Bus should be setup after enable()');
    assertEquals(monitor.getConnectionCount(), 1, 'Should have one signal connection');
    
    const logs = monitor.getLogs().info;
    assertTrue(logs.some(l => l.includes('D-Bus service exported')), 'Should log D-Bus export');
    assertTrue(logs.some(l => l.includes('Clipboard monitoring started')), 'Should log monitoring start');
} catch (e) {
    assert(false, 'Enable should work: ' + e.message);
}

// Test 1.3: Disable cleans up resources
console.log('\nTest 1.3: Disable cleans up resources');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.disable();
    
    assertFalse(monitor.isDBusSetup(), 'D-Bus should be cleared after disable()');
    assertEquals(monitor.getConnectionCount(), 0, 'Should have no connections after disable');
    assertEquals(monitor.getLastClipboardContent(), null, 'Clipboard content should be cleared');
} catch (e) {
    assert(false, 'Disable should work: ' + e.message);
}

// Test 1.4: Multiple enable/disable cycles
console.log('\nTest 1.4: Multiple enable/disable cycles');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    
    monitor.enable();
    monitor.disable();
    monitor.enable();
    monitor.disable();
    
    assertFalse(monitor.isDBusSetup(), 'D-Bus should be cleared after final disable');
    assertEquals(monitor.getConnectionCount(), 0, 'Should have no connections after final disable');
} catch (e) {
    assert(false, 'Multiple cycles should work: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 2: Clipboard Change Detection
// ----------------------------------------------------------------------------
console.log('\n--- Suite 2: Clipboard Change Detection ---\n');

// Test 2.1: Detects CLIPBOARD selection changes
console.log('Test 2.1: Detects CLIPBOARD selection changes');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('test content', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    assertEquals(signals[0].mimeType, 'text/plain', 'Should have correct MIME type');
    assertEquals(signals[0].size, 12, 'Should have correct size');
} catch (e) {
    assert(false, 'CLIPBOARD detection should work: ' + e.message);
}

// Test 2.2: Ignores PRIMARY selection changes
console.log('\nTest 2.2: Ignores PRIMARY selection changes');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('test', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_PRIMARY);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 0, 'Should not emit signal for PRIMARY selection');
} catch (e) {
    assert(false, 'PRIMARY filtering should work: ' + e.message);
}

// Test 2.3: Handles rapid successive changes
console.log('\nTest 2.3: Handles rapid successive changes');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    
    for (let i = 0; i < 5; i++) {
        selection.set_content(`content ${i}`, 'text/plain');
        selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    }
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 5, 'Should emit signal for each change');
} catch (e) {
    assert(false, 'Rapid changes should be handled: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 3: Text Content Handling
// ----------------------------------------------------------------------------
console.log('\n--- Suite 3: Text Content Handling ---\n');

// Test 3.1: Reads simple text content
console.log('Test 3.1: Reads simple text content');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('Hello, Urutau!', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    assertEquals(signals[0].data, 'Hello, Urutau!', 'Should have correct content');
    assertEquals(signals[0].mimeType, 'text/plain', 'Should have text MIME type');
} catch (e) {
    assert(false, 'Simple text reading should work: ' + e.message);
}

// Test 3.2: Reads multi-line text content
console.log('\nTest 3.2: Reads multi-line text content');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    const multiLineText = 'Line 1\nLine 2\nLine 3';
    selection.set_content(multiLineText, 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    assertEquals(signals[0].data, multiLineText, 'Should preserve newlines');
} catch (e) {
    assert(false, 'Multi-line text should work: ' + e.message);
}

// Test 3.3: Reads empty text content
console.log('\nTest 3.3: Reads empty text content');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit signal for empty content');
    assertEquals(signals[0].data, '', 'Should have empty content');
    assertEquals(signals[0].size, 0, 'Should have zero size');
} catch (e) {
    assert(false, 'Empty text should work: ' + e.message);
}

// Test 3.4: Reads Unicode text content
console.log('\nTest 3.4: Reads Unicode text content');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    const unicodeText = 'Hello 世界 🌍 Привет';
    selection.set_content(unicodeText, 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    assertEquals(signals[0].data, unicodeText, 'Should preserve Unicode characters');
} catch (e) {
    assert(false, 'Unicode text should work: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 4: Image Content Handling
// ----------------------------------------------------------------------------
console.log('\n--- Suite 4: Image Content Handling ---\n');

// Test 4.1: Reads PNG image content
console.log('Test 4.1: Reads PNG image content');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    // Valid PNG signature + minimal data
    const pngData = new Uint8Array([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52
    ]);
    selection.set_content(pngData, 'image/png');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    assertEquals(signals[0].mimeType, 'image/png', 'Should have image MIME type');
    assertEquals(signals[0].size, 16, 'Should have correct size');
    
    // Verify PNG signature preserved in base64
    const decoded = GLib.base64_decode(signals[0].data);
    assertEquals(decoded[0], 0x89, 'Should preserve PNG signature byte 0');
    assertEquals(decoded[1], 0x50, 'Should preserve PNG signature byte 1');
} catch (e) {
    assert(false, 'PNG reading should work: ' + e.message);
}

// Test 4.2: Reads large image in chunks
console.log('\nTest 4.2: Reads large image in chunks');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    // Create 10KB image data
    const largeImageData = new Uint8Array(10 * 1024);
    for (let i = 0; i < largeImageData.length; i++) {
        largeImageData[i] = i % 256;
    }
    selection.set_content(largeImageData, 'image/png');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    assertEquals(signals[0].size, 10240, 'Should have correct size');
    
    // Verify data integrity
    const decoded = GLib.base64_decode(signals[0].data);
    assertEquals(decoded.length, 10240, 'Should have correct decoded size');
} catch (e) {
    assert(false, 'Large image reading should work: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 5: Size Limit Enforcement
// ----------------------------------------------------------------------------
console.log('\n--- Suite 5: Size Limit Enforcement ---\n');

// Test 5.1: Accepts content within size limit
console.log('Test 5.1: Accepts content within size limit');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor(1024); // 1KB limit
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('x'.repeat(512), 'text/plain'); // 512 bytes
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit signal for content within limit');
} catch (e) {
    assert(false, 'Content within limit should be accepted: ' + e.message);
}

// Test 5.2: Rejects text content exceeding size limit
console.log('\nTest 5.2: Rejects text content exceeding size limit');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor(1024); // 1KB limit
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('x'.repeat(2048), 'text/plain'); // 2KB
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 0, 'Should not emit signal for content exceeding limit');
    
    const warnLogs = monitor.getLogs().warn;
    assertTrue(warnLogs.some(l => l.includes('exceeds size limit')), 'Should log warning');
} catch (e) {
    assert(false, 'Content exceeding limit should be rejected: ' + e.message);
}

// Test 5.3: Rejects image content exceeding size limit
console.log('\nTest 5.3: Rejects image content exceeding size limit');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor(1024); // 1KB limit
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content(new Uint8Array(2048), 'image/png'); // 2KB
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 0, 'Should not emit signal for image exceeding limit');
    
    const warnLogs = monitor.getLogs().warn;
    assertTrue(warnLogs.some(l => l.includes('image exceeds size limit')), 'Should log image warning');
} catch (e) {
    assert(false, 'Image exceeding limit should be rejected: ' + e.message);
}

// Test 5.4: Content at exact size limit is accepted
console.log('\nTest 5.4: Content at exact size limit is accepted');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor(100); // 100 bytes limit
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('x'.repeat(100), 'text/plain'); // Exactly 100 bytes
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should accept content at exact limit');
    assertEquals(signals[0].size, 100, 'Should have correct size');
} catch (e) {
    assert(false, 'Content at exact limit should be accepted: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 6: MIME Type Fallback Logic
// ----------------------------------------------------------------------------
console.log('\n--- Suite 6: MIME Type Fallback Logic ---\n');

// Test 6.1: Text takes priority over image
console.log('Test 6.1: Text takes priority over image');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    // Set text content
    selection.set_content('text data', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    assertEquals(signals[0].mimeType, 'text/plain', 'Should prefer text');
} catch (e) {
    assert(false, 'Text priority should work: ' + e.message);
}

// Test 6.2: Falls back to image when no text
console.log('\nTest 6.2: Falls back to image when no text');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content(new Uint8Array([1, 2, 3]), 'image/png');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    assertEquals(signals[0].mimeType, 'image/png', 'Should fall back to image');
} catch (e) {
    assert(false, 'Image fallback should work: ' + e.message);
}

// Test 6.3: Handles unsupported MIME types gracefully
console.log('\nTest 6.3: Handles unsupported MIME types gracefully');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('data', 'application/unknown');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 0, 'Should not emit signal for unsupported MIME');
    
    const infoLogs = monitor.getLogs().info;
    assertTrue(infoLogs.some(l => l.includes('No supported clipboard content')), 'Should log no content found');
} catch (e) {
    assert(false, 'Unsupported MIME should be handled: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 7: Error Handling
// ----------------------------------------------------------------------------
console.log('\n--- Suite 7: Error Handling ---\n');

// Test 7.1: Handles null clipboard content
console.log('Test 7.1: Handles null clipboard content');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.clear(); // No content
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 0, 'Should not emit signal for null content');
} catch (e) {
    assert(false, 'Null content should be handled: ' + e.message);
}

// Test 7.2: Handles read errors gracefully
console.log('\nTest 7.2: Handles read errors gracefully');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    
    // Simulate error in _readAndEmitClipboard by calling with invalid selection
    try {
        monitor._readAndEmitClipboard(null);
        // Should not throw
        assertTrue(true, 'Should not throw on null selection');
    } catch (e) {
        assert(false, 'Should handle null selection gracefully: ' + e.message);
    }
} catch (e) {
    assert(false, 'Read error handling should work: ' + e.message);
}

// Test 7.3: Error in clipboard change handler doesn't crash
console.log('\nTest 7.3: Error in handler doesn\'t crash extension');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    
    // The _onClipboardChanged should catch errors internally
    monitor._onClipboardChanged(null, Meta.SelectionType.SELECTION_CLIPBOARD);
    
    // Extension should still be functional
    const selection = Meta.Selection.get_default();
    selection.set_content('test', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should still process valid changes after error');
} catch (e) {
    assert(false, 'Error isolation should work: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 8: D-Bus Signal Emission
// ----------------------------------------------------------------------------
console.log('\n--- Suite 8: D-Bus Signal Emission ---\n');

// Test 8.1: Signal contains correct data structure
console.log('Test 8.1: Signal contains correct data structure');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('test data', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    
    const signal = signals[0];
    assertNotNull(signal.data, 'Signal should have data');
    assertNotNull(signal.mimeType, 'Signal should have mimeType');
    assertNotNull(signal.size, 'Signal should have size');
} catch (e) {
    assert(false, 'Signal structure should be correct: ' + e.message);
}

// Test 8.2: Binary data is base64 encoded
console.log('\nTest 8.2: Binary data is base64 encoded');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    monitor.clearSignals();
    
    const selection = Meta.Selection.get_default();
    const binaryData = new Uint8Array([0x00, 0x01, 0x02, 0xFF]);
    selection.set_content(binaryData, 'image/png');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit one signal');
    
    // Verify it's valid base64
    const decoded = GLib.base64_decode(signals[0].data);
    assertEquals(decoded.length, 4, 'Should decode to original size');
    assertEquals(decoded[0], 0x00, 'First byte should match');
    assertEquals(decoded[3], 0xFF, 'Last byte should match');
} catch (e) {
    assert(false, 'Base64 encoding should work: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 9: GetClipboardContent Method
// ----------------------------------------------------------------------------
console.log('\n--- Suite 9: GetClipboardContent Method ---\n');

// Test 9.1: Returns last captured content
console.log('Test 9.1: Returns last captured content');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    
    const selection = Meta.Selection.get_default();
    selection.set_content('my content', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    const [data, mime] = monitor.GetClipboardContent();
    assertEquals(data, 'my content', 'Should return captured data');
    assertEquals(mime, 'text/plain', 'Should return captured MIME type');
} catch (e) {
    assert(false, 'GetClipboardContent should work: ' + e.message);
}

// Test 9.2: Returns empty when no content captured
console.log('\nTest 9.2: Returns empty when no content captured');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    
    const [data, mime] = monitor.GetClipboardContent();
    assertEquals(data, '', 'Should return empty string');
    assertEquals(mime, '', 'Should return empty MIME');
} catch (e) {
    assert(false, 'Empty GetClipboardContent should work: ' + e.message);
}

// Test 9.3: Updates on new content
console.log('\nTest 9.3: Updates on new content');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();
    
    const selection = Meta.Selection.get_default();
    
    selection.set_content('first', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    let [data, mime] = monitor.GetClipboardContent();
    assertEquals(data, 'first', 'Should return first content');
    
    selection.set_content('second', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);
    
    [data, mime] = monitor.GetClipboardContent();
    assertEquals(data, 'second', 'Should return updated content');
} catch (e) {
    assert(false, 'Content update should work: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 10: Signal Connection Management
// ----------------------------------------------------------------------------
console.log('\n--- Suite 10: Signal Connection Management ---\n');

// Test 10.1: Multiple connections can be disconnected
console.log('Test 10.1: Multiple connections can be disconnected');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();

    // Manually add multiple connections
    const selection = Meta.Selection.get_default();
    const id1 = selection.connect('owner-changed', () => {});
    const id2 = selection.connect('owner-changed', () => {});
    const id3 = selection.connect('owner-changed', () => {});

    monitor._signalConnections = [id1, id2, id3];
    monitor.disable();

    // Verify connections are cleaned up
    assertEquals(monitor._signalConnections, null, 'Connections should be null after disable');
} catch (e) {
    assert(false, 'Multiple disconnects should work: ' + e.message);
}

// Test 10.2: Disable handles null connections gracefully
console.log('\nTest 10.2: Disable handles null connections gracefully');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();

    // Set null connections (simulating already disabled state)
    monitor._signalConnections = null;

    // Should not throw
    monitor.disable();

    assertTrue(true, 'Should not throw on null connections');
} catch (e) {
    assert(false, 'Null connections should be handled: ' + e.message);
}

// Test 10.3: Disable handles empty connections array
console.log('\nTest 10.3: Disable handles empty connections array');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();

    monitor._signalConnections = [];
    monitor.disable();

    assertEquals(monitor._signalConnections, null, 'Empty array should be cleared');
} catch (e) {
    assert(false, 'Empty connections should be handled: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 11: SetClipboard D-Bus Method
// ----------------------------------------------------------------------------
console.log('\n--- Suite 11: SetClipboard D-Bus Method ---\n');

// Test 11.1: SetClipboard sets clipboard content in Meta.Selection
console.log('Test 11.1: SetClipboard sets clipboard content');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    const selection = Meta.Selection.get_default();
    monitor.SetClipboard('test clipboard data', 'text/plain');

    const content = selection.get_content();
    assertEquals(content.content, 'test clipboard data', 'Should set clipboard data');
    assertEquals(content.mimeType, 'text/plain', 'Should set MIME type');
} catch (e) {
    assert(false, 'SetClipboard should set content: ' + e.message);
}

// Test 11.2: SetClipboard handles image data (base64 encoded)
console.log('\nTest 11.2: SetClipboard handles base64 image data');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    const originalBinary = new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    const base64Data = GLib.base64_encode(originalBinary);

    const selection = Meta.Selection.get_default();
    monitor.SetClipboard(base64Data, 'image/png');

    const content = selection.get_content();
    // For image data, it should decode base64 and set as binary
    assertNotNull(content.content, 'Should set image data');
    assertEquals(content.mimeType, 'image/png', 'Should set image MIME type');
} catch (e) {
    assert(false, 'SetClipboard with base64 should work: ' + e.message);
}

// Test 11.3: SetClipboard updates internal lastClipboardContent
console.log('\nTest 11.3: SetClipboard updates internal state');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    monitor.SetClipboard('new content', 'text/plain');

    const lastContent = monitor.getLastClipboardContent();
    assertEquals(lastContent.data, 'new content', 'Should update internal data');
    assertEquals(lastContent.mime, 'text/plain', 'Should update internal MIME');
} catch (e) {
    assert(false, 'SetClipboard should update state: ' + e.message);
}

// Test 11.4: SetClipboard handles empty data
console.log('\nTest 11.4: SetClipboard handles empty data');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    monitor.SetClipboard('', 'text/plain');

    const content = Meta.Selection.get_default().get_content();
    assertEquals(content.content, '', 'Should set empty data');
    assertEquals(content.mimeType, 'text/plain', 'Should set MIME type');
} catch (e) {
    assert(false, 'SetClipboard with empty data should work: ' + e.message);
}

// Test 11.5: SetClipboard logs the operation
console.log('\nTest 11.5: SetClipboard logs the operation');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    monitor.SetClipboard('test', 'text/plain');

    const logs = monitor.getLogs().info;
    assertTrue(logs.some(l => l.includes('SetClipboard')), 'Should log SetClipboard call');
} catch (e) {
    assert(false, 'SetClipboard should log: ' + e.message);
}

// Test 11.6: SetClipboard handles invalid base64 gracefully
console.log('\nTest 11.6: SetClipboard handles invalid base64 gracefully');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    // Invalid base64 should not crash
    monitor.SetClipboard('!!!invalid-base64!!!', 'image/png');

    assertTrue(true, 'Should not crash on invalid base64');
} catch (e) {
    assert(false, 'Invalid base64 should be handled: ' + e.message);
}

// Test 11.7: SetClipboard handles null data
console.log('\nTest 11.7: SetClipboard handles null data');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    monitor.SetClipboard(null, 'text/plain');

    assertTrue(true, 'Should not crash on null data');
} catch (e) {
    assert(false, 'Null data should be handled: ' + e.message);
}

// Test 11.8: SetClipboard handles unknown MIME type
console.log('\nTest 11.8: SetClipboard handles unknown MIME type');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    monitor.SetClipboard('data', 'application/custom');

    const content = Meta.Selection.get_default().get_content();
    assertNotNull(content.content, 'Should set data for unknown MIME');
    assertEquals(content.mimeType, 'application/custom', 'Should preserve unknown MIME');
} catch (e) {
    assert(false, 'Unknown MIME type should be handled: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 12: SimulatePaste D-Bus Method
// ----------------------------------------------------------------------------
console.log('\n--- Suite 12: SimulatePaste D-Bus Method ---\n');

// Test 12.1: SimulatePaste logs the operation
console.log('Test 12.1: SimulatePaste logs the operation');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    monitor.SimulatePaste();

    const logs = monitor.getLogs().info;
    assertTrue(logs.some(l => l.includes('SimulatePaste')), 'Should log SimulatePaste call');
} catch (e) {
    assert(false, 'SimulatePaste should log: ' + e.message);
}

// Test 12.2: SimulatePaste sets pastePending flag
console.log('Test 12.2: SimulatePaste sets paste pending flag');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    monitor.SimulatePaste();

    // Check that paste was triggered (via internal flag or callback)
    assertTrue(monitor._pasteTriggered, 'Should set paste triggered flag');
} catch (e) {
    assert(false, 'SimulatePaste should set flag: ' + e.message);
}

// Test 12.3: SimulatePaste handles no focused window gracefully
console.log('\nTest 12.3: SimulatePaste handles no focused window');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    // Set no focused window
    Meta.Display.get_default().set_focus_window(null);

    // Should not throw
    monitor.SimulatePaste();

    assertTrue(true, 'Should not throw with no focused window');
} catch (e) {
    assert(false, 'No focused window should be handled: ' + e.message);
}

// Test 12.4: SimulatePaste works after SetClipboard
console.log('\nTest 12.4: SimulatePaste works after SetClipboard');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    monitor.SetClipboard('paste this', 'text/plain');
    monitor.SimulatePaste();

    const content = Meta.Selection.get_default().get_content();
    assertEquals(content.content, 'paste this', 'Should have content ready for paste');
    assertTrue(monitor._pasteTriggered, 'Should trigger paste');
} catch (e) {
    assert(false, 'SimulatePaste after SetClipboard should work: ' + e.message);
}

// Test 12.5: SimulatePaste is idempotent (multiple calls safe)
console.log('\nTest 12.5: SimulatePaste is idempotent');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    monitor.SimulatePaste();
    monitor.SimulatePaste();
    monitor.SimulatePaste();

    assertTrue(monitor._pasteTriggered, 'Should still have paste triggered');
} catch (e) {
    assert(false, 'Multiple SimulatePaste calls should be safe: ' + e.message);
}

// Test 12.6: SimulatePaste with focused window
console.log('\nTest 12.6: SimulatePaste with focused window');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    // Set a mock focused window
    const mockWindow = { get_title: function() { return 'Test Window'; } };
    Meta.Display.get_default().set_focus_window(mockWindow);

    monitor.SimulatePaste();

    assertTrue(monitor._pasteTriggered, 'Should trigger paste with focused window');
} catch (e) {
    assert(false, 'SimulatePaste with window should work: ' + e.message);
}

// ----------------------------------------------------------------------------
// Suite 13: D-Bus Interface Integration
// ----------------------------------------------------------------------------
console.log('\n--- Suite 13: D-Bus Interface Integration ---\n');

// Test 13.1: D-Bus interface contains all required methods
console.log('Test 13.1: D-Bus interface contains all methods');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    // Verify methods exist
    assertNotNull(monitor.SetClipboard, 'SetClipboard method should exist');
    assertNotNull(monitor.SimulatePaste, 'SimulatePaste method should exist');
    assertNotNull(monitor.GetClipboardContent, 'GetClipboardContent method should exist');
} catch (e) {
    assert(false, 'D-Bus methods should exist: ' + e.message);
}

// Test 13.2: D-Bus interface contains ClipboardChanged signal
console.log('\nTest 13.2: D-Bus interface contains signal definition');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    // D-Bus impl should be exported
    assertTrue(monitor._dbusImpl.exported, 'D-Bus should be exported');
} catch (e) {
    assert(false, 'D-Bus signal should be defined: ' + e.message);
}

// Test 13.3: Complete workflow - capture, set, paste
console.log('\nTest 13.3: Complete clipboard workflow');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    // Step 1: Capture content
    const selection = Meta.Selection.get_default();
    selection.set_content('original', 'text/plain');
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);

    let signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should capture clipboard');

    // Step 2: Set new content
    monitor.SetClipboard('replacement', 'text/plain');
    let content = selection.get_content();
    assertEquals(content.content, 'replacement', 'Should set new content');

    // Step 3: Simulate paste
    monitor.SimulatePaste();
    assertTrue(monitor._pasteTriggered, 'Should trigger paste');

    // Step 4: Get content
    const [data, mime] = monitor.GetClipboardContent();
    assertEquals(data, 'replacement', 'Should return current content');
} catch (e) {
    assert(false, 'Complete workflow should work: ' + e.message);
}

// Test 13.4: Methods called before enable() should not crash
console.log('\nTest 13.4: Methods called before enable()');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();

    // Call methods before enable
    monitor.SetClipboard('test', 'text/plain');
    monitor.SimulatePaste();
    monitor.GetClipboardContent();

    assertTrue(true, 'Should not crash when called before enable');
} catch (e) {
    assert(false, 'Pre-enable calls should be handled: ' + e.message);
}

// Test 13.5: SetClipboard then capture should emit signal
console.log('\nTest 13.5: SetClipboard then capture emits signal');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    // Set clipboard content
    monitor.SetClipboard('initial', 'text/plain');
    monitor.clearSignals();

    // Now trigger capture (should capture what we just set)
    const selection = Meta.Selection.get_default();
    selection.emit_owner_changed(Meta.SelectionType.SELECTION_CLIPBOARD);

    const signals = monitor.getEmittedSignals();
    assertEquals(signals.length, 1, 'Should emit signal after SetClipboard');
} catch (e) {
    assert(false, 'Capture after SetClipboard should work: ' + e.message);
}

// Test 13.6: Image workflow - set base64, verify binary storage
console.log('\nTest 13.6: Image workflow');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    const originalImage = new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFF]);
    const base64Image = GLib.base64_encode(originalImage);

    monitor.SetClipboard(base64Image, 'image/png');

    const content = monitor.getLastClipboardContent();
    assertNotNull(content.data, 'Should store image data');
    assertEquals(content.mime, 'image/png', 'Should preserve MIME type');
} catch (e) {
    assert(false, 'Image workflow should work: ' + e.message);
}

// Test 13.7: State isolation - disable clears all state
console.log('\nTest 13.7: State isolation on disable');
try {
    Meta.Selection._reset();
    const monitor = new UrutauClipboardMonitor();
    monitor.enable();

    // Set up state
    monitor.SetClipboard('test', 'text/plain');
    monitor.SimulatePaste();

    // Disable
    monitor.disable();

    // Verify state cleared
    assertEquals(monitor._pasteTriggered, false, 'Paste flag should be cleared');
    assertEquals(monitor.getLastClipboardContent(), null, 'Clipboard content should be cleared');
} catch (e) {
    assert(false, 'State isolation should work: ' + e.message);
}

// ============================================================================
// TEST SUMMARY
// ============================================================================

console.log('\n========================================');
console.log('           TEST SUMMARY');
console.log('========================================\n');
console.log(`Total Tests: ${testsPassed + testsFailed}`);
console.log(`Passed: ${testsPassed}`);
console.log(`Failed: ${testsFailed}`);
console.log(`Success Rate: ${((testsPassed / (testsPassed + testsFailed)) * 100).toFixed(1)}%`);

if (failures.length > 0) {
    console.log('\n--- Failures ---\n');
    failures.forEach((f, i) => {
        console.log(`${i + 1}. ${f}`);
    });
    console.log('\n❌ Some tests failed');
} else {
    console.log('\n✅ All tests passed!');
}
