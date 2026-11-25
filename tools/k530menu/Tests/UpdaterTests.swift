import Foundation
import CryptoKit

/// Регрессии доверия: отклоняем изменённый JSON и чужой ключ, неверный адрес, откат build и несовместимую macOS.
@main
struct UpdaterTests {
    static func main() throws {
        assert(UpdateManifest.newer("0.10.0", than: "0.2.0"))
        assert(!UpdateManifest.newer("0.2.0", than: "0.2.0"))
        let key = Curve25519.Signing.PrivateKey()
        let manifest = UpdateManifest(version: "0.3.0", build: 3,
            archive: "https://github.com/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/download/v0.3.0/K530Lighting.zip",
            sha256: String(repeating: "a", count: 64), minimumSystemVersion: "11.0")
        let data = try JSONEncoder().encode(manifest), signature = try key.signature(for: data)
        _ = try UpdateManifest.decodeSigned(data, signature: signature, publicKey: key.publicKey.rawRepresentation)
        _ = try manifest.validate(currentBuild: 2)
        func rejects(_ operation: () throws -> Void) {
            do { try operation(); fatalError("Опасные данные приняты") } catch { }
        }
        rejects { _ = try UpdateManifest.decodeSigned(data + Data([32]), signature: signature, publicKey: key.publicKey.rawRepresentation) }
        rejects { _ = try UpdateManifest.decodeSigned(data, signature: signature, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation) }
        rejects { _ = try manifest.validate(currentBuild: 3) }
        for badURL in ["http://github.com/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/download/v1/a.zip", "https://evil.example/a.zip", "https://github.com/other/repo/releases/download/v1/a.zip"] {
            rejects { _ = try UpdateManifest(version: "0.3.0", build: 3, archive: badURL, sha256: manifest.sha256, minimumSystemVersion: "11.0").validate(currentBuild: 2) }
        }
        rejects { _ = try UpdateManifest(version: "0.3.0", build: 3, archive: manifest.archive, sha256: "bad", minimumSystemVersion: "11.0").validate(currentBuild: 2) }
        rejects { _ = try UpdateManifest(version: "0.3.0", build: 3, archive: manifest.archive, sha256: manifest.sha256, minimumSystemVersion: "99.0").validate(currentBuild: 2) }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("UpdaterTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let old = root.appendingPathComponent("Installed.app"), new = root.appendingPathComponent("New.app")
        try Data("old".utf8).write(to: old)
        try Data("new".utf8).write(to: new)
        rejects { _ = try UpdateInstaller.replace(source: new, destination: old) { throw UpdateFailure.network } }
        let restored = try String(contentsOf: old); assert(restored == "old")
        let backup = try UpdateInstaller.replace(source: new, destination: old) { }
        assert((try? String(contentsOf: old)) == "new")
        assert((try? String(contentsOf: backup)) == "old")
        rejects { _ = try UpdateInstaller.replace(source: root.appendingPathComponent("Missing.app"), destination: old) { } }
        assert((try? String(contentsOf: old)) == "new")
        // Смена ключа: подпись любым из доверенных ключей принимается, посторонним — нет.
        let next = Curve25519.Signing.PrivateKey()
        let both = [key.publicKey.rawRepresentation, next.publicKey.rawRepresentation]
        _ = try UpdateManifest.decodeSigned(data, signature: try next.signature(for: data), publicKeys: both)
        rejects { _ = try UpdateManifest.decodeSigned(data, signature: try Curve25519.Signing.PrivateKey().signature(for: data), publicKeys: both) }
        rejects { _ = try UpdateManifest.decodeSigned(data, signature: signature, publicKeys: []) }
        let keyFile = "# текущий\n" + both.map { $0.base64EncodedString() }.joined(separator: "\n\n") + "\nнеключ\n" + Data([1, 2]).base64EncodedString() + "\n"
        assert(UpdateManifest.trustedKeys(from: keyFile) == both)

        // Неудачный запуск после замены каталога-.app возвращает прежнюю версию целиком.
        let installed = root.appendingPathComponent("Dir.app"), candidate = root.appendingPathComponent("DirNew.app")
        try fm.createDirectory(at: installed, withIntermediateDirectories: true)
        try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: installed.appendingPathComponent("marker"))
        try Data("new".utf8).write(to: candidate.appendingPathComponent("marker"))
        rejects { _ = try UpdateInstaller.replace(source: candidate, destination: installed) { throw UpdateFailure.network } }
        assert((try? String(contentsOf: installed.appendingPathComponent("marker"))) == "old")

        // Очистка удаляет только копии replace и не трогает остальное.
        UpdateInstaller.removeLeftovers(in: root)
        let leftovers = try fm.contentsOfDirectory(atPath: root.path)
        assert(!leftovers.contains { $0.hasPrefix(UpdateInstaller.backupPrefix) || $0.hasPrefix(UpdateInstaller.updatePrefix) }, "\(leftovers)")
        let decoy = root.appendingPathComponent(UpdateInstaller.backupPrefix + "not-a-uuid.app")
        try Data().write(to: decoy)
        UpdateInstaller.removeLeftovers(in: root)
        assert(fm.fileExists(atPath: decoy.path) && fm.fileExists(atPath: old.path) && fm.fileExists(atPath: installed.path))
        print("UpdaterTests: passed (signature, tampering, trust, key rotation, URL, build, hash, OS, rollback, cleanup)")
    }
}
