#!/bin/sh
# Собирает локальный выпуск: DMG для установки, ZIP для обновления и подписанный manifest.
# Закрытый ключ остаётся вне проекта. Ничего не публикуется в сеть.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
OUTPUT_DIR="$PROJECT_ROOT/dist"
LEGACY_KEY="$HOME/Library/Application Support/K530Lighting/ReleaseKeys/update-signing.key"
PUBLIC_KEY="$SCRIPT_DIR/UpdatePublicKey.txt"
MODULE_CACHE="${SWIFT_MODULECACHE_PATH:-$SCRIPT_DIR/.build/ModuleCache}"

# Источник закрытого ключа: K530_UPDATE_PRIVATE_KEY (файл или "keychain"), иначе связка ключей входа.
# Прежний файл в Application Support поддерживается, но с предупреждением.
if [ -n "${K530_UPDATE_PRIVATE_KEY:-}" ]; then
  PRIVATE_KEY=$K530_UPDATE_PRIVATE_KEY
elif [ -r "$LEGACY_KEY" ]; then
  PRIVATE_KEY=$LEGACY_KEY
  echo "Внимание: закрытый ключ хранится обычным файлом. Перенесите его в связку ключей: см. docs/UPDATES_RU.md." >&2
else
  PRIVATE_KEY=keychain
fi
if [ ! -r "$PUBLIC_KEY" ] || { [ "$PRIVATE_KEY" != keychain ] && [ ! -r "$PRIVATE_KEY" ]; }; then
  echo "Не найдены ключи подписи обновлений. См. docs/UPDATES_RU.md; закрытый ключ должен храниться вне проекта." >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"
WORK_DIR=$(mktemp -d "$OUTPUT_DIR/.package.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

"$SCRIPT_DIR/build.sh" universal
APP="$SCRIPT_DIR/.build/K530Lighting.app"
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
BASE="K530Lighting-$VERSION-macOS-universal"

# ZIP содержит только bundle в корне — именно такую структуру ожидает AppUpdater.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK_DIR/$BASE.zip"
mkdir "$WORK_DIR/image"
ditto "$APP" "$WORK_DIR/image/K530Lighting.app"
ln -s /Applications "$WORK_DIR/image/Applications"
cat > "$WORK_DIR/image/Установка.txt" <<'INSTALL'
K530 Lighting

1. Закройте работающую копию через меню значка → «Завершить K530 Lighting».
2. Перетащите K530Lighting.app в папку Applications («Программы»).
3. Извлеките этот образ и запускайте приложение из «Программ».
4. Подключите Redragon K530 по USB.
5. Разрешите K530Lighting в «Конфиденциальность и безопасность → Мониторинг ввода».
   Для старой записи после обновления может потребоваться удалить её и добавить новую .app.
6. Перезапустите приложение. Левый щелчок значка открывает панель, правый — быстрое меню.
7. Кнопка RU/EN рядом с шестерёнкой меняет язык интерфейса и справки без перезапуска; выбор сохраняется.

Профили приложения — именованные наборы настроек, сохраняемые на этом Mac.
Выбор профиля загружает черновик; «Применить» записывает его в клавиатуру.
Приложение подписано ad-hoc и не нотаризовано.
INSTALL
cat > "$WORK_DIR/image/README_Installation_EN.txt" <<'INSTALL_EN'
K530 Lighting

1. Quit the running copy using the menu bar icon: Quit K530 Lighting.
2. Drag K530Lighting.app to Applications.
3. Eject this disk image and launch the app from Applications.
4. Connect the Redragon K530 over USB.
5. Allow K530Lighting in Privacy & Security > Input Monitoring.
   An older permission entry may need to be removed and the current .app added again.
6. Restart the app. Left-click the menu bar icon to open the panel; right-click for quick actions.
7. Click RU/EN beside the gear to change the interface and help language immediately. The choice is remembered.

The default language is Russian; use the header language button to select English.
Local app profiles are named settings stored on this Mac.
Selecting a profile loads its draft; Apply writes settings to the keyboard.
The app is ad-hoc signed and is not notarized.
INSTALL_EN
hdiutil create -quiet -volname "K530 Lighting $VERSION" -srcfolder "$WORK_DIR/image" -format UDZO "$WORK_DIR/$BASE.dmg"
hdiutil verify -quiet "$WORK_DIR/$BASE.dmg"

python3 - "$WORK_DIR" "$BASE" "$VERSION" "$BUILD" <<'PY'
import hashlib
import json
import pathlib
import sys
work, base, version, build = sys.argv[1:]
root = pathlib.Path(work)
archive = root / (base + '.zip')
manifest = {
    'version': version,
    'build': int(build),
    'archive': 'https://github.com/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/download/v' + version + '/' + archive.name,
    'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
    'minimumSystemVersion': '11.0',
}
(root / 'update.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY
swiftc -module-cache-path "$MODULE_CACHE" -framework CryptoKit -framework Security "$SCRIPT_DIR/Updates/SignUpdate.swift" -o "$WORK_DIR/sign-update"
"$WORK_DIR/sign-update" sign "$PRIVATE_KEY" "$WORK_DIR/update.json" "$WORK_DIR/update.json.sig"

# Проверяем, что подпись создана ключом, доверенным собранному приложению
# (файл может содержать несколько ключей на период их смены).
cat > "$WORK_DIR/VerifyUpdate.swift" <<'SWIFT'
import Foundation
import CryptoKit
let args = CommandLine.arguments
let keys = try String(contentsOfFile: args[1]).split(whereSeparator: \.isNewline)
    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    .compactMap { Data(base64Encoded: $0) }.compactMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
let signatureText = try String(contentsOfFile: args[3]).trimmingCharacters(in: .whitespacesAndNewlines)
guard !keys.isEmpty, let signature = Data(base64Encoded: signatureText) else {
    fputs("Неверный формат публичного ключа или подписи.\n", stderr); exit(1)
}
let bytes = try Data(contentsOf: URL(fileURLWithPath: args[2]))
guard keys.contains(where: { $0.isValidSignature(signature, for: bytes) }) else {
    fputs("Закрытый ключ не соответствует ключу приложения. Выпуск отменён.\n", stderr); exit(1)
}
SWIFT
swiftc -module-cache-path "$MODULE_CACHE" -framework CryptoKit "$WORK_DIR/VerifyUpdate.swift" -o "$WORK_DIR/verify-update"
"$WORK_DIR/verify-update" "$APP/Contents/Resources/UpdatePublicKey.txt" "$WORK_DIR/update.json" "$WORK_DIR/update.json.sig"
python3 - "$WORK_DIR" "$BASE" <<'PY'
import hashlib
import pathlib
import sys
root, base = pathlib.Path(sys.argv[1]), sys.argv[2]
names = [base + '.dmg', base + '.zip', 'update.json', 'update.json.sig']
lines = [hashlib.sha256((root / name).read_bytes()).hexdigest() + '  ' + name for name in names]
(root / 'SHA256SUMS').write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
for name in "$BASE.dmg" "$BASE.zip" update.json update.json.sig SHA256SUMS; do
  mv -f "$WORK_DIR/$name" "$OUTPUT_DIR/$name"
done
printf 'Выпуск %s (build %s) сохранён: %s\n' "$VERSION" "$BUILD" "$OUTPUT_DIR"
