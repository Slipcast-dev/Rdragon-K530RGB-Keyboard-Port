import AppKit
import Combine
import IOKit.hid

/// Последовательный HID-сервис. Каждый сеанс живёт внутри одной задачи, поэтому
/// callback и его CFRunLoop всегда принадлежат одному потоку, даже если GCD сменит поток.
final class LightingDeviceService {
    private let queue = DispatchQueue(label: "dev.slipcast.k530.hid")
    private var initial: [[UInt8]]?
    private var backupSaved = false

    enum Action { case read, apply(LightingSettings), restore }
    struct Snapshot {
        let settings: LightingSettings?
        let message: AppText
        let canRestore: Bool
    }
    private struct DeviceError: AppLocalizedError {
        let appText: AppText
        init(_ russian: String, _ english: String) { appText = AppText(russian, english) }
    }

    func perform(_ action: Action, completion: @escaping (Result<Snapshot, Error>) -> Void) {
        queue.async {
            let result = Result { try self.execute(action) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func execute(_ action: Action) throws -> Snapshot {
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            throw DeviceError("Нужен доступ «Мониторинг ввода» в системных настройках.", "Input Monitoring permission is required in System Settings.")
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw DeviceError("Не удалось открыть USB HID.", "Could not open USB HID.")
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        guard let device = devices.first(where: {
            (IOHIDDeviceGetProperty($0, "MaxOutputReportSize" as CFString) as? Int) == 64
        }), let session = K530Session(device: device) else {
            throw DeviceError("Клавиатура не найдена. Подключите K530 по USB.", "Keyboard not found. Connect the K530 over USB.")
        }
        guard let before = session.readProfiles(), before.count == 3 else {
            throw DeviceError("Клавиатура не ответила. Проверьте USB и разрешения.", "The keyboard did not respond. Check USB and permissions.")
        }
        if initial == nil { initial = before }
        switch action {
        case .read: break
        case .apply(let settings):
            guard before.allSatisfy({ LightingSettings(profile: $0) != nil }) else {
                throw DeviceError("Необычные значения профилей: запись отменена.", "Unexpected profile values: write canceled.")
            }
            try backup(before)
            // Одна запись 8 байт на профиль вместо отдельной команды на каждое поле.
            guard session.writeHeads(before.map { settings.head(preserving: $0) }) else {
                throw DeviceError("Ошибка записи. Часть настроек могла измениться; перечитайте устройство.", "Write failed. Some settings may have changed; read the device again.")
            }
        case .restore:
            guard let original = initial else { throw DeviceError("Исходное состояние ещё не прочитано.", "The initial state has not been read yet.") }
            try backup(before)
            guard session.restoreHeads(original) else { throw DeviceError("Не удалось вернуть исходные настройки.", "Could not restore the initial settings.") }
        }
        let after: [[UInt8]]
        if case .read = action { after = before }
        else {
            guard let profiles = session.readProfiles(), profiles.count == 3 else {
                throw DeviceError("Запись отправлена, но проверка не удалась. Перечитайте устройство.", "The write was sent, but verification failed. Read the device again.")
            }
            after = profiles
        }
        switch action {
        case .apply(let settings):
            guard after.allSatisfy({ profile in settings.fields.allSatisfy {
                Array(profile[$0.offset..<($0.offset + $0.data.count)]) == $0.data
            } }) else { throw DeviceError("Проверка записи не пройдена. Можно вернуть исходное состояние.", "Write verification failed. You can restore the initial state.") }
        case .restore:
            guard let original = initial, zip(after, original).allSatisfy({
                Array($0.0.prefix(8)) == Array($0.1.prefix(8))
            }) else { throw DeviceError("Проверка восстановления не пройдена.", "Restore verification failed.") }
        case .read: break
        }
        let same = after.dropFirst().allSatisfy { Array($0.prefix(8)) == Array(after[0].prefix(8)) }
        return Snapshot(settings: same ? LightingSettings(profile: after[0]) : nil,
                        message: same ? AppText("Настройки прочитаны из клавиатуры", "Settings read from the keyboard") :
                            AppText("Профили различаются. Применение синхронизирует все три.", "Hardware profiles differ. Applying settings synchronizes all three."),
                        canRestore: initial != nil)
    }

    /// Отказ создания резервной копии останавливает запись, а не скрывается.
    private func backup(_ profiles: [[UInt8]]) throws {
        guard !backupSaved else { return }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("K530Lighting")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = profiles.enumerated().map { index, bytes in
            "профиль \(index + 1): " + bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        }.joined(separator: "\n")
        try text.write(to: directory.appendingPathComponent("backup-\(UUID().uuidString).txt"), atomically: true, encoding: .utf8)
        backupSaved = true
    }
}

/// Состояние панели живёт на главном потоке. Черновик не перезаписывается
/// фоновым чтением: перечитать устройство можно отдельным действием.
final class LightingController: ObservableObject {
    @Published var draft = LightingSettings()
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var canRestore = false
    @Published private var statusText = AppText("Подключите клавиатуру по USB", "Connect the keyboard over USB")
    var message: String { statusText.value }
    @Published private(set) var error = false
    @Published var autostart = false
    @Published private(set) var needsPermission = false
    var restartApplication: () -> Void = {}
    @Published private(set) var profileDocument = LightingProfileDocument.defaults()
    @Published private var profileErrorText: AppText?
    var profileError: String? { profileErrorText?.value }
    private let profileStore: LightingProfileStore
    private var profileDrafts: [UUID: LightingSettings] = [:]
    private var hasStoredProfiles = false
    private let service = LightingDeviceService()
    private var generation = 0
    /// Чтение, отложенное из-за незавершённой операции (например, клавиатуру переподключили во время записи).
    private var pendingRefresh = false
    private var saved: LightingSettings?
    var hasChanges: Bool { saved != draft }
    var profiles: [LightingProfile] { profileDocument.profiles }
    var selectedProfileID: UUID { profileDocument.selectedID }
    var selectedProfile: LightingProfile? { profiles.first { $0.id == selectedProfileID } }
    var hasUnsavedProfileChanges: Bool { selectedProfile?.settings != draft }

    init(profileStore: LightingProfileStore = LightingProfileStore()) {
        self.profileStore = profileStore
        do {
            if let document = try profileStore.load() {
                profileDocument = document; hasStoredProfiles = true
            }
            draft = selectedProfile?.settings ?? LightingSettings()
        } catch { setProfileError(error) }
    }

    /// Переключение хранит несохранённый черновик каждого набора отдельно.
    /// Выбор сам по себе не отправляет команды в клавиатуру.
    func selectProfile(_ id: UUID) {
        guard !busy, !updaterBusy(), profiles.contains(where: { $0.id == id }) else { return }
        profileDrafts[selectedProfileID] = draft
        var document = profileDocument; document.selectedID = id
        guard persistProfiles(document) else { return }
        profileDocument = document
        draft = profileDrafts[id] ?? selectedProfile!.settings
    }

    func saveProfile(name: String) {
        guard !busy, !updaterBusy(), let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
        var document = profileDocument
        document.profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        document.profiles[index].settings = draft
        guard persistProfiles(document) else { return }
        profileDocument = document; profileDrafts[selectedProfileID] = draft
        let name = document.profiles[index].name
        statusText = AppText("Профиль «\(name)» сохранён", "Profile “\(name)” saved")
    }

    func createProfile() {
        guard !busy, !updaterBusy() else { return }
        profileDrafts[selectedProfileID] = draft
        let names = Set(profiles.map { $0.name })
        var number = profiles.count + 1
        while names.contains(L("Профиль \(number)", "Profile \(number)")) { number += 1 }
        let profile = LightingProfile(name: L("Профиль \(number)", "Profile \(number)"), settings: draft)
        var document = profileDocument; document.profiles.append(profile); document.selectedID = profile.id
        guard persistProfiles(document) else { return }
        profileDocument = document
    }

    func deleteProfile() {
        guard !busy, !updaterBusy(), profiles.count > 1 else { return }
        let removed = selectedProfileID
        var document = profileDocument
        document.profiles.removeAll { $0.id == removed }
        document.selectedID = document.profiles[0].id
        guard persistProfiles(document) else { return }
        profileDrafts.removeValue(forKey: removed); profileDocument = document
        draft = profileDrafts[selectedProfileID] ?? document.profiles[0].settings
    }

    @discardableResult
    private func persistProfiles(_ document: LightingProfileDocument) -> Bool {
        do {
            try profileStore.save(document); profileErrorText = nil; hasStoredProfiles = true
            return true
        } catch { setProfileError(error); return false }
    }
    var showHelp: () -> Void = {}
    var checkUpdates: () -> Void = {}
    var updaterBusy: () -> Bool = { false }

    /// `busy` не сбрасывается: операция ещё может выполняться в очереди HID, и до её
    /// завершения выход и установка обновления должны оставаться заблокированными.
    func deviceRemoved() {
        generation += 1; connected = false
        statusText = AppText("Клавиатура отключена. Подключите K530 по USB.", "Keyboard disconnected. Connect the K530 over USB.")
    }
    /// Проверяется при возвращении из настроек. macOS может потребовать перезапуск
    /// процесса даже после включения переключателя — для этого есть отдельное действие.
    func refresh() {
        needsPermission = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted
        if busy { pendingRefresh = true; return }
        run(.read)
    }

    func openInputSettings() {
        let link = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        if !NSWorkspace.shared.open(link) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Preferences.app"))
        }
    }

    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    func apply() { run(.apply(draft)) }

    /// Быстрое меню меняет одно поле поверх состояния клавиатуры, а не отправляет весь
    /// черновик: неприменённые правки окна остаются в черновике и в устройство не уходят.
    func applyQuick(_ change: @escaping (inout LightingSettings) -> Void) {
        guard connected, !busy, !updaterBusy() else { return }
        // Без единого прочитанного состояния (профили клавиатуры различаются) черновик
        // целиком не отправляем: синхронизация профилей — только кнопкой «Применить».
        guard var settings = saved else {
            statusText = AppText("Профили клавиатуры различаются. Используйте «Применить» в окне.",
                                 "Hardware profiles differ. Use Apply in the window.")
            return
        }
        change(&settings)
        run(.apply(settings), preserveDraft: true) { [weak self] in
            guard let self = self else { return }
            change(&self.draft)
        }
    }
    func restore() { run(.restore) }

    private func run(_ action: LightingDeviceService.Action, preserveDraft forcePreserve: Bool = false,
                     onSuccess: @escaping () -> Void = {}) {
        guard !busy, !updaterBusy() else { return }
        let operationGeneration = generation
        let preserveDraft: Bool
        if case .read = action { preserveDraft = hasStoredProfiles || hasUnsavedProfileChanges || (saved != nil && hasChanges) }
        else { preserveDraft = forcePreserve }
        busy = true; error = false
        statusText = AppText("Обмен с клавиатурой…", "Communicating with the keyboard…")
        service.perform(action) { [weak self] result in
            guard let self = self else { return }
            self.busy = false
            defer { if self.pendingRefresh { self.pendingRefresh = false; self.refresh() } }
            guard self.generation == operationGeneration else { return }
            switch result {
            case .success(let snapshot):
                self.connected = true; self.canRestore = snapshot.canRestore
                self.saved = snapshot.settings
                if let settings = snapshot.settings, !preserveDraft { self.draft = settings }
                onSuccess()
                if case .apply = action { self.statusText = AppText("Настройки сохранены в клавиатуре", "Settings saved to the keyboard") }
                else if case .restore = action { self.statusText = AppText("Исходное состояние восстановлено", "Initial state restored") }
                else { self.statusText = snapshot.message }
            case .failure(let error):
                self.needsPermission = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted
                self.error = true; self.connected = false; self.statusText = self.localizedErrorText(error)
            }
        }
    }

    /// Ошибки приложения сохраняют две версии. Системный текст macOS остаётся
    /// в системной локали, но наши пояснения и префиксы переключаются немедленно.
    private func localizedErrorText(_ error: Error) -> AppText {
        if let localized = error as? AppLocalizedError { return localized.appText }
        let detail = error.localizedDescription
        return AppText(detail, detail)
    }

    private func setProfileError(_ error: Error) {
        let detail = localizedErrorText(error)
        profileErrorText = AppText("Профили: \(detail.russian)", "Profiles: \(detail.english)")
    }

    private var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/dev.slipcast.k530lighting.plist")
    }
    func loadAutostart() {
        guard let data = try? Data(contentsOf: agentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { autostart = false; return }
        autostart = arguments.first == Bundle.main.executablePath
    }
    func toggleAutostart() {
        do {
            if autostart { try FileManager.default.removeItem(at: agentURL) }
            else {
                guard let executable = Bundle.main.executablePath else { return }
                let plist: [String: Any] = ["Label": "dev.slipcast.k530lighting", "ProgramArguments": [executable],
                                          "RunAtLoad": true, "ProcessType": "Interactive"]
                try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agentURL, options: .atomic)
            }
            loadAutostart()
        } catch {
            self.error = true
            let detail = localizedErrorText(error)
            statusText = AppText("Автозапуск: \(detail.russian)", "Launch at login: \(detail.english)")
        }
    }
}
