import Foundation
import CryptoKit
import Security

// Служебная программа выпуска. Закрытый ключ никогда не попадает в приложение или вывод терминала.
// swift SignUpdate.swift keygen /защищённый/путь/private.key UpdatePublicKey.txt
// swift SignUpdate.swift keychain-import /защищённый/путь/private.key   — перенести ключ в связку ключей входа
// swift SignUpdate.swift sign keychain|/путь/private.key update.json update.json.sig
// swift SignUpdate.swift public keychain|/путь/private.key               — напечатать публичный ключ (base64)
let args = CommandLine.arguments
let keychainService = "dev.slipcast.k530.update-signing", keychainAccount = "update-signing"
func die(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }

/// Ключ в связке доступен только на этом Mac и только после разблокировки; не синхронизируется в iCloud.
func keychainImport(_ raw: Data) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
        kSecAttrLabel as String: "K530 Lighting update signing key",
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAttrSynchronizable as String: false,
        kSecValueData as String: raw,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem { die("В связке ключей уже есть ключ подписи. Перезапись запрещена.") }
    guard status == errSecSuccess else { die("Связка ключей вернула ошибку \(status).") }
}

func keychainRead() -> Data {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
        die(status == errSecItemNotFound ? "Ключ подписи не найден в связке ключей (keychain-import)." : "Связка ключей вернула ошибку \(status).")
    }
    return data
}

func loadKey(_ source: String) throws -> Curve25519.Signing.PrivateKey {
    let raw = source == "keychain" ? keychainRead() : try Data(contentsOf: URL(fileURLWithPath: source))
    return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

do {
    guard args.count >= 2 else { die("Команды: keygen PRIVATE PUBLIC | keychain-import PRIVATE | sign SOURCE MANIFEST SIGNATURE | public SOURCE") }
    if args[1] == "keygen", args.count == 4 {
        let privateURL = URL(fileURLWithPath: args[2]), publicURL = URL(fileURLWithPath: args[3])
        guard !FileManager.default.fileExists(atPath: privateURL.path), !FileManager.default.fileExists(atPath: publicURL.path) else { die("Файлы уже существуют. Перезапись ключа запрещена.") }
        let key = Curve25519.Signing.PrivateKey()
        guard FileManager.default.createFile(atPath: privateURL.path, contents: key.rawRepresentation,
                                             attributes: [.posixPermissions: 0o600]) else { die("Не удалось сохранить закрытый ключ") }
        try (key.publicKey.rawRepresentation.base64EncodedString() + "\n").write(to: publicURL, atomically: true, encoding: .utf8)
        print("Ключи сохранены. Перенесите закрытый ключ в связку ключей (keychain-import) и храните резервную копию офлайн.")
    } else if args[1] == "keychain-import", args.count == 3 {
        let key = try loadKey(args[2])
        keychainImport(key.rawRepresentation)
        print("Ключ сохранён в связке ключей. Удалите файл после проверки резервной копии: rm -P \(args[2])")
    } else if args[1] == "sign", args.count == 5 {
        let key = try loadKey(args[2])
        let bytes = try Data(contentsOf: URL(fileURLWithPath: args[3]))
        let signature = try key.signature(for: bytes)
        try (signature.base64EncodedString() + "\n").write(toFile: args[4], atomically: true, encoding: .utf8)
        print("Подпись сохранена.")
    } else if args[1] == "public", args.count == 3 {
        print(try loadKey(args[2]).publicKey.rawRepresentation.base64EncodedString())
    } else { die("Аргументы: keygen PRIVATE PUBLIC | keychain-import PRIVATE | sign SOURCE MANIFEST SIGNATURE | public SOURCE") }
} catch { die(error.localizedDescription) }
