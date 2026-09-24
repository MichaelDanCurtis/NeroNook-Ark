#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin="$(swift build -c release --show-bin-path)"
app="$PWD/build/Ark Module.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/ArkPlugin" "$app/Contents/MacOS/ArkPlugin"
ditto Resources/Views "$app/Contents/Resources/Views"
cp Resources/NookPlugin.json "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>cafe.nero.plugin.ark</string><key>CFBundleName</key><string>Ark Module</string><key>CFBundleExecutable</key><string>ArkPlugin</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.2.0</string><key>CFBundleVersion</key><string>2</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>LSUIElement</key><true/><key>NSLocalNetworkUsageDescription</key><string>Find and control your selected Odyssey Ark monitor directly on your local network.</string><key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict></dict></plist>
PLIST
codesign --force --sign "${NERONOOK_SIGNING_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
