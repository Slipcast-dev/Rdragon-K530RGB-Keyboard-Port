import Foundation

/// Изолированные проверки сохранения; реальная пользовательская библиотека не открывается.
@main
struct LightingProfileStoreTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("K530ProfileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/profiles.json")
        let store = LightingProfileStore(url: url)
        let absent = try store.load(); precondition(absent == nil)
        var document = LightingProfileDocument.defaults()
        document.profiles[0].settings.red = 255
        document.profiles[1].settings.mode = 6
        document.selectedID = document.profiles[1].id
        try store.save(document)
        let loaded = try store.load()
        precondition(loaded == document)
        precondition(loaded?.profiles[0].settings != loaded?.profiles[1].settings)
        func rejects(_ action: () throws -> Void) {
            do { try action(); fatalError("Недопустимые данные приняты") } catch { }
        }
        let original = try Data(contentsOf: url)
        var invalid = document; invalid.profiles[0].name = " \n "
        rejects { try store.save(invalid) }
        invalid = document; invalid.profiles[0].settings.brightness = 2.5
        rejects { try store.save(invalid) }
        invalid = document; invalid.profiles[0].settings.speed = 0
        rejects { try store.save(invalid) }
        invalid = document; invalid.profiles[0].settings.mode = 19
        rejects { try store.save(invalid) }
        invalid = document; invalid.profiles[1].id = invalid.profiles[0].id
        rejects { try store.save(invalid) }
        invalid = document; invalid.selectedID = UUID()
        rejects { try store.save(invalid) }
        invalid = document; invalid.version = 2
        rejects { try store.save(invalid) }
        let unchanged = try Data(contentsOf: url); precondition(unchanged == original)
        // Даже синтаксически корректный JSON должен пройти проверку значений при чтении.
        invalid = document; invalid.profiles[0].settings.speed = 9
        let forged = try JSONEncoder().encode(invalid)
        try forged.write(to: url)
        rejects { _ = try store.load() }
        rejects { try store.save(document) }
        let forgedPreserved = try Data(contentsOf: url); precondition(forgedPreserved == forged)
        let corrupt = Data("broken JSON".utf8)
        try corrupt.write(to: url)
        rejects { _ = try store.load() }
        rejects { try store.save(document) }
        let preserved = try Data(contentsOf: url); precondition(preserved == corrupt)
        print("LightingProfileStore: roundtrip, isolation, validation, corruption preservation passed")
    }
}
