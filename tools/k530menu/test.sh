#!/bin/sh
# Регрессии настроек, локальных профилей и обновлений. Клавиатура и сеть не используются.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"
mkdir -p .build/ModuleCache
MODULE_CACHE="${SWIFT_MODULECACHE_PATH:-$SCRIPT_DIR/.build/ModuleCache}"
WORK_DIR=$(mktemp -d "$SCRIPT_DIR/.build/tests.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM
run_test() {
    test_name=$1
    shift
    swiftc -module-cache-path "$MODULE_CACHE" Sources/AppLocalization.swift "$@" -o "$WORK_DIR/$test_name"
    "$WORK_DIR/$test_name"
}
run_test settings Sources/LightingSettings.swift Tests/LightingSettingsTests.swift
run_test profiles Sources/LightingSettings.swift Sources/LightingProfileStore.swift Tests/LightingProfileStoreTests.swift
run_test controller Sources/LightingSettings.swift Sources/LightingProfileStore.swift Sources/LightingController.swift \
    ../k530diag/Sources/k530diag/Protocol.swift ../k530diag/Sources/k530diag/Session.swift Tests/LightingControllerProfileTests.swift
run_test updater -framework CryptoKit Sources/AppUpdater.swift Tests/UpdaterTests.swift
run_test localization -framework CryptoKit Sources/FaqWindowController.swift Sources/AppUpdater.swift Sources/LightingSettings.swift Sources/LightingProfileStore.swift Sources/LightingController.swift \
    ../k530diag/Sources/k530diag/Protocol.swift ../k530diag/Sources/k530diag/Session.swift Tests/AppLocalizationTests.swift
