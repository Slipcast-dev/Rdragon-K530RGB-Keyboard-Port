#!/bin/sh
# Сборка K530Lighting.app без Xcode (достаточно Command Line Tools).
# По умолчанию — архитектура этого Mac; "./build.sh universal" — Intel + Apple Silicon (дольше).
# Второй аргумент "install" копирует приложение в ~/Applications: "./build.sh universal install".
set -eu
cd "$(dirname "$0")"
SH=../k530diag/Sources/k530diag
APP=.build/K530Lighting.app
mkdir -p .build .build/ModuleCache "$APP/Contents/MacOS"
# Локальный кэш пригоден и для обычной сборки, и для ограниченной среды Codex.
MODULE_CACHE="${SWIFT_MODULECACHE_PATH:-$(pwd)/.build/ModuleCache}"
if [ "${1:-}" = "universal" ]; then
  for arch in x86_64 arm64; do
    swiftc -module-cache-path "$MODULE_CACHE" -O -target $arch-apple-macos11 $SH/Protocol.swift $SH/Session.swift Sources/*.swift -o .build/k530menu-$arch
  done
  lipo -create .build/k530menu-x86_64 .build/k530menu-arm64 -output .build/K530Lighting-universal
  mv -f .build/K530Lighting-universal "$APP/Contents/MacOS/K530Lighting"
else
  # Оптимизированная сборка: именно она попадает в ~/Applications по "./build.sh install".
  swiftc -module-cache-path "$MODULE_CACHE" -O $SH/Protocol.swift $SH/Session.swift Sources/*.swift -o .build/K530Lighting-native
  mv -f .build/K530Lighting-native "$APP/Contents/MacOS/K530Lighting"
fi
# Иконки (приложение и строка меню) из исходной PNG-эмблемы
python3 -I Icon/make_icons.py >/dev/null
mkdir -p "$APP/Contents/Resources"
cp .build/icons/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ".build/icons/StatusIcon@2x.png" "$APP/Contents/Resources/StatusIcon@2x.png"
rm -f "$APP/Contents/Resources/UpdatePublicKey.txt"
if [ -f UpdatePublicKey.txt ]; then
  cp UpdatePublicKey.txt "$APP/Contents/Resources/UpdatePublicKey.txt"
fi
cp ../../docs/FAQ_RU.md "$APP/Contents/Resources/FAQ.md"
cp ../../docs/FAQ_RU.md "$APP/Contents/Resources/FAQ_RU.md"
cp ../../docs/FAQ_EN.md "$APP/Contents/Resources/FAQ_EN.md"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>K530Lighting</string>
  <key>CFBundleDisplayName</key><string>K530 Lighting</string>
  <key>CFBundleIdentifier</key><string>dev.slipcast.k530lighting</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>K530Lighting</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.4.0</string>
  <key>CFBundleVersion</key><string>7</string>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>CFBundleLocalizations</key><array><string>ru</string><string>en</string></array>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Готово: $(pwd)/$APP"
if [ "${2:-}" = "install" ] || [ "${1:-}" = "install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/K530Lighting.app"
  cp -R "$APP" "$HOME/Applications/K530Lighting.app"
  echo "Установлено: $HOME/Applications/K530Lighting.app (стабильный путь для автозапуска и разрешений)"
fi
