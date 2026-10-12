#!/bin/bash
# Renders the PNGs from the SVG sources. Needs rsvg-convert (brew install librsvg).
# Usage: Scripts/render-icon.sh [app-icon-set-dir] [menu-bar-dir]
# Defaults: Packaging/Assets.xcassets/AppIcon.appiconset and Packaging/MenuBar.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || { echo "error: rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
ICON_SET="${1:-Packaging/Assets.xcassets/AppIcon.appiconset}"
MENU_DIR="${2:-Packaging/MenuBar}"
mkdir -p "$ICON_SET" "$MENU_DIR"

# Source: Packaging/AppIcon.svg (1024 px canvas). Sizes match Contents.json.
render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }
for px in 16 32 128 256 512; do
    render Packaging/AppIcon.svg "$px" "$ICON_SET/icon_${px}x${px}.png"
    render Packaging/AppIcon.svg "$((px * 2))" "$ICON_SET/icon_${px}x${px}@2x.png"
done

# Menu bar template: black on transparent, read as a template image by AppKit.
render Packaging/MenuBarTemplate.svg 18 "$MENU_DIR/menubar-template-18.png"
render Packaging/MenuBarTemplate.svg 36 "$MENU_DIR/menubar-template-18@2x.png"
echo "rendered $ICON_SET and $MENU_DIR"
