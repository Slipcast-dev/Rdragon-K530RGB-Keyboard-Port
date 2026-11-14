import Foundation
import CryptoKit

// Служебная программа выпуска. Закрытый ключ никогда не попадает в приложение или вывод терминала.
// swift SignUpdate.swift keygen /защищённый/путь/private.key UpdatePublicKey.txt
// swift SignUpdate.swift sign /защищённый/путь/private.key update.json update.json.sig
let args = CommandLine.arguments
func die(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
do {
    guard args.count >= 2 else { die("Команды: keygen PRIVATE PUBLIC | sign PRIVATE MANIFEST SIGNATURE") }
    if args[1] == "keygen", args.count == 4 {
        let privateURL = URL(fileURLWithPath: args[2]), publicURL = URL(fileURLWithPath: args[3])
        guard !FileManager.default.fileExists(atPath: privateURL.path), !FileManager.default.fileExists(atPath: publicURL.path) else { die("Файлы уже существуют. Перезапись ключа запрещена.") }
        let key = Curve25519.Signing.PrivateKey()
        guard FileManager.default.createFile(atPath: privateURL.path, contents: key.rawRepresentation,
                                             attributes: [.posixPermissions: 0o600]) else { die("Не удалось сохранить закрытый ключ") }
        try (key.publicKey.rawRepresentation.base64EncodedString() + "\n").write(to: publicURL, atomically: true, encoding: .utf8)
        print("Ключи сохранены. Храните закрытый ключ отдельно от репозитория.")
    } else if args[1] == "sign", args.count == 5 {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let bytes = try Data(contentsOf: URL(fileURLWithPath: args[3]))
        let signature = try key.signature(for: bytes)
        try (signature.base64EncodedString() + "\n").write(toFile: args[4], atomically: true, encoding: .utf8)
        print("Подпись сохранена.")
    } else { die("Аргументы: keygen PRIVATE PUBLIC | sign PRIVATE MANIFEST SIGNATURE") }
} catch { die(error.localizedDescription) }
