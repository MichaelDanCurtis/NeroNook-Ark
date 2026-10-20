#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin="$(swift build -c release --show-bin-path)"
mkdir -p "$PWD/build"
reference="$PWD/build/Ark Module.app"
identity="$(python3 scripts/signing.py identity --bundle cafe.nero.plugin.ark --reference "$reference")"
staging="$(mktemp -d "$PWD/build/.ark-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Ark Module.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -R "$bin/NookPluginSDK_NookPluginSDK.bundle" "$app/Contents/Resources/"
cp "$bin/ArkPlugin" "$app/Contents/MacOS/ArkPlugin"
ditto Resources/Views "$app/Contents/Resources/Views"
cp Resources/NookPlugin.json "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>cafe.nero.plugin.ark</string><key>CFBundleName</key><string>Ark Module</string><key>CFBundleExecutable</key><string>ArkPlugin</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.4.3</string><key>CFBundleVersion</key><string>7</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>LSUIElement</key><true/><key>NSLocalNetworkUsageDescription</key><string>Find and control your selected Odyssey Ark monitor directly on your local network.</string><key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict></dict></plist>
PLIST
python3 scripts/signing.py sign --identity "$identity" "$app"
python3 scripts/signing.py verify --reference "$reference" "$app"
if [[ -d "$reference" ]]; then mv "$reference" "$PWD/build/Ark Module.previous.$(date +%Y%m%d%H%M%S).app"; fi
mv "$app" "$reference"
