# Implementation Plan

## Task List

- [x] 1. GNOME Shell Extension for Clipboard Monitoring
- [x] 1.1 Implement clipboard change detection using Meta.Selection
  - Create GJS extension structure with proper metadata
  - Monitor Meta.Selection for owner-changed signals
  - Read clipboard content for text/plain and image/png MIME types
  - Handle size limit checks before reading content
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 1.2 Implement D-Bus service interface for extension
  - Define org.urutau.Monitor interface with ClipboardChanged signal
  - Implement SetClipboard method for data restoration
  - Implement SimulatePaste method using Mutter internal APIs
  - Register D-Bus service on GNOME session bus
  - _Requirements: 4.1, 4.2, 5.2_

- [x] 2. Zig Daemon Core Infrastructure
- [x] 2.1 Set up Zig project structure and D-Bus integration
  - Initialize Zig 0.15.2 project with build.zig configuration
  - Evaluate and integrate D-Bus library (dbuz or libdbus wrapper)
  - Implement D-Bus client connection to GNOME extension
  - Set up exponential backoff reconnection logic for IPC failures
  - _Requirements: 5.1, 5.2_

- [x] 2.2 Implement SQLite storage layer with concurrency controls
  - Create SQLite database schema with history table (id, content, mime_type, created_at, search_text)
  - Configure WAL mode for concurrent read/write access
  - Implement connection pooling with single-writer pattern
  - Add database corruption detection and .bak rotation recovery
  - Set file permissions to 0600 for data privacy
  - _Requirements: 5.3_

- [x] 2.3 Implement clipboard history data operations
  - Create HistoryItem struct with id, blob, mime_type, timestamp, metadata
  - Implement INSERT operation for new clipboard captures
  - Implement GetHistory with offset/limit pagination
  - Implement DeleteItem and ClearHistory operations
  - Add full-text search on search_text column for real-time filtering
  - _Requirements: 2.1, 2.2, 2.3, 3.1, 3.2_

- [ ] 3. Lua VM Integration with Resource Controls
- [x] 3.1 Integrate Lua 5.5 VM using ziglua
  - Add ziglua dependency to build.zig
  - Initialize Lua state with custom Zig allocator
  - Implement pcall-based error handling for graceful degradation
  - Log Lua errors and skip transformation on failure
  - _Requirements: 1.4_

- [x] 3.2 Implement Lua resource controls and sandboxing
  - Implement lua_sethook() for instruction count limits and execution timeouts
  - Create restricted Lua environment (no os.execute, restricted io, no require)
  - Add per-script resource quotas in configuration
  - _Requirements: 1.3, 5.2_
  - **TODO**: `timeout_ms` config field exists but time-based enforcement is not implemented. Only instruction-count-based limiting via `lua_sethook` is active. See `vm.zig:setTimeout()` and `Config.timeout_ms`.
  - **TODO**: Memory limiting is out of scope - Lua's C allocator semantics make custom allocator integration complex. Clipboard size limits should be enforced at the capture layer before passing data to Lua scripts.

- [x] 3.3 Implement pre-capture hook execution
  - Define Lua hook interface for clipboard transformation
  - Execute user scripts on clipboard data before storage
  - Pass modified data back to daemon for persistence
  - Handle script timeout and memory limit violations
  - _Requirements: 1.4_

- [ ] 4. GTK4/Libadwaita History Picker UI
- [x] 4.1 Set up GTK4 UI project with zig-gobject bindings
  - Initialize GTK4 project structure (using GTK4 only due to libadwaita version constraints)
  - Create main History Picker window with GtkApplicationWindow
  - Set up basic UI with header bar, search entry, and history list
  - Write unit tests for GTK4 components
  - _Requirements: 2.1, 5.1_

- [x] 4.2 Implement history list display with clipboard indicator
  - Create HistoryCollection data model with CRUD operations
  - Render history items in reverse chronological order
  - Highlight item matching current system clipboard content
  - Implement real-time updates when daemon captures new items
  - _Requirements: 2.1, 2.4_

- [x] 4.3 Implement search and filtering interface
  - Add search entry with real-time filtering
  - Implement case-insensitive text search in history content
  - Update filtered list as user types (search-changed signal)
  - Display no-results state when query matches nothing
  - _Requirements: 3.1, 3.2_

- [x] 4.4 Implement item selection and restoration
  - Handle item click/keyboard selection via row-activated signal
  - Implement SelectionHandler with restore-only and restore-and-paste modes
  - Call daemon to set system clipboard content via D-Bus (stubbed for now)
  - Implement auto-paste toggle and trigger via D-Bus to extension (stubbed)
  - Clear selection after action performed
  - _Requirements: 4.1, 4.2_

- [ ] 5. System Integration and Packaging
- [ ] 5.1 Create systemd user service for daemon
  - Write urutau-daemon.service unit file
  - Configure daemon to start on D-Bus activation
  - Set restart-condition: on-failure policy
  - _Requirements: 5.1_

- [ ] 5.2 Create D-Bus service file for daemon activation
  - Write org.urutau.Daemon.service file
  - Configure session bus service activation
  - Test daemon auto-start via D-Bus
  - _Requirements: 5.2_

- [ ] 5.3 Implement GNOME extension installation hook
  - Create install hook script for extension deployment
  - Copy GJS extension to ~/.local/share/gnome-shell/extensions/urutau@urutau.io/
  - Enable extension via gnome-extensions enable command
  - Handle post-refresh hook for updates
  - _Requirements: 5.2_

- [ ] 6. Testing and Validation
- [ ] 6.1 Implement unit tests for Zig daemon
  - Test SQLite mapping and CRUD operations
  - Test Lua VM integration and error handling
  - Test data cleaning and size limit logic
  - Test resource control enforcement (memory, timeout)
  - _Requirements: 1.3, 1.4, 5.3_

- [ ] 6.2 Implement integration tests for D-Bus communication
  - Create mock GJS extension for testing
  - Verify ClipboardChanged signal reception
  - Test SetClipboard and SimulatePaste commands
  - Test reconnection logic on IPC failure
  - _Requirements: 4.1, 4.2, 5.2_

- [ ] 6.3 Validate persistence across reboot
  - Test database survives system restart
  - Verify history recovery after daemon restart
  - Test SQLite corruption recovery with .bak rotation
  - _Requirements: 5.3_

- [ ] 6.4 Manual UI validation on Ubuntu 22.04
  - Test History Picker rendering and responsiveness
  - Validate real-time search filtering performance
  - Test clipboard restoration and auto-paste functionality
  - Verify native GNOME look and feel
  - _Requirements: 2.1, 3.1, 3.2, 4.1, 4.2, 5.1_
