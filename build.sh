#!/bin/bash
# Builds StickyMac.app in ./build. Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary: runs natively on Apple silicon and Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/StickyMac"

APP=build/StickyMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/StickyMac"

if [ ! -f build/AppIcon.icns ]; then
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>StickyMac</string>
  <key>CFBundleDisplayName</key><string>StickyMac</string>
  <key>CFBundleIdentifier</key><string>com.ferax564.stickymac</string>
  <key>CFBundleExecutable</key><string>StickyMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# SIGN_IDENTITY (a Developer ID Application identity) produces a build that can be notarized.
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x StickyMac || true
  rm -rf /Applications/StickyMac.app
  cp -R "$APP" /Applications/
  open /Applications/StickyMac.app
  echo "Installed to /Applications and launched"
fi
