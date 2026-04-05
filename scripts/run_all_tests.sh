#!/usr/bin/env bash
#
# Run all Zig tests for Urutau
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DAEMON_DIR="$PROJECT_ROOT/src/daemon"

echo "=== Running all Zig tests ==="
echo ""

cd "$DAEMON_DIR"

# Run all test steps defined in build.zig
echo "Running D-Bus client tests..."
zig build test-dbus
echo ""

echo "Running storage layer tests..."
zig build test-storage
echo ""

echo "Running Lua VM tests..."
zig build test-lua
echo ""

echo "Running hook execution tests..."
zig build test-hooks
echo ""

echo "=== All tests passed ==="
