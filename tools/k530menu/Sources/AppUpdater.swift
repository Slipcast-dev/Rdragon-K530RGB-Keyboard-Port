import AppKit
import Combine
import CryptoKit

/// Подписанное описание обновления. Подпись относится к исходным байтам JSON, а не к его сериализации.
struct UpdateManifest: Codable {
    let version: String
    let build: Int
    let archive: String
    let sha256: String
    let minimumSystemVersion: String

    /// Проверка подписи до декодирования исключает подмену URL, версии и контрольной суммы.
    /// Достаточно подписи любым из доверенных ключей: так выпуск переходного периода
    /// при смене ключа подписывается старым ключом, а приложение уже знает новый.
    static func decodeSigned(_ bytes: Data, signature: Data, publicKeys: [Data]) throws -> UpdateManifest {
        let keys = publicKeys.compactMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
        guard keys.contains(where: { $0.isValidSignature(signature, for: bytes) }) else { throw UpdateFailure.signature }
        return try JSONDecoder().decode(Self.self, from: bytes)
    }

    static func decodeSigned(_ bytes: Data, signature: Data, publicKey: Data) throws -> UpdateManifest {
        try decodeSigned(bytes, signature: signature, publicKeys: [publicKey])
    }

    /// UpdatePublicKey.txt: по одному ключу Ed25519 (base64) в строке; пустые строки и «#»-комментарии пропускаются.
    static func trustedKeys(from text: String) -> [Data] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { Data(base64Encoded: $0) }
            .filter { (try? Curve25519.Signing.PublicKey(rawRepresentation: $0)) != nil }
    }

    static func newer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    func validate(currentBuild: Int) throws -> URL {
        guard build > currentBuild, !version.isEmpty,
              sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
              let url = URL(string: archive), url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/download/"),
              url.path.hasSuffix(".zip"), url.user == nil, url.password == nil,
              !Self.newer(minimumSystemVersion, than: ProcessInfo.processInfo.operatingSystemVersionStringValue)
        else { throw UpdateFailure.invalidManifest }
        return url
    }
}

private extension ProcessInfo {
    var operatingSystemVersionStringValue: String {
        let v = operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

enum UpdateFailure: AppLocalizedError {
    case invalidManifest, signature, invalidArchive, missingKey, network, installation(AppText)
    var appText: AppText {
        switch self {
        case .invalidManifest:
            return AppText("Некорректное описание обновления или несовместимая версия macOS.",
                           "The update manifest is invalid, or this macOS version is not supported.")
        case .signature:
            return AppText("Подпись обновления не подтверждена. Установка отменена.",
                           "The update signature could not be verified. Installation was cancelled.")
        case .invalidArchive:
            return AppText("Архив повреждён или содержит другое приложение.",
                           "The archive is damaged or contains a different application.")
        case .missingKey:
            return AppText("В этой сборке отсутствует доверенный ключ обновлений. Доступна ручная загрузка со страницы релизов.",
                           "This build has no trusted update key. Download the update manually from Releases.")
        case .network:
            return AppText("Сервер обновлений недоступен. Повторите проверку позже.",
                           "The update server is unavailable. Try again later.")
        case .installation(let detail):
            return AppText("Не удалось установить обновление: \(detail.russian)",
                           "Could not install the update: \(detail.english)")
        }
    }
}

/// Проверяет релизы в фоне. Настройки клавиатуры не затрагиваются; установка начинается только после согласия.
/// Сетевые операции и распаковка не блокируют интерфейс. Изменения опубликованного состояния идут на main.
final class AppUpdater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published private var statusText = AppText("Обновления проверяются автоматически", "Updates are checked automatically")
    var message: String { statusText.value }
    @Published private(set) var progress: Double?
    @Published private(set) var isBusy = false
    /// Версия, найденная проверкой. Автоматическая проверка не открывает модальное окно:
    /// о ней сообщают строка состояния панели и пункт меню значка.
    @Published private(set) var availableVersion: String?
    private(set) var readyToRelaunch = false
    /// Хост запрещает установку во время незавершённого HID-обмена и открывает панель с прогрессом.
    var canStartUpdate: () -> Bool = { true }
    var onPresentationRequested: () -> Void = {}
    private let repository = "https://api.github.com/repos/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/latest"
    private let releasePage = URL(string: "https://github.com/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/latest")!
    private var timer: Timer?
    private var downloadSession: URLSession?
    /// Манифест текущей загрузки. Читается и пишется только на главном потоке.
    private var pendingManifest: UpdateManifest?
    private var checking = false
    private let maximumArchiveSize: Int64 = 250 * 1024 * 1024
    private var currentBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }
    private var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func start() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.removeInstallLeftovers()
            self?.check(manual: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in self?.check(manual: false) }
    }

    func checkManually() { check(manual: true) }

    /// Эта версия проработала 30 с, значит копия прежней установки для ручного отката больше не нужна.
    private func removeInstallLeftovers() {
        let parent = Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent()
        DispatchQueue.global(qos: .utility).async { UpdateInstaller.removeLeftovers(in: parent) }
    }

    private func state(_ text: AppText, progress: Double? = nil) {
        DispatchQueue.main.async { self.statusText = text; self.progress = progress }
    }

    private func check(manual: Bool) {
        guard !checking, !isBusy else { return }
        checking = true
        statusText = AppText("Проверка обновлений…", "Checking for updates…")
        var request = URLRequest(url: URL(string: repository)!)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("K530Lighting/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.checking = false
                guard error == nil, let http = response as? HTTPURLResponse else { self.fail(UpdateFailure.network); return }
                if http.statusCode == 404 {
                    // GitHub скрывает приватные репозитории ответом 404; это
                    // не подтверждает отсутствие обновлений установленной версии.
                    self.statusText = AppText("Проверка недоступна: нет общедоступного релиза или репозиторий закрыт", "Update check unavailable: no public release, or the repository is private")
                    return
                }
                guard http.statusCode == 200, let data = data,
                      let release = try? JSONDecoder().decode(Release.self, from: data) else { self.fail(UpdateFailure.network); return }
                let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                guard !release.prerelease, !release.draft, UpdateManifest.newer(version, than: self.currentVersion) else {
                    self.availableVersion = nil
                    self.statusText = AppText("Установлена актуальная версия", "You have the latest version"); return
                }
                self.availableVersion = version
                self.statusText = AppText("Доступна версия \(version)", "Version \(version) is available")
                // Фоновая проверка не перехватывает фокус: установка — по команде пользователя.
                guard manual else { return }
                let alert = NSAlert()
                alert.messageText = L("Доступна K530 Lighting \(version)", "K530 Lighting \(version) is available")
                alert.informativeText = L("Скачать обновление? После проверки оно установится автоматически, и приложение перезапустится.",
                                          "Download the update? After verification, it will install automatically and the app will restart.")
                alert.addButton(withTitle: L("Скачать", "Download"))
                alert.addButton(withTitle: L("Позже", "Later"))
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                guard self.canStartUpdate() else {
                    self.statusText = AppText("Дождитесь завершения операции с клавиатурой и повторите обновление.", "Wait for the keyboard operation to finish, then try the update again.")
                    return
                }
                self.onPresentationRequested()
                self.prepare(release)
            }
        }.resume()
    }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let prerelease: Bool
        let draft: Bool
        let assets: [Asset]
    }

    /// Вызывается на главном потоке. Временный каталог удаляет тот, кто его создал.
    private func fail(_ error: Error) {
        if let localized = error as? AppLocalizedError {
            statusText = localized.appText
        } else {
            // Системный текст ошибки остаётся в языке macOS; наше пояснение
            // сохраняет обе версии и меняется вместе с интерфейсом.
            let detail = error.localizedDescription
            statusText = AppText("Ошибка обновления: \(detail)", "Update error: \(detail)")
        }
        progress = nil
        isBusy = false
        pendingManifest = nil
    }

    /// Получает только небольшие служебные файлы, не блокируя потоки ожиданием.
    /// Подлинность JSON проверяется встроенным публичным ключом.
    private func fetch(_ url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        guard url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/download/") else {
            completion(.failure(UpdateFailure.invalidManifest)); return
        }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data, data.count <= 65536, error == nil,
               (response as? HTTPURLResponse)?.statusCode == 200 {
                completion(.success(data))
            } else { completion(.failure(UpdateFailure.network)) }
        }.resume()
    }

    private func prepare(_ release: Release) {
        guard let keyURL = Bundle.main.url(forResource: "UpdatePublicKey", withExtension: "txt"),
              let keyText = try? String(contentsOf: keyURL, encoding: .utf8) else {
            fail(UpdateFailure.missingKey); NSWorkspace.shared.open(releasePage); return
        }
        let keys = UpdateManifest.trustedKeys(from: keyText)
        guard !keys.isEmpty else { fail(UpdateFailure.missingKey); NSWorkspace.shared.open(releasePage); return }
        guard let manifestAsset = release.assets.first(where: { $0.name == "update.json" }),
              let signatureAsset = release.assets.first(where: { $0.name == "update.json.sig" }) else {
            fail(UpdateFailure.invalidManifest); return
        }
        let tag = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let build = currentBuild
        isBusy = true; statusText = AppText("Проверка подписи обновления…", "Verifying the update signature…"); progress = nil
        fetch(manifestAsset.browser_download_url) { manifestResult in
            self.fetch(signatureAsset.browser_download_url) { signatureResult in
                do {
                    let bytes = try manifestResult.get(), encoded = try signatureResult.get()
                    guard let signature = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else { throw UpdateFailure.signature }
                    let manifest = try UpdateManifest.decodeSigned(bytes, signature: signature, publicKeys: keys)
                    let url = try manifest.validate(currentBuild: build)
                    guard manifest.version == tag else { throw UpdateFailure.invalidManifest }
                    DispatchQueue.main.async { self.startDownload(url, manifest: manifest) }
                } catch { DispatchQueue.main.async { self.fail(error) } }
            }
        }
    }

    private func startDownload(_ url: URL, manifest: UpdateManifest) {
        pendingManifest = manifest
        statusText = AppText("Загрузка обновления…", "Downloading the update…"); progress = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 30 * 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        downloadSession = session
        session.downloadTask(with: url).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumArchiveSize || totalBytesExpectedToWrite > maximumArchiveSize { downloadTask.cancel(); return }
        state(AppText("Загрузка обновления…", "Downloading the update…"), progress: totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil)
    }

    /// Выполняется в очереди URLSession. Общее состояние читается через main, каталог — локальный.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let pending = DispatchQueue.main.sync { self.pendingManifest }
        var staging: URL?
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200,
                  let manifest = pending else { throw UpdateFailure.network }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("K530Update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            staging = dir
            let archive = dir.appendingPathComponent("update.zip")
            try FileManager.default.copyItem(at: location, to: archive)
            state(AppText("Проверка загруженного архива…", "Verifying the downloaded archive…"))
            let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard hash == manifest.sha256.lowercased() else { throw UpdateFailure.invalidArchive }
            try install(archive: archive, directory: dir, manifest: manifest)
        } catch {
            if let dir = staging { try? FileManager.default.removeItem(at: dir) }
            DispatchQueue.main.async { self.fail(error) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let error = error { DispatchQueue.main.async { self.fail(error) } }
    }

    /// Внешние утилиты получают аргументы напрямую, без интерпретации shell и без повышения прав.
    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure.installation(AppText(URL(fileURLWithPath: executable).lastPathComponent,
                                                                                           URL(fileURLWithPath: executable).lastPathComponent)) }
    }

    /// Подлинность архива уже подтверждена хэшем из подписанного манифеста. Здесь архив
    /// распаковывается и проверяется bundle; `codesign --verify` для ad-hoc подписи
    /// подтверждает только целостность пакета, а не автора. Старая версия остаётся для отката.
    private func install(archive: URL, directory: URL, manifest: UpdateManifest) throws {
        var allowed = false
        DispatchQueue.main.sync {
            self.onPresentationRequested()
            allowed = self.canStartUpdate()
        }
        guard allowed else { throw UpdateFailure.installation(AppText("Выполняется операция с клавиатурой. Повторите обновление позже.",
                                                                          "A keyboard operation is in progress. Try the update again later.")) }
        let fm = FileManager.default
        let unpacked = directory.appendingPathComponent("unpacked")
        state(AppText("Распаковка обновления…", "Extracting the update…"))
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        let app = unpacked.appendingPathComponent("K530Lighting.app")
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == manifest.version,
              Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") == manifest.build,
              bundle.executableURL != nil else { throw UpdateFailure.invalidArchive }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let destination = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parent = destination.deletingLastPathComponent()
        guard destination.pathExtension == "app", !destination.path.contains("/AppTranslocation/"),
              fm.isWritableFile(atPath: parent.path), fm.isWritableFile(atPath: destination.path) else {
            throw UpdateFailure.installation(AppText("Переместите приложение в доступную для записи папку «Программы» и повторите проверку.",
                                                     "Move the app to a writable Applications folder, then check again."))
        }
        state(AppText("Установка обновления…", "Installing the update…"))
        _ = try UpdateInstaller.replace(source: app, destination: destination) {
            self.state(AppText("Обновление установлено. Перезапуск…", "Update installed. Restarting…"), progress: 1)
            try self.run("/usr/bin/open", ["-n", destination.path])
        }
        try? fm.removeItem(at: directory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.readyToRelaunch = true
            NSApp.terminate(nil)
        }
    }
}

/// Транзакция замены выделена отдельно: откат проверяется на временных каталогах без запуска приложения.
enum UpdateInstaller {
    static let backupPrefix = ".K530Lighting-backup-"
    static let updatePrefix = ".K530Lighting-update-"

    /// Откат опирается только на переименования в одном каталоге: они атомарны,
    /// а удаление дерева .app может оборваться на середине и оставить битую копию.
    @discardableResult
    static func replace(source: URL, destination: URL, launch: () throws -> Void) throws -> URL {
        let fm = FileManager.default, parent = destination.deletingLastPathComponent()
        let replacement = parent.appendingPathComponent("\(updatePrefix)\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent("\(backupPrefix)\(UUID().uuidString).app")
        try fm.copyItem(at: source, to: replacement)
        do { try fm.moveItem(at: destination, to: backup) }
        catch { try? fm.removeItem(at: replacement); throw error }
        do { try fm.moveItem(at: replacement, to: destination) }
        catch {
            try? fm.moveItem(at: backup, to: destination)
            try? fm.removeItem(at: replacement)
            throw error
        }
        do { try launch() }
        catch {
            let failed = parent.appendingPathComponent("\(updatePrefix)\(UUID().uuidString).app")
            try fm.moveItem(at: destination, to: failed)
            do { try fm.moveItem(at: backup, to: destination) }
            catch { try? fm.moveItem(at: failed, to: destination); throw error }
            try? fm.removeItem(at: failed)
            throw error
        }
        // Старая .app остаётся, пока новая версия не проработает 30 с (removeLeftovers в start()).
        return backup
    }

    /// Удаляет только скрытые копии, созданные replace: точный префикс, UUID и расширение .app.
    /// Символическая ссылка удаляется как ссылка, её цель не затрагивается.
    static func removeLeftovers(in parent: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: parent.path) else { return }
        for name in names where name.hasSuffix(".app") {
            guard let prefix = [backupPrefix, updatePrefix].first(where: { name.hasPrefix($0) }),
                  UUID(uuidString: String(name.dropFirst(prefix.count).dropLast(4))) != nil else { continue }
            try? fm.removeItem(at: parent.appendingPathComponent(name))
        }
    }
}
