# Technology Stack

## Architecture

Hybrid Extension + Daemon pattern: GJS extension handles privileged Mutter signals; Zig daemon manages storage, logic, and Lua VM.

## Core Technologies

- **Core Engine**: Zig 0.15.2 (Daemon & UI logic)
- **Scripting**: Lua 5.5 (User-defined filters via `ziglua`)
- **UI Framework**: GTK4 / Libadwaita (History Picker UI)
- **IPC**: D-Bus Session Bus (Extension ↔ Daemon communication)
- **Storage**: SQLite 3 (History persistence with WAL mode)
- **Extension**: GJS (GNOME Shell Extension for GNOME 42-46)

## Key Libraries

| Component | Library | Purpose |
|-----------|---------|---------|
| Zig ↔ Lua | `ziglua` | Lua VM integration |
| Zig ↔ D-Bus | `dbuz` or libdbus | IPC communication |
| Zig ↔ GTK | `zig-gobject` | GTK4 bindings |
| GJS | GNOME Shell APIs | Clipboard monitoring |

## Development Standards

### Type Safety
- Zig: Strong static typing with explicit error unions
- GJS: JSDoc annotations for GNOME Shell APIs
- Lua: Sandboxed environment with restricted globals

### Code Quality
- Zig: `zig fmt` for formatting, `zig build test` for unit tests
- GJS: ESLint with GNOME Shell plugin rules
- File permissions: SQLite database must be 0600 (user-only read/write)

### Testing
- **Test Quality**: Focus on happy paths and edge cases
- **Unit Tests (Zig)**: SQLite mapping, Lua VM integration, data cleaning
- **Integration Tests**: D-Bus message exchange between mock extension and daemon
- **GJS Tests**: `gjs --module tests/test-extension.js`

## Development Environment

### Required Tools
- Zig 0.15.2+
- GNOME Shell 42-46 (development headers)
- GTK4 / Libadwaita development libraries
- SQLite 3 with WAL support
- Lua 5.5 development libraries

### Common Commands
```bash
# GJS Extension Tests
npm test                    # Run extension test suite
npm run test:watch          # Watch mode for tests

# Zig Daemon (when implemented)
zig build test              # Run Zig unit tests
zig build run               # Run daemon
```

## Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| **Hybrid Architecture** | Wayland isolation requires privileged extension for clipboard access |
| **Zig for Core** | Memory safety, performance, small footprint |
| **Lua for Scripting** | Lightweight, embeddable, user-friendly |
| **SQLite WAL Mode** | Concurrent read/write without locking contention |
| **D-Bus Session Bus** | Standard GNOME IPC mechanism |
| **Base64 Encoding** | Binary-safe D-Bus signal transmission for images |

---
_Document standards and patterns, not every dependency_
