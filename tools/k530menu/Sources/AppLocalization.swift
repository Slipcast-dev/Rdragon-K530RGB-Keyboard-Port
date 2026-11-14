import Foundation
import Combine

/// Язык приложения задаётся явно и не меняет системную локаль macOS.
enum AppLanguage: String, CaseIterable {
    case russian = "ru"
    case english = "en"
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("K530Lighting.AppLanguageDidChange")
}

/// Единый источник языка для SwiftUI и AppKit. По умолчанию сохраняем
/// прежний русский интерфейс; переключение переживает перезапуск приложения.
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()
    static let preferenceKey = "interfaceLanguage"
    private let defaults: UserDefaults
    @Published private(set) var language: AppLanguage

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .russian
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        defaults.set(language.rawValue, forKey: Self.preferenceKey)
        NotificationCenter.default.post(name: .appLanguageDidChange, object: self)
    }

    func toggle() { setLanguage(language == .russian ? .english : .russian) }
    func text(_ russian: String, _ english: String) -> String {
        language == .russian ? russian : english
    }
}

/// Обе версии хранятся вместе: динамические параметры подставляются одинаково,
/// а сообщение, созданное до смены языка, не остаётся на старом языке.
struct AppText: Equatable {
    let russian: String
    let english: String
    init(_ russian: String, _ english: String) {
        self.russian = russian; self.english = english
    }
    var value: String { AppLocalization.shared.text(russian, english) }
}

/// Ошибки приложения сохраняют обе версии до момента отображения.
protocol AppLocalizedError: LocalizedError {
    var appText: AppText { get }
}
extension AppLocalizedError {
    var errorDescription: String? { appText.value }
}

func L(_ russian: String, _ english: String) -> String {
    AppLocalization.shared.text(russian, english)
}
