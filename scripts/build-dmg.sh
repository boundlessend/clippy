#!/bin/bash
# собирает release-бинарь, упаковывает в «Clippy Mac.app» и создаёт нарядный .dmg-установщик
# (create-dmg: окно с иконкой приложения и стрелкой на Applications; фон - assets/dmg-background.png).
# ad-hoc подпись, без Developer ID - при первом запуске: правый клик -> «Открыть».
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"         # версия (semver); в CI берётся из git-тега (release.yml)

APP="build/Clippy Mac.app"          # имя бандла с пробелом - красивее в Finder/установщике
DMG="build/ClippyMac.dmg"           # имя файла загрузки оставляем без пробела
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

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clippy Mac</string>
  <key>CFBundleDisplayName</key><string>Clippy Mac</string>
  <key>CFBundleExecutable</key><string>ClippyMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.clippymac.app</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- ATS по умолчанию режет http; localhost (Ollama) разрешаем через loopback-исключение,
       публичные http остаются запрещены (для них - только https) -->
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
  <key>NSHumanReadableCopyright</key><string>© 2026 boundlessend</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Файл</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.data</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> ad-hoc signing"
# ресурс-бандл SwiftPM плоский и без Info.plist - codesign (macOS 15+/26) такой не
# принимает. Впишем минимальный Info.plist в корень бандла, иначе подпись падает
RESB="$APP/Contents/Resources/$(basename "$RESBUNDLE")"
cat > "$RESB/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.clippymac.resources</string>
  <key>CFBundleName</key><string>ClippyMac_ClippyMac</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
</dict>
</plist>
PLIST

# подписываем вложенный ресурс-бандл, затем сам .app (--deep у codesign помечен deprecated)
codesign --force --sign - "$RESB"
codesign --force --sign - "$APP"

echo "==> creating dmg"
# нарядный установщик (окно с иконкой + стрелка на Applications + фон) через create-dmg.
# на dev-машине shell-версию (create-dmg/create-dmg) может затенять node-версия в PATH -
# берём её строго по brew-префиксу; если create-dmg нет вовсе - простой dmg через hdiutil
CREATE_DMG="$(brew --prefix create-dmg 2>/dev/null)/bin/create-dmg"
[ -x "$CREATE_DMG" ] || CREATE_DMG="$(command -v create-dmg || true)"

if [ -n "${CREATE_DMG:-}" ] && [ -x "$CREATE_DMG" ]; then
  STAGE="build/dmg-src"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"                       # источник для create-dmg: только .app
  "$CREATE_DMG" \
    --volname "Clippy Mac" \
    --volicon assets/AppIcon.icns \
    --background assets/dmg-background.png \
    --window-pos 200 120 \
    --window-size 540 400 \
    --icon-size 128 \
    --icon "Clippy Mac.app" 150 205 \
    --hide-extension "Clippy Mac.app" \
    --app-drop-link 390 205 \
    --no-internet-enable \
    --hdiutil-retries 5 \
    "$DMG" "$STAGE"
  rm -rf "$STAGE"
else
  echo "create-dmg не найден - собираю простой dmg через hdiutil" >&2
  hdiutil create -volname "Clippy Mac" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
fi

echo "==> done: $DMG"
