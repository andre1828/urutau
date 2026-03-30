# Project Structure

## Organization Philosophy

**Domain-Driven Hybrid**: Separate concerns by technology boundary (GJS extension, Zig daemon, GTK UI) with clear D-Bus contracts between components.

## Directory Patterns

### GNOME Shell Extension
**Location**: `/extensions/urutau@urutau.io/`
**Purpose**: Privileged bridge between Mutter compositor and Zig daemon
**Structure**:
```
extensions/urutau@urutau.io/
├── extension.js          # Main entry point, clipboard monitoring
├── metadata.json         # GNOME Shell extension metadata
├── package.json          # NPM test configuration
├── dbus/
│   └── org.urutau.Monitor.xml  # D-Bus interface definition
└── tests/
    └── test-extension.js # Comprehensive GJS test suite
```

### Zig Daemon (Planned)
**Location**: `/src/daemon/` (to be created)
**Purpose**: Core engine managing storage, Lua VM, and business logic
**Expected Structure**:
```
src/daemon/
├── main.zig              # Daemon entry point
├── dbus/                 # D-Bus client implementation
├── storage/              # SQLite layer
├── lua/                  # Lua VM integration
└── config/               # Configuration management
```

### GTK UI (Planned)
**Location**: `/src/ui/` (to be created)
**Purpose**: History Picker window with search and selection
**Expected Structure**:
```
src/ui/
├── main.zig              # UI entry point
├── widgets/              # GTK4 components
└── models/               # Data models for history list
```

### Specification-Driven Development
**Location**: `/.sdd/`
**Purpose**: SDD workflow artifacts (steering, specs, templates)
**Structure**:
```
.sdd/
├── steering/             # Project memory (product, tech, structure)
├── specs/                # Feature specifications
└── settings/             # Templates and rules for SDD workflow
```

## Naming Conventions

- **Files**: `kebab-case.zig` for Zig, `camelCase.js` for GJS
- **GJS Classes**: `PascalCase` (e.g., `UrutauExtension`, `MockSelection`)
- **Zig Functions**: `snake_case` (e.g., `init_database`, `emit_clipboard_changed`)
- **D-Bus Interfaces**: `org.urutau.{Component}` (e.g., `org.urutau.Monitor`, `org.urutau.Daemon`)
- **Test Files**: `test-*.js` for GJS, `*_test.zig` for Zig

## Import Organization

### GJS (GNOME Shell Extension)
```javascript
// GNOME Shell APIs (gi://)
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';

// Extension utilities
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
```

### Zig (Planned)
```zig
// Standard library
const std = @import("std");

// Local modules
const Database = @import("storage/database.zig");
const LuaVM = @import("lua/vm.zig");
```

**Path Aliases**: Relative imports with `./` and `../` for both Zig and GJS

## Code Organization Principles

### Separation of Concerns
| Layer | Responsibility | Technology |
|-------|---------------|------------|
| **Monitoring** | Clipboard change detection, D-Bus signals | GJS + Meta.Selection |
| **Persistence** | SQLite storage, CRUD operations | Zig + SQLite |
| **Logic** | Lua hooks, size limits, filtering | Zig + Lua |
| **UI** | History display, search, selection | Zig + GTK4 |

### Dependency Rules
- **Extension → Daemon**: D-Bus signals only (one-way for clipboard changes)
- **Daemon → Extension**: D-Bus method calls (SetClipboard, SimulatePaste)
- **UI → Daemon**: D-Bus method calls (GetHistory, DeleteItem)
- **No direct imports** between GJS and Zig components

### Error Handling Patterns
- **GJS**: Try-catch with console logging, graceful degradation
- **Zig**: Error unions with `try`/`catch`, exponential backoff for IPC
- **Lua**: `pcall` for script execution, graceful skip on error

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_
