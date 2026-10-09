#!/bin/bash
# Builds build/MouseBar.app (arm64 only, ad-hoc signed). Usage: Scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG" --arch arm64 --product MouseBar
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/MouseBar"

APP="build/MouseBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MouseBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MouseBar</string>
    <key>CFBundleDisplayName</key><string>MouseBar</string>
    <key>CFBundleIdentifier</key><string>dev.mousebar.MouseBar</string>
    <key>CFBundleExecutable</key><string>MouseBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built $APP"
echo "archs: $(lipo -archs "$APP/Contents/MacOS/MouseBar")"
