#!/bin/bash
# собирает release-бинарь, упаковывает в ClippyMac.app и создаёт .dmg.
# ad-hoc подпись, без Developer ID - при первом запуске: правый клик -> «Открыть».
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/ClippyMac.app"
DMG="build/ClippyMac.dmg"
BIN=".build/release/ClippyMac"
RESBUNDLE=".build/release/ClippyMac_ClippyMac.bundle"

echo "==> building release"
swift build -c release

echo "==> packaging .app"
rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClippyMac"
cp -R "$RESBUNDLE" "$APP/Contents/Resources/"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClippyMac</string>
  <key>CFBundleDisplayName</key><string>Clippy</string>
  <key>CFBundleExecutable</key><string>ClippyMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.clippymac.app</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc signing"
codesign --force --deep --sign - "$APP" || echo "codesign skipped"

echo "==> creating dmg"
hdiutil create -volname "ClippyMac" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

echo "==> done: $DMG"
