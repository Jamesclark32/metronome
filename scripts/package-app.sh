#!/bin/bash
# Builds an ad-hoc signed build/Metronome.app for Apple silicon.
# Usage: scripts/package-app.sh [version]   (default: 0.0.0-dev)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-0.0.0-dev}"
APP="build/Metronome.app"

swift build -c release --arch arm64 --product MetronomeApp
swift build -c release --arch arm64 --product metronome
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN/MetronomeApp" "$APP/Contents/MacOS/Metronome"
# The CLI lives in Helpers: Contents/MacOS/metronome would collide with
# Contents/MacOS/Metronome on a case-insensitive file system.
cp "$BIN/metronome" "$APP/Contents/Helpers/metronome"
codesign --force --sign - --identifier com.jamesclark32.metronome.cli "$APP/Contents/Helpers/metronome"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.jamesclark32.metronome</string>
    <key>CFBundleName</key><string>Metronome</string>
    <key>CFBundleDisplayName</key><string>Metronome</string>
    <key>CFBundleExecutable</key><string>Metronome</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --sign - --identifier com.jamesclark32.metronome "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION)"
