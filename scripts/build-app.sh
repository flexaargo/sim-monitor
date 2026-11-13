#!/bin/bash
# Builds SimMonitor.app into ./build. Pass --install to also copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

# The version comes from $VERSION, else the latest tag. The build number is the commit count.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# Universal, so one download runs on Apple silicon and Intel.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release --product SimMonitor "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/SimMonitor"

APP="build/SimMonitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SimMonitor"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
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
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign with $CODESIGN_IDENTITY, else a Developer ID certificate if the keychain has one,
# else ad hoc. Ad hoc builds run locally but can't be notarized.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $APP ($VERSION, build $BUILD, signed: ${IDENTITY:-ad hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SimMonitor 2>/dev/null || true
    rm -rf "/Applications/SimMonitor.app"
    cp -R "$APP" "/Applications/SimMonitor.app"
    open "/Applications/SimMonitor.app"
    echo "Installed to /Applications/SimMonitor.app and launched"
fi
