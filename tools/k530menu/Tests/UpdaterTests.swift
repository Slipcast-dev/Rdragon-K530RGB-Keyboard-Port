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
        print("UpdaterTests: passed (signature, tampering, trust, URL, build, hash, OS)")
    }
}
