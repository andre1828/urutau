# Product Overview

Urutau is a high-performance clipboard manager for Ubuntu 22.04+ (GNOME 42+) that captures, stores, searches, and restores clipboard history. It bridges Wayland security constraints through a hybrid architecture combining a GNOME Shell Extension with a persistent Zig daemon.

## Core Capabilities

1. **Automatic Clipboard Capture**: Monitors system clipboard for text and image content in real-time
2. **Persistent History Storage**: SQLite-backed storage survives system reboots with full-text search
3. **Fast Searchable UI**: GTK4/Libadwaita history picker with real-time filtering
4. **User-Defined Extensibility**: Lua scripting for clipboard transformation hooks
5. **GNOME Integration**: Native D-Bus communication and Wayland-compliant architecture

## Target Use Cases

- Developers copying code snippets across multiple applications
- Users managing multiple copied items before pasting
- Quick retrieval of previously copied sensitive data (passwords, URLs)
- Batch operations on clipboard history (clear, delete, restore)

## Value Proposition

- **Wayland-Native**: Respects compositor security while providing full clipboard history
- **High Performance**: Zig core engine ensures minimal latency and memory footprint
- **Extensible**: Lua scripting allows custom transformations without modifying core
- **Privacy-First**: Local SQLite storage with restricted file permissions (0600)

---
_Focus on patterns and purpose, not exhaustive feature lists_
