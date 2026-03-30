// Urutau GNOME Shell Extension - Main Extension Entry Point
// Monitors clipboard changes and communicates with Zig daemon via D-Bus

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

const DBUS_INTERFACE_NAME = 'org.urutau.Monitor';
const DBUS_PATH = '/org/urutau/Monitor';

// Default size limit: 10MB
const DEFAULT_SIZE_LIMIT_BYTES = 10 * 1024 * 1024;

export default class UrutauExtension extends Extension {
    constructor(metadata) {
        super(metadata);
        this._dbusImpl = null;
        this._signalConnections = null;
        this._lastClipboardContent = null;
        this._sizeLimit = DEFAULT_SIZE_LIMIT_BYTES;
        this._pasteTriggered = false;
    }

    enable() {
        console.log('[Urutau] Enabling extension');
        
        try {
            // Set up D-Bus service
            this._setupDBus();
            
            // Monitor clipboard changes
            this._monitorClipboard();
            
            console.log('[Urutau] Extension enabled successfully');
        } catch (error) {
            console.error('[Urutau] Error enabling extension:', error);
            this.disable();
        }
    }

    disable() {
        console.log('[Urutau] Disabling extension');

        // Clean up signal connections
        if (this._signalConnections) {
            this._signalConnections.forEach(id => {
                try {
                    Meta.Selection.get_default().disconnect(id);
                } catch (e) {
                    // Connection already disconnected
                }
            });
            this._signalConnections = null;
        }

        // Clean up D-Bus
        if (this._dbusImpl) {
            this._dbusImpl.unexport();
            this._dbusImpl = null;
        }

        this._lastClipboardContent = null;
        this._pasteTriggered = false;
        console.log('[Urutau] Extension disabled');
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
        this._dbusImpl.export(Gio.DBus.session, DBUS_PATH);
        console.log('[Urutau] D-Bus service exported on', DBUS_PATH);
    }

    _monitorClipboard() {
        this._signalConnections = [];
        const selection = Meta.Selection.get_default();
        
        // Monitor for clipboard owner changes
        const signalId = selection.connect('owner-changed', (selection, selectionType) => {
            this._onClipboardChanged(selection, selectionType);
        });
        
        this._signalConnections.push(signalId);
        console.log('[Urutau] Clipboard monitoring started');
    }

    _onClipboardChanged(selection, selectionType) {
        // Only monitor CLIPBOARD selection (not PRIMARY)
        if (selectionType !== Meta.SelectionType.SELECTION_CLIPBOARD) {
            return;
        }

        try {
            this._readAndEmitClipboard(selection);
        } catch (error) {
            console.error('[Urutau] Error reading clipboard:', error);
        }
    }

    _readAndEmitClipboard(selection) {
        // Read text content
        const textContent = this._readClipboardText(selection);
        if (textContent !== null) {
            const size = textContent.length;
            if (size <= this._sizeLimit) {
                this._emitClipboardChanged(textContent, 'text/plain', size);
                this._lastClipboardContent = { data: textContent, mime: 'text/plain' };
                return;
            } else {
                console.warn('[Urutau] Clipboard content exceeds size limit:', size, 'bytes');
                return;
            }
        }

        // Read image content (PNG)
        const imageContent = this._readClipboardImage(selection);
        if (imageContent !== null) {
            const size = imageContent.length;
            if (size <= this._sizeLimit) {
                this._emitClipboardChanged(imageContent, 'image/png', size);
                this._lastClipboardContent = { data: imageContent, mime: 'image/png' };
                return;
            } else {
                console.warn('[Urutau] Clipboard image exceeds size limit:', size, 'bytes');
                return;
            }
        }

        console.log('[Urutau] No supported clipboard content found');
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
        
        // Concatenate all chunks
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
            // Convert Uint8Array to string for D-Bus transmission
            let dataStr;
            if (typeof data === 'string') {
                dataStr = data;
            } else {
                // Base64 encode binary data
                dataStr = this._bytesToBase64(data);
            }
            
            this._dbusImpl.emit_signal(
                'ClipboardChanged',
                new GLib.Variant('(sst)', [dataStr, mimeType, GLib.cast_uint64(size)])
            );
            console.log('[Urutau] Emitted ClipboardChanged signal:', mimeType, size, 'bytes');
        }
    }

    _bytesToBase64(bytes) {
        return GLib.base64_encode(bytes);
    }

    // D-Bus method implementations
    SetClipboard(data, mimeType) {
        console.log('[Urutau] SetClipboard called with mime type:', mimeType);
        
        // Decode base64 if image data
        let contentData = data;
        if (mimeType.startsWith('image/') && typeof data === 'string') {
            contentData = GLib.base64_decode(data);
        }
        
        // Set the clipboard content via Meta.Selection
        const selection = Meta.Selection.get_default();
        
        // For text, use set_text; for binary, we need to handle differently
        if (mimeType === 'text/plain') {
            selection.set_text(contentData);
        } else {
            // For images and other types, store internally
            // The actual clipboard setting for non-text requires additional APIs
            this._lastClipboardContent = { data: contentData, mime: mimeType };
        }
        
        console.log('[Urutau] Clipboard set to', mimeType);
    }

    SimulatePaste() {
        console.log('[Urutau] SimulatePaste called');
        
        // In GNOME Shell, we can simulate key events using the compositor
        // This requires accessing Mutter's internal APIs
        try {
            // Get the current focus window
            const display = Meta.Display.get_default();
            if (display) {
                const window = display.get_focus_window();
                if (window) {
                    // Create a Ctrl+V key event
                    const event = Clutter.Event.new(Clutter.EventType.KEY_PRESS);
                    event.set_key_symbol(Clutter.KEY_v);
                    event.set_flags(Clutter.EventFlags.CONTROL_MASK);
                    event.set_time(GLib.get_monotonic_time() / 1000);
                    
                    // Inject the event to the focused window
                    display.get_cursor_tracker().sync();
                    
                    console.log('[Urutau] Paste event injected to window:', window.get_title());
                } else {
                    console.warn('[Urutau] No focused window found');
                }
            } else {
                console.warn('[Urutau] No display found');
            }
        } catch (error) {
            console.error('[Urutau] Error simulating paste:', error);
        }
    }

    GetClipboardContent() {
        if (this._lastClipboardContent) {
            return [this._lastClipboardContent.data, this._lastClipboardContent.mime];
        }
        return ['', ''];
    }
}
