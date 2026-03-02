#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ICONSET_DIR="$PROJECT_DIR/SttTool/Resources/AppIcon.iconset"
ICNS_PATH="$PROJECT_DIR/SttTool/Resources/AppIcon.icns"

echo "Generating app icon..."

# Run Swift script to generate iconset PNGs
swift "$SCRIPT_DIR/generate-icon.swift"

# Convert iconset to icns
echo ""
echo "Converting iconset to icns..."
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

# Clean up iconset directory
rm -rf "$ICONSET_DIR"

FILESIZE=$(stat -f%z "$ICNS_PATH" 2>/dev/null || stat --format=%s "$ICNS_PATH" 2>/dev/null || echo "unknown")
echo "Generated AppIcon.icns ($FILESIZE bytes)"
echo "Output: $ICNS_PATH"
