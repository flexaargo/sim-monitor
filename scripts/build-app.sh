#!/bin/bash
# Builds SimMonitor.app into ./build. Pass --install to also copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product SimMonitor
BIN="$(swift build -c release --show-bin-path)/SimMonitor"

APP="build/SimMonitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SimMonitor"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Sim Monitor</string>
    <key>CFBundleDisplayName</key><string>Sim Monitor</string>
    <key>CFBundleIdentifier</key><string>local.sim-monitor</string>
    <key>CFBundleExecutable</key><string>SimMonitor</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SimMonitor 2>/dev/null || true
    rm -rf "/Applications/SimMonitor.app"
    cp -R "$APP" "/Applications/SimMonitor.app"
    open "/Applications/SimMonitor.app"
    echo "Installed to /Applications/SimMonitor.app and launched"
fi
