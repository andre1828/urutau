# Research & Design Decisions - Urutau

---
**Purpose**: Capture discovery findings, architectural investigations, and rationale that inform the technical design for Urutau.

**Usage**:
- Log research activities and outcomes during the discovery phase.
- Document design decision trade-offs for the Zig/Lua hybrid clipboard manager.
---

## Summary
- **Feature**: Urutau Clipboard Manager
- **Discovery Scope**: New Feature (Greenfield)
- **Key Findings**:
  - GNOME 42+ on Wayland restricts background clipboard access; a GNOME Shell Extension is required as a bridge.
  - Zig 0.15.2 provides robust C interoperability for GTK4 and SQLite integration.
  - Lua 5.5 integration via `ziglua` allows for high-performance, user-defined clipboard transformations.
  - Snap is the recommended distribution format (not AppImage) due to daemon + GNOME extension architecture.

## Research Log

### Linux App Distribution
- **Context**: Choosing a distribution format for Urutau (Zig daemon + GNOME Shell Extension + GTK4 UI).
- **Sources Consulted**: ComputingForGeeks comparison (Mar 2026), OneUptime guide (Mar 2026), Snapcraft docs, AppImage docs, David Bushell's Zig release blog.
- **Findings**:
  - AppImage is unsuitable: cannot install GNOME extensions, register D-Bus services, or manage daemons.
  - Snap is the best fit: native daemon support, GNOME extension hooks, auto-updates, first-class Ubuntu integration.
  - Flatpak lacks daemon support and cannot install GNOME extensions outside the sandbox.
  - Native .deb via PPA is viable but has higher maintenance burden.
- **Implications**: Urutau should be distributed as a Snap package using `core22` base with the `gnome` extension.

### GNOME Wayland Clipboard Access
- **Context**: How to monitor the clipboard on Ubuntu 22.04 (Wayland) without keyboard focus?
- **Sources Consulted**: GNOME Mutter API docs, XDG Desktop Portal specs, GPaste source code.
- **Findings**:
  - Mutter doesn't support `wlr-data-control`.
  - Standard apps only get clipboard access when focused.
  - GNOME Shell Extensions run inside the compositor and can access `St.Clipboard` and `Meta.Selection` directly.
- **Implications**: Urutau must include a small GJS extension to "watch" the clipboard and signal the Zig daemon.

### Zig and Lua Integration
- **Context**: Best way to embed Lua in a Zig application in 2024/2025.
- **Sources Consulted**: `ziglua` repository, Zig community forums.
- **Findings**:
  - `ziglua` (by natecraddock) is the most idiomatic wrapper for Lua 5.1-5.5.
  - Zig's `comptime` can be used to generate Lua userdata bindings with minimal boilerplate.
  - Memory management is handled by passing a Zig `Allocator` to the Lua state.
- **Implications**: The Zig daemon will host a Lua VM to allow users to write custom "actions" (e.g., regex-based cleaning of URLs).

### UI Framework for GNOME
- **Context**: Building a native-feeling UI with Zig on Ubuntu 22.04.
- **Sources Consulted**: GTK4/Libadwaita documentation, `zig-gobject` bindings.
- **Findings**:
  - `zig-gobject` (by ianprime0509) provides high-quality generated bindings for GTK4 and Libadwaita.
  - Direct C integration via `@cImport` is a viable fallback with zero overhead.
- **Implications**: The UI will use Libadwaita to match the Ubuntu 22.04/24.04 aesthetic.

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| **Hybrid Extension/Daemon** | GJS Extension for monitoring + Zig Daemon for logic | Full Wayland support, native GNOME feel | Complexity of IPC (D-Bus) | Recommended for GNOME compatibility |
| **Portal-only** | Relying on `xdg-desktop-portal` | Secure, standard-compliant | Limited background "watching" in GNOME 42 | May miss events when inactive |
| **Standalone Daemon (X11 only)** | Zig binary using X11 APIs | Simple implementation | Broken on Wayland (Ubuntu default) | Not viable for Ubuntu 22.04+ |

## Design Decisions

### Decision: IPC Mechanism
- **Context**: Communication between the GNOME Extension and the Zig Daemon.
- **Alternatives Considered**:
  1. Unix Domain Sockets
  2. D-Bus (Session Bus)
- **Selected Approach**: **D-Bus**
- **Rationale**: D-Bus is the standard for GNOME services. It allows for "activation" (starting the daemon on demand) and is natively supported by GJS.
- **Trade-offs**: Slightly more overhead than raw sockets, but significantly better integration.

### Decision: Storage Engine
- **Context**: Persistence for clipboard history.
- **Alternatives Considered**:
  1. Flat Files (JSON/YAML)
  2. SQLite
- **Selected Approach**: **SQLite**
- **Rationale**: Provides efficient searching/filtering (Requirement 3), handles concurrent access better, and is supported by Zig via `zig-sqlite`.
- **Trade-offs**: Requires linking a C library, but Zig handles this gracefully.

### Decision: Auto-Paste Implementation
- **Context**: Requirement 4.2 (Simulate paste).
- **Selected Approach**: **GNOME Extension API**
- **Rationale**: Since we already need an extension for monitoring, the extension can also use Mutter's internal virtual input or `Meta.Selection` to trigger a paste operation more reliably than a standalone app.

## Risks & Mitigations
- **Wayland Security Changes** — Future GNOME versions might restrict extensions further. Mitigation: Monitor GNOME Shell API changes and consider Portal migration if it matures.
- **Memory Leaks in Lua** — User scripts might be poorly written. Mitigation: Use Zig's `std.heap.GeneralPurposeAllocator` for the Lua VM and implement a timeout/limit for script execution.
- **D-Bus Stability** — Zig libraries for D-Bus are in flux. Mitigation: Use `dbuz` (pure Zig) or wrap the stable C `libdbus` if necessary.

## Linux App Distribution Research

### Context
Urutau has a hybrid architecture: a Zig daemon, a GNOME Shell Extension (GJS), and a GTK4 UI. The distribution method must handle all components and their integration points (D-Bus service file, systemd user service, GNOME extension installation).

### Options Evaluated

| Format | Daemon Support | GNOME Extension | D-Bus/ systemd | Ubuntu Integration | Complexity | Verdict |
|--------|---------------|-----------------|----------------|-------------------|------------|---------|
| **AppImage** | Poor | Not possible | Problematic | Low | Low for binary only | ❌ Not suitable |
| **Snap** | Excellent | Via hooks | Native support | First-class | Medium | ✅ Best fit |
| **Flatpak** | Limited | Not possible | Restricted | Requires install | Medium | ⚠️ Partial |
| **.deb / PPA** | Excellent | Via postinst | Native support | Native | High maintenance | ✅ Viable alternative |

### AppImage — Why It's Not Suitable

AppImage is ideal for single, self-contained binaries. However, Urutau is NOT a single binary:

1. **GNOME Shell Extension**: Must be installed to `~/.local/share/gnome-shell/extensions/`. AppImage cannot do this — extensions must be in the filesystem, not inside a mounted image.
2. **D-Bus Service**: Requires a `.service` file in `/usr/share/dbus-1/services/` or `~/.local/share/dbus-1/services/`. AppImage cannot register D-Bus services.
3. **Systemd User Service**: Needs a unit file in `~/.config/systemd/user/`. AppImage has no installation hooks.
4. **Desktop Integration**: No `.desktop` file auto-installation, no MIME type registration.
5. **Updates**: No built-in update mechanism. Users must manually download new versions.

**Conclusion**: AppImage works for standalone GUI apps (Blender, Kdenlive). It fails for daemon + extension architectures like Urutau.

### Snap — Recommended Approach

Snap is the best fit for Urutau on Ubuntu for several reasons:

**Advantages:**
- **Daemon support**: Snap natively supports daemons via `snap.yaml` (`daemon: simple`). The Zig daemon runs as a managed service.
- **GNOME Extension bundling**: Snap hooks (`install`, `post-refresh`) can install/enable the GJS extension to the correct path.
- **D-Bus service**: Snap supports D-Bus activation natively.
- **Auto-updates**: Background updates (4x daily) keep the daemon current.
- **GNOME extension**: The `gnome` Snap extension provides GTK4/Libadwaita runtime dependencies.
- **Snap Store**: Ubuntu's default store. Users install with `sudo snap install urutau`.
- **Confinement**: AppArmor sandboxing for the daemon (clipboard data protection).
- **Rollback**: `snap revert urutau` if an update breaks something.

**Challenges:**
- Slower first launch (squashfs decompression). Less relevant for a background daemon.
- Canonical controls the Snap Store (vendor lock-in concern).
- Snap's classic confinement may be needed if strict confinement blocks D-Bus/Mutter access.

**Snap Architecture for Urutau:**
```yaml
apps:
  daemon:
    command: bin/urutau-daemon
    daemon: simple
    extensions: [gnome]
  ui:
    command: bin/urutau-ui
    extensions: [gnome]
    desktop: share/applications/urutau.desktop
```
The `install` hook would copy the GJS extension and enable it via `gnome-extensions enable`.

### Flatpak — Partial Fit

Flatpak excels at desktop GUI apps but struggles with:
- **Daemons**: Not designed for background services. No native daemon lifecycle management.
- **GNOME Extensions**: Cannot install extensions outside the sandbox.
- **System integration**: Restricted D-Bus and filesystem access by design.

Flatpak could work for just the UI component, but the daemon still needs separate distribution (Snap or .deb). This split adds complexity without benefit.

### Native .deb / PPA — Viable Alternative

A `.deb` package via a PPA provides the best system integration:
- Full control over file placement (extension, service files, binary).
- Native `apt` integration for dependencies.
- Pre/post-install scripts for extension setup.

**Drawbacks:**
- Higher maintenance burden (packaging, dependency management, multi-arch builds).
- PPA approval process.
- No auto-updates (users must `apt upgrade`).
- Zig's static compilation reduces the dependency advantage.

### Decision

**Recommended: Snap** as the primary distribution format for Ubuntu.

| Criteria | Snap | AppImage | Flatpak | .deb |
|----------|------|----------|---------|------|
| Daemon support | ✅ Native | ❌ | ⚠️ Workaround | ✅ |
| GNOME Extension | ✅ Hooks | ❌ | ❌ | ✅ postinst |
| D-Bus | ✅ Native | ❌ | ⚠️ Restricted | ✅ |
| Auto-update | ✅ | ❌ | ⚠️ Manual | ❌ |
| Ubuntu default | ✅ | ❌ | ❌ | ✅ |
| Maintenance | Medium | Low | Medium | High |

**Fallback**: If Snap confinement causes issues with Mutter/D-Bus access, a `.deb` via PPA is the alternative. AppImage should not be considered for this project.

### Implementation Notes (Snap)
- Use `core22` base (Ubuntu 22.04 runtime).
- Leverage the `gnome` extension for GTK4/Libadwaita.
- The GJS extension is bundled in the snap and installed to `~/.local/share/gnome-shell/extensions/urutau@urutau.io/` via an `install` hook.
- The `snap.yaml` defines the daemon as `daemon: simple` with `restart-condition: on-failure`.
- D-Bus interface slot for `org.urutau.Daemon` service activation.

## References
- [ziglua](https://github.com/natecraddock/ziglua)
- [GTK4 / Libadwaita Docs](https://docs.gtk.org/gtk4/)
- [GNOME Shell Extension Guide](https://gjs.guide/extensions/)
- [Snapcraft Documentation](https://snapcraft.io/docs)
- [Snap GNOME Extension](https://snapcraft.io/docs/gnome-extension)
- [zig_appimage](https://github.com/dantecatalfamo/zig_appimage)
- [Zig App Release via GitHub](https://dbushell.com/2025/03/18/zig-app-release-and-updates-via-github)
