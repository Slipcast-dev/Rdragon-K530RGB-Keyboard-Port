import Foundation

/// Именованный локальный набор. Формат хранения независим от HID-профиля клавиатуры.
struct LightingProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var settings: LightingSettings

    init(id: UUID = UUID(), name: String, settings: LightingSettings) {
        self.id = id; self.name = name; self.settings = settings
    }

    private enum CodingKeys: String, CodingKey { case id, name, settings }
    private struct SettingsPayload: Codable {
        let mode: UInt8
        let brightness: Double
        let speed: Double
        let colourful: Bool
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        init(_ settings: LightingSettings) {
            mode = settings.mode; brightness = settings.brightness; speed = settings.speed
            colourful = settings.colourful; red = settings.red; green = settings.green; blue = settings.blue
        }
        var value: LightingSettings {
            var result = LightingSettings()
            result.mode = mode; result.brightness = brightness; result.speed = speed
            result.colourful = colourful; result.red = red; result.green = green; result.blue = blue
            return result
        }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        settings = try container.decode(SettingsPayload.self, forKey: .settings).value
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(SettingsPayload(settings), forKey: .settings)
    }
}

enum LightingProfileError: LocalizedError {
    case unsupportedVersion, invalidProfiles, invalidSettings, damagedFile
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Формат файла профилей не поддерживается. Файл сохранён без изменений."
        case .invalidProfiles: return "Некорректный список профилей: проверьте имена и выбранный профиль."
        case .invalidSettings: return "Профиль содержит недопустимые настройки подсветки."
        case .damagedFile: return "Не удалось прочитать файл профилей. Исходный файл сохранён без изменений."
        }
    }
}

/// Версия относится к JSON-документу, выбранный UUID сохраняется между запусками.
struct LightingProfileDocument: Codable, Equatable {
    var version: Int = 1
    var selectedID: UUID
    var profiles: [LightingProfile]

    static func defaults() -> LightingProfileDocument {
        let profiles = (1...3).map { LightingProfile(name: "Профиль \($0)", settings: LightingSettings()) }
        return LightingProfileDocument(selectedID: profiles[0].id, profiles: profiles)
    }

    func validated() throws {
        guard version == 1 else { throw LightingProfileError.unsupportedVersion }
        guard (1...100).contains(profiles.count),
              Set(profiles.map { $0.id }).count == profiles.count,
              profiles.contains(where: { $0.id == selectedID }) else { throw LightingProfileError.invalidProfiles }
        for profile in profiles {
            let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, profile.name.count <= 80,
                  !profile.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw LightingProfileError.invalidProfiles
            }
            let settings = profile.settings
            guard knownModes.contains(settings.mode), settings.brightness.isFinite, settings.speed.isFinite,
                  (0...4).contains(settings.brightness), (1...5).contains(settings.speed),
                  settings.brightness.rounded() == settings.brightness,
                  settings.speed.rounded() == settings.speed else { throw LightingProfileError.invalidSettings }
        }
    }
}

/// Атомарная запись защищает предыдущую версию от незавершённого сохранения.
/// Повреждённый или более новый формат никогда автоматически не заменяется шаблоном.
final class LightingProfileStore {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/K530Lighting/profiles.json")
    }
    let url: URL
    init(url: URL = LightingProfileStore.defaultURL) { self.url = url }

    func load() throws -> LightingProfileDocument? {
        let bytes: Data
        do { bytes = try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
        guard bytes.count <= 1024 * 1024 else { throw LightingProfileError.damagedFile }
        let document: LightingProfileDocument
        do { document = try JSONDecoder().decode(LightingProfileDocument.self, from: bytes) }
        catch { throw LightingProfileError.damagedFile }
        try document.validated()
        return document
    }

    func save(_ document: LightingProfileDocument) throws {
        try document.validated()
        // Перед заменой проверяем существующие данные: не уничтожаем неизвестный формат.
        _ = try load()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
}
