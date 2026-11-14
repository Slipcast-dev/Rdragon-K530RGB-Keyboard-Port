import Foundation

/// Проверяем смену языка и сохранение выбора без HID/сети и без изменения
/// пользовательских профилей. Названия наборов являются данными, а не ключами перевода.
@main
struct AppLocalizationTests {
    static func main() throws {
        let suiteName = "K530LanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let isolated = AppLocalization(defaults: defaults)
        precondition(isolated.language == .russian)
        isolated.setLanguage(.english)
        precondition(AppLocalization(defaults: defaults).language == .english)
        isolated.toggle()
        precondition(AppLocalization(defaults: defaults).language == .russian)
        defaults.set("unsupported", forKey: AppLocalization.preferenceKey)
        precondition(AppLocalization(defaults: defaults).language == .russian)

        let language = AppLocalization.shared
        let previousLanguage = language.language
        let previousPreference = UserDefaults.standard.object(forKey: AppLocalization.preferenceKey)
        defer {
            language.setLanguage(previousLanguage)
            if let previous = previousPreference { UserDefaults.standard.set(previous, forKey: AppLocalization.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: AppLocalization.preferenceKey) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("K530LanguageProfiles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LightingProfileStore(url: directory.appendingPathComponent("profiles.json"))
        language.setLanguage(.russian)
        let controller = LightingController(profileStore: store)
        controller.saveProfile(name: "Мой профиль / My profile")
        let initialSettings = controller.draft
        let name = controller.selectedProfile?.name
        let persisted = try Data(contentsOf: store.url)
        precondition(FaqWindowController.resourceName(for: .russian) == "FAQ_RU")
        precondition(FaqWindowController.resourceName(for: .english) == "FAQ_EN")
        let updater = AppUpdater()
        precondition(updater.message == "Обновления проверяются автоматически")
        let installError = UpdateFailure.installation(AppText("нет доступа", "access denied"))
        precondition(installError.localizedDescription.contains("нет доступа"))
        let existing = AppText("Готово", "Ready")
        precondition(existing.value == "Готово")
        precondition(controller.message.contains("сохранён"))
        let ruError = LightingProfileError.invalidSettings.localizedDescription
        language.setLanguage(.english)
        precondition(existing.value == "Ready")
        precondition(updater.message == "Updates are checked automatically")
        precondition(installError.localizedDescription == "Could not install the update: access denied")
        precondition(controller.message == "Profile “Мой профиль / My profile” saved")
        precondition(LightingProfileError.invalidSettings.localizedDescription != ruError)
        precondition(controller.selectedProfile?.name == name && controller.draft == initialSettings)
        let afterSwitch = try Data(contentsOf: store.url)
        precondition(afterSwitch == persisted)
        precondition(LightingProfileDocument.defaults().profiles[0].name == "Profile 1")
        for mode in modes { precondition(localizedModeName(mode.id) == mode.name) }
        for preset in presets { precondition(preset.localizedName.range(of: "[А-Яа-яЁё]", options: .regularExpression) == nil) }
        precondition(localizedBrightnessName(0) == "0 — off")
        language.setLanguage(.russian)
        precondition(controller.message.contains("сохранён"))
        precondition(localizedModeName(5) == "Дыхание")
        print("AppLocalization: language persistence, fallback, live messages/errors, profile preservation and translated names passed")
    }
}
