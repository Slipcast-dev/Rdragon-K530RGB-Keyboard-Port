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
    static func decodeSigned(_ bytes: Data, signature: Data, publicKey: Data) throws -> UpdateManifest {
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard key.isValidSignature(signature, for: bytes) else { throw UpdateFailure.signature }
        return try JSONDecoder().decode(Self.self, from: bytes)
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

enum UpdateFailure: LocalizedError {
    case invalidManifest, signature, invalidArchive, missingKey, network, installation(String)
    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "Некорректное описание обновления или несовместимая версия macOS."
        case .signature: return "Подпись обновления не подтверждена. Установка отменена."
        case .invalidArchive: return "Архив повреждён или содержит другое приложение."
        case .missingKey: return "В этой сборке отсутствует доверенный ключ обновлений. Доступна ручная загрузка со страницы релизов."
        case .network: return "Сервер обновлений недоступен. Повторите проверку позже."
        case .installation(let detail): return "Не удалось установить обновление: \(detail)"
        }
    }
}

/// Проверяет релизы в фоне. Настройки клавиатуры не затрагиваются; установка начинается только после согласия.
/// Сетевые операции и распаковка не блокируют интерфейс. Изменения опубликованного состояния идут на main.
final class AppUpdater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published private(set) var message = "Обновления проверяются автоматически"
    @Published private(set) var progress: Double?
    @Published private(set) var isBusy = false
    private(set) var readyToRelaunch = false
    /// Хост запрещает установку во время незавершённого HID-обмена и открывает панель с прогрессом.
    var canStartUpdate: () -> Bool = { true }
    var onPresentationRequested: () -> Void = {}
    private let repository = "https://api.github.com/repos/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/latest"
    private let releasePage = URL(string: "https://github.com/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/latest")!
    private var timer: Timer?
    private var downloadSession: URLSession?
    private var pendingManifest: UpdateManifest?
    private var staging: URL?
    private var checking = false
    private let maximumArchiveSize: Int64 = 250 * 1024 * 1024
    private var currentBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0 }
    private var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func start() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.check(manual: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in self?.check(manual: false) }
    }

    func checkManually() { check(manual: true) }

    private func state(_ text: String, progress: Double? = nil) {
        DispatchQueue.main.async { self.message = text; self.progress = progress }
    }

    private func check(manual: Bool) {
        guard !checking, !isBusy else { return }
        checking = true
        message = "Проверка обновлений…"
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
                    self.message = "Проверка недоступна: нет общедоступного релиза или репозиторий закрыт"
                    return
                }
                guard http.statusCode == 200, let data = data,
                      let release = try? JSONDecoder().decode(Release.self, from: data) else { self.fail(UpdateFailure.network); return }
                let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                guard !release.prerelease, !release.draft, UpdateManifest.newer(version, than: self.currentVersion) else {
                    self.message = "Установлена актуальная версия"; return
                }
                self.message = "Доступна версия \(version)"
                let deferred = UserDefaults.standard.double(forKey: "UpdateReminderDate")
                if !manual && deferred > Date().timeIntervalSince1970 { return }
                let alert = NSAlert()
                alert.messageText = "Доступна K530 Lighting \(version)"
                alert.informativeText = "Скачать обновление? После проверки оно установится автоматически, и приложение перезапустится."
                alert.addButton(withTitle: "Скачать")
                alert.addButton(withTitle: "Позже")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else {
                    UserDefaults.standard.set(Date().addingTimeInterval(24 * 60 * 60).timeIntervalSince1970, forKey: "UpdateReminderDate"); return
                }
                guard self.canStartUpdate() else {
                    self.message = "Дождитесь завершения операции с клавиатурой и повторите обновление."
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

    private func fail(_ error: Error) {
        message = error.localizedDescription
        progress = nil
        isBusy = false
        pendingManifest = nil
        if let dir = staging { try? FileManager.default.removeItem(at: dir) }
        staging = nil
    }

    /// Получает только небольшие служебные файлы. Подлинность JSON проверяется встроенным публичным ключом.
    private func fetch(_ url: URL) throws -> Data {
        guard url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/Slipcast-dev/Rdragon-K530RGB-Keyboard-Port/releases/download/") else { throw UpdateFailure.invalidManifest }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(UpdateFailure.network)
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data, data.count <= 65536, error == nil,
               (response as? HTTPURLResponse)?.statusCode == 200 {
                result = .success(data)
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 35) == .success else { task.cancel(); throw UpdateFailure.network }
        return try result.get()
    }

    private func prepare(_ release: Release) {
        guard let keyURL = Bundle.main.url(forResource: "UpdatePublicKey", withExtension: "txt"),
              let keyText = try? String(contentsOf: keyURL),
              let keyBytes = Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes) else {
            fail(UpdateFailure.missingKey)
            NSWorkspace.shared.open(releasePage)
            return
        }
        isBusy = true; message = "Проверка подписи обновления…"; progress = nil
        DispatchQueue.global(qos: .utility).async {
            do {
                guard let manifestAsset = release.assets.first(where: { $0.name == "update.json" }),
                      let signatureAsset = release.assets.first(where: { $0.name == "update.json.sig" }) else { throw UpdateFailure.invalidManifest }
                let bytes = try self.fetch(manifestAsset.browser_download_url)
                let encoded = try self.fetch(signatureAsset.browser_download_url)
                guard let signature = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else { throw UpdateFailure.signature }
                let manifest = try UpdateManifest.decodeSigned(bytes, signature: signature, publicKey: key.rawRepresentation)
                let url = try manifest.validate(currentBuild: self.currentBuild)
                let tag = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                guard manifest.version == tag else { throw UpdateFailure.invalidManifest }
                DispatchQueue.main.async {
                    self.pendingManifest = manifest
                    self.message = "Загрузка обновления…"; self.progress = 0
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.timeoutIntervalForRequest = 60
                    configuration.timeoutIntervalForResource = 30 * 60
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    self.downloadSession = session
                    session.downloadTask(with: url).resume()
                }
            } catch { DispatchQueue.main.async { self.fail(error) } }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumArchiveSize || totalBytesExpectedToWrite > maximumArchiveSize { downloadTask.cancel(); return }
        state("Загрузка обновления…", progress: totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200,
                  let manifest = pendingManifest else { throw UpdateFailure.network }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("K530Update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            staging = dir
            let archive = dir.appendingPathComponent("update.zip")
            try FileManager.default.copyItem(at: location, to: archive)
            state("Проверка загруженного архива…")
            let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard hash == manifest.sha256.lowercased() else { throw UpdateFailure.invalidArchive }
            try install(archive: archive, directory: dir, manifest: manifest)
        } catch { DispatchQueue.main.async { self.fail(error) } }
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
        guard process.terminationStatus == 0 else { throw UpdateFailure.installation(URL(fileURLWithPath: executable).lastPathComponent) }
    }

    /// Сначала проверяет подпись архива, затем распаковывает и проверяет bundle. Старая версия остаётся для отката.
    private func install(archive: URL, directory: URL, manifest: UpdateManifest) throws {
        var allowed = false
        DispatchQueue.main.sync {
            self.onPresentationRequested()
            allowed = self.canStartUpdate()
        }
        guard allowed else { throw UpdateFailure.installation("Выполняется операция с клавиатурой. Повторите обновление позже.") }
        let fm = FileManager.default
        let unpacked = directory.appendingPathComponent("unpacked")
        state("Распаковка обновления…")
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
            throw UpdateFailure.installation("Переместите приложение в доступную для записи папку «Программы» и повторите проверку.")
        }
        state("Установка обновления…")
        _ = try UpdateInstaller.replace(source: app, destination: destination) {
            self.state("Обновление установлено. Перезапуск…", progress: 1)
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
    @discardableResult
    static func replace(source: URL, destination: URL, launch: () throws -> Void) throws -> URL {
        let fm = FileManager.default, parent = destination.deletingLastPathComponent()
        let replacement = parent.appendingPathComponent(".K530Lighting-update-\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent(".K530Lighting-backup-\(UUID().uuidString).app")
        try fm.copyItem(at: source, to: replacement)
        do {
            try fm.moveItem(at: destination, to: backup)
            do { try fm.moveItem(at: replacement, to: destination) }
            catch { try fm.moveItem(at: backup, to: destination); throw error }
            do { try launch() }
            catch {
                try fm.removeItem(at: destination)
                try fm.moveItem(at: backup, to: destination)
                throw error
            }
            // Сохраняем старую .app для ручного восстановления при сбое уже запущенной новой версии.
            return backup
        } catch {
            try? fm.removeItem(at: replacement)
            throw error
        }
    }
}
