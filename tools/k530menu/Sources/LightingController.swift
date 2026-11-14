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
        let message: String
        let canRestore: Bool
    }
    private struct DeviceError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    func perform(_ action: Action, completion: @escaping (Result<Snapshot, Error>) -> Void) {
        queue.async {
            let result = Result { try self.execute(action) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func execute(_ action: Action) throws -> Snapshot {
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            throw DeviceError("Нужен доступ «Мониторинг ввода» в системных настройках.")
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw DeviceError("Не удалось открыть USB HID.")
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        guard let device = devices.first(where: {
            (IOHIDDeviceGetProperty($0, "MaxOutputReportSize" as CFString) as? Int) == 64
        }), let session = K530Session(device: device) else {
            throw DeviceError("Клавиатура не найдена. Подключите K530 по USB.")
        }
        guard let before = session.readProfiles(), before.count == 3 else {
            throw DeviceError("Клавиатура не ответила. Проверьте USB и разрешения.")
        }
        if initial == nil { initial = before }
        switch action {
        case .read: break
        case .apply(let settings):
            guard before.allSatisfy({ LightingSettings(profile: $0) != nil }) else {
                throw DeviceError("Необычные значения профилей: запись отменена.")
            }
            try backup(before)
            guard session.writeFields(settings.fields) else {
                throw DeviceError("Ошибка записи. Часть настроек могла измениться; перечитайте устройство.")
            }
        case .restore:
            guard let original = initial else { throw DeviceError("Исходное состояние ещё не прочитано.") }
            try backup(before)
            guard session.restoreHeads(original) else { throw DeviceError("Не удалось вернуть исходные настройки.") }
        }
        let after: [[UInt8]]
        if case .read = action { after = before }
        else {
            guard let profiles = session.readProfiles(), profiles.count == 3 else {
                throw DeviceError("Запись отправлена, но проверка не удалась. Перечитайте устройство.")
            }
            after = profiles
        }
        switch action {
        case .apply(let settings):
            guard after.allSatisfy({ profile in settings.fields.allSatisfy {
                Array(profile[$0.offset..<($0.offset + $0.data.count)]) == $0.data
            } }) else { throw DeviceError("Проверка записи не пройдена. Можно вернуть исходное состояние.") }
        case .restore:
            guard let original = initial, zip(after, original).allSatisfy({
                Array($0.0.prefix(8)) == Array($0.1.prefix(8))
            }) else { throw DeviceError("Проверка восстановления не пройдена.") }
        case .read: break
        }
        let same = after.dropFirst().allSatisfy { Array($0.prefix(8)) == Array(after[0].prefix(8)) }
        return Snapshot(settings: same ? LightingSettings(profile: after[0]) : nil,
                        message: same ? "Настройки прочитаны из клавиатуры" : "Профили различаются. Применение синхронизирует все три.",
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
    @Published private(set) var message = "Подключите клавиатуру по USB"
    @Published private(set) var error = false
    @Published var autostart = false
    @Published private(set) var needsPermission = false
    var restartApplication: () -> Void = {}
    private let service = LightingDeviceService()
    private var generation = 0
    private var saved: LightingSettings?
    var hasChanges: Bool { saved != draft }
    var showHelp: () -> Void = {}
    var checkUpdates: () -> Void = {}
    var updaterBusy: () -> Bool = { false }

    func deviceRemoved() {
        generation += 1; connected = false; busy = false
        message = "Клавиатура отключена. Подключите K530 по USB."
    }
    /// Проверяется при возвращении из настроек. macOS может потребовать перезапуск
    /// процесса даже после включения переключателя — для этого есть отдельное действие.
    func refresh() {
        needsPermission = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted
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
    func restore() { run(.restore) }

    private func run(_ action: LightingDeviceService.Action) {
        guard !busy, !updaterBusy() else { return }
        let operationGeneration = generation
        let preserveDraft: Bool
        if case .read = action { preserveDraft = saved != nil && hasChanges }
        else { preserveDraft = false }
        busy = true; error = false
        message = "Обмен с клавиатурой…"
        service.perform(action) { [weak self] result in
            guard let self = self, self.generation == operationGeneration else { return }
            self.busy = false
            switch result {
            case .success(let snapshot):
                self.connected = true; self.canRestore = snapshot.canRestore
                self.saved = snapshot.settings
                if let settings = snapshot.settings, !preserveDraft { self.draft = settings }
                if case .apply = action { self.message = "Настройки сохранены в клавиатуре" }
                else if case .restore = action { self.message = "Исходное состояние восстановлено" }
                else { self.message = snapshot.message }
            case .failure(let error):
                self.needsPermission = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted
                self.error = true; self.connected = false; self.message = error.localizedDescription
            }
        }
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
        } catch { self.error = true; message = "Автозапуск: \(error.localizedDescription)" }
    }
}
