#!/bin/bash
# Builds build/MouseBar.app (arm64 only, ad-hoc signed). Usage: Scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
if [ ! -d Vendor/MouseBarLogi.xcframework ]; then
    echo "error: Vendor/MouseBarLogi.xcframework is missing. Run Scripts/build-logi.sh first (it needs Rust: https://rustup.rs)." >&2
    exit 1
fi
swift build -c "$CONFIG" --arch arm64 --product MouseBar
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/MouseBar"

APP="build/MouseBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MouseBar"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

# App icon: compile the asset catalog into Assets.car plus AppIcon.icns (source: Packaging/AppIcon.svg).
ICON_INFO="$(mktemp -t mousebar-icon).plist"
xcrun actool Packaging/Assets.xcassets \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_INFO" \
    --output-format human-readable-text \
    --notices --warnings --errors > "$ICON_INFO.log"
if grep -A3 -E "com.apple.actool.(warnings|errors)" "$ICON_INFO.log"; then
    echo "warning: actool reported the messages above" >&2
fi
rm -f "$ICON_INFO" "$ICON_INFO.log"
[ -f "$APP/Contents/Resources/AppIcon.icns" ] || { echo "error: actool did not produce AppIcon.icns" >&2; exit 1; }

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
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
