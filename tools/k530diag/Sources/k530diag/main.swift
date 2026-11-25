import Foundation
import IOKit
import IOKit.hid

// Диагностическая утилита K530 (Redragon, Sonix 0C45:5004).
// По умолчанию только читает метаданные. Команда read-profile без --send ничего не отправляет;
// с --send отправляет служебные пакеты begin/read/end (Output-отчёты). Команд записи настроек в утилите нет.

let defaultVID = 0x0C45, defaultPID = 0x5004
var interrupted: Int32 = 0

func intProp(_ dev: IOHIDDevice, _ key: String) -> Int? {
    IOHIDDeviceGetProperty(dev, key as CFString) as? Int
}
func strProp(_ dev: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(dev, key as CFString) as? String
}
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

/// research/device в репозитории определяется по пути исходника, а не по текущей папке терминала.
/// Если утилита собрана вне репозитория — каталог в Application Support.
func researchDirectory() -> URL {
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { repo.deleteLastPathComponent() } // main.swift → k530diag → Sources → k530diag → tools → корень
    let device = repo.appendingPathComponent("research/device", isDirectory: true)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: device.path, isDirectory: &isDirectory), isDirectory.boolValue { return device }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/K530Lighting/diag", isDirectory: true)
}

/// Без резервной копии запись в клавиатуру не начинается.
func saveBackupOrExit(_ profiles: [[UInt8]]) -> String {
    let directory = researchDirectory()
    let url = directory.appendingPathComponent("profiles-backup-\(Int(Date().timeIntervalSince1970)).txt")
    let text = profiles.enumerated().map { "профиль \($0.offset + 1): " + hex($0.element) }.joined(separator: "\n") + "\n"
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        fputs("Не удалось сохранить резервную копию (\(url.path)): \(error.localizedDescription). Запись отменена.\n", stderr)
        exit(7)
    }
    return url.path
}

func findDevices(vid: Int, pid: Int) -> [IOHIDDevice] {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: vid, kIOHIDProductIDKey: pid] as CFDictionary)
    IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    let set = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
    // Порядок по LocationID/MaxInput для стабильного вывода.
    return set.sorted { (intProp($0, "MaxInputReportSize") ?? 0) < (intProp($1, "MaxInputReportSize") ?? 0) }
}

func descriptor(_ dev: IOHIDDevice) -> [UInt8] {
    guard let d = IOHIDDeviceGetProperty(dev, kIOHIDReportDescriptorKey as CFString) as? Data else { return [] }
    return [UInt8](d)
}

func describe(_ dev: IOHIDDevice, index: Int) -> String {
    let desc = descriptor(dev)
    let parsed = HIDDescriptor.dump(desc)
    var s = "## Интерфейс \(index)\n\n"
    s += "- Product: \(strProp(dev, "Product") ?? "?"), Manufacturer: \(strProp(dev, "Manufacturer") ?? "?")\n"
    s += String(format: "- VID:PID %04X:%04X, версия (bcdDevice) 0x%04X\n",
                intProp(dev, "VendorID") ?? 0, intProp(dev, "ProductID") ?? 0, intProp(dev, "VersionNumber") ?? 0)
    s += String(format: "- LocationID 0x%X, Transport %@\n", intProp(dev, "LocationID") ?? 0, strProp(dev, "Transport") ?? "?")
    s += String(format: "- Primary usage page/usage: 0x%X / 0x%X\n", intProp(dev, "PrimaryUsagePage") ?? 0, intProp(dev, "PrimaryUsage") ?? 0)
    s += "- Max input/output/feature: \(intProp(dev, "MaxInputReportSize") ?? 0)/\(intProp(dev, "MaxOutputReportSize") ?? 0)/\(intProp(dev, "MaxFeatureReportSize") ?? 0)\n"
    s += "- Дескриптор (\(desc.count) байт): `\(hex(desc))`\n\n"
    s += "Отчёты (размер без байта Report ID):\n\n"
    for r in parsed.reports { s += "- \(r.kind) ID \(r.id): \(r.bytes) байт\n" }
    s += "\n```\n\(parsed.text)```\n\n"
    return s
}

func usage() {
    print("""
    k530diag — диагностика Redragon K530 (только чтение)

      k530diag list                    краткий список HID-интерфейсов
      k530diag descriptors             полный разбор дескрипторов (Markdown, годится для research/device)
      k530diag get-feature <iface> <id> [len]
                                       прочитать Feature-отчёт (GET_REPORT). Запись не выполняется.
      k530diag read-profile [--send] [--save файл]
                                       прочитать 3 профиля (команды begin, read, end). Без --send только
                                       показывает пакеты. Команд записи в утилите нет.
      k530diag test-mode <1-18|20> [--hold сек] [--send]
                                       ЗАПИСЬ: временно меняет режим подсветки во всех профилях и возвращает
                                       исходный с проверкой чтением. Без --send печатает пакеты.
      k530diag color-scan [--hold сек] [--ask] [--send]
                                       ЗАПИСЬ: перебирает режимы 1–18 и 20 с красным цветом (режим называется
                                       голосом) и возвращает исходное состояние. Без --send ничего не делает.
      k530diag listen <seconds>       показать входящие отчёты служебного интерфейса (FF1C:0092)
                                       при нажатии Fn-комбинаций; нужны права Input Monitoring.

    Переменные: K530_VID, K530_PID (десятичные или 0x..) для другой ревизии.
    """)
}

func envInt(_ k: String, _ d: Int) -> Int {
    guard let v = ProcessInfo.processInfo.environment[k] else { return d }
    return Int(v.hasPrefix("0x") ? String(v.dropFirst(2)) : v, radix: v.hasPrefix("0x") ? 16 : 10) ?? d
}

let args = Array(CommandLine.arguments.dropFirst())
let vid = envInt("K530_VID", defaultVID), pid = envInt("K530_PID", defaultPID)
guard let cmd = args.first else { usage(); exit(0) }
let devs = findDevices(vid: vid, pid: pid)
if devs.isEmpty && cmd != "help" {
    fputs(String(format: "Устройство %04X:%04X не найдено. Подключите клавиатуру кабелем.\n", vid, pid), stderr)
    exit(2)
}

switch cmd {
case "list":
    for (i, d) in devs.enumerated() {
        print(String(format: "[%d] usage %04X:%04X in=%d out=%d feat=%d  %@", i,
                     intProp(d, "PrimaryUsagePage") ?? 0, intProp(d, "PrimaryUsage") ?? 0,
                     intProp(d, "MaxInputReportSize") ?? 0, intProp(d, "MaxOutputReportSize") ?? 0,
                     intProp(d, "MaxFeatureReportSize") ?? 0, strProp(d, "Product") ?? ""))
    }
case "descriptors":
    var s = "# Дескрипторы K530 (снято k530diag)\n\n"
    for (i, d) in devs.enumerated() { s += describe(d, index: i) }
    print(s)
case "get-feature":
    guard args.count >= 3, let idx = Int(args[1]), idx < devs.count, let rid = UInt8(args[2]) else { usage(); exit(1) }
    let len = args.count > 3 ? Int(args[3]) ?? 64 : 64
    let d = devs[idx]
    guard IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
        fputs("IOHIDDeviceOpen не удался (права Input Monitoring или устройство занято системой).\n", stderr); exit(3)
    }
    var buf = [UInt8](repeating: 0, count: len)
    var n = len
    let r = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, CFIndex(rid), &buf, &n)
    if r == kIOReturnSuccess { print("OK \(n) байт: \(hex(Array(buf.prefix(n))))") }
    else { print(String(format: "Ошибка IOReturn 0x%08X", r)); exit(4) }
case "listen":
    let secs = args.count > 1 ? Double(args[1]) ?? 10 : 10
    guard let d = devs.first(where: { intProp($0, "MaxInputReportSize") == 64 }) else { fputs("Служебный интерфейс не найден.\n", stderr); exit(2) }
    guard IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
        fputs("IOHIDDeviceOpen не удался: выдайте терминалу доступ в Системные настройки → Конфиденциальность → Мониторинг ввода.\n", stderr); exit(3)
    }
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
    IOHIDDeviceRegisterInputReportCallback(d, buf, 256, { _, _, _, _, id, rep, len in
        // Клавиатурный ввод (ID 1, 3 и т.п.) не печатаем — только служебный ID 4.
        guard id == 4 else { return }
        print("ID \(id) len \(len): \(hex(Array(UnsafeBufferPointer(start: rep, count: len))))")
        fflush(stdout)
    }, nil)
    IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    print("Слушаю \(secs) с. Нажмите Fn-комбинацию подсветки…")
    CFRunLoopRunInMode(.defaultMode, secs, false)
case "read-profile":
    // По умолчанию только показывает пакеты, которые были бы отправлены. Отправка — с флагом --send.
    let send = args.contains("--send")
    let plan: [(String, K530Protocol.Command, UInt8, UInt16)] =
        [("begin", .begin, 0, 0)]
        + (0..<K530Protocol.profileCount).map { ("read профиль \($0 + 1)", .read, K530Protocol.readChunk, UInt16($0 * K530Protocol.profileSize)) }
        + [("end", .end, 0, 0)]
    if !send {
        print("Пробный режим: ничего не отправляется. Для отправки добавьте --send.\n")
        for (name, cmd, len, addr) in plan {
            let p = K530Protocol.packet(cmd, length: len, address: addr)
            print("\(name):\n  \(hex(p))")
        }
        exit(0)
    }
    guard let d = devs.first(where: { intProp($0, "MaxOutputReportSize") == 64 }) else { fputs("Служебный интерфейс не найден.\n", stderr); exit(2) }
    guard let session = K530Session(device: d) else {
        fputs("IOHIDDeviceOpen не удался: нужен доступ «Мониторинг ввода» для терминала.\n", stderr); exit(3)
    }
    guard let profiles = session.readProfiles() else { exit(5) }
    var dump = "# Прочитано k530diag read-profile\n"
    for (i, data) in profiles.enumerated() {
        let text = "Профиль \(i + 1) (адрес \(i * K530Protocol.profileSize)):\n" + K530Protocol.describeProfile(data)
        print(text); dump += text
    }
    if let path = args.drop(while: { $0 != "--save" }).dropFirst().first {
        do { try dump.write(toFile: path, atomically: true, encoding: .utf8); print("Сохранено: \(path)") }
        catch { fputs("Не удалось сохранить \(path): \(error.localizedDescription)\n", stderr); exit(7) }
    }
case "test-mode":
    // Временная смена режима подсветки с автоматическим возвратом: test-mode <режим> [--hold сек] [--send]
    // Без --send печатает пакеты. Меняется только байт +0 (номер режима) трёх профилей.
    guard args.count >= 2, let mode = UInt8(args[1]), (1...18).contains(Int(mode)) || mode == 20 else {
        fputs("Режим должен быть 1–18 или 20.\n", stderr); exit(1)
    }
    var hold = 8.0
    if let i = args.firstIndex(of: "--hold"), i + 1 < args.count, let v = Double(args[i + 1]) { hold = min(max(v, 1), 60) }
    if !args.contains("--send") {
        print("Пробный режим: ничего не отправляется. Для отправки добавьте --send.\n")
        for i in 0..<K530Protocol.profileCount {
            let p = K530Protocol.packet(.write, length: 1, address: UInt16(i * K530Protocol.profileSize), data: [mode])
            print("write +0 профиля \(i + 1) = \(mode):\n  \(hex(Array(p.prefix(16))))")
        }
        exit(0)
    }
    guard let d = devs.first(where: { intProp($0, "MaxOutputReportSize") == 64 }), let session = K530Session(device: d) else {
        fputs("Не удалось открыть служебный интерфейс (доступ «Мониторинг ввода»).\n", stderr); exit(3)
    }
    guard let before = session.readProfiles() else { fputs("Не удалось прочитать профили, запись отменена.\n", stderr); exit(4) }
    let backupPath = saveBackupOrExit(before)
    print("Резервная копия: \(backupPath)")
    let originals = before.map { $0[0] }
    guard originals.allSatisfy({ (1...18).contains(Int($0)) || $0 == 20 }) else {
        fputs("Текущие режимы вне известного набора (\(originals)); запись отменена.\n", stderr); exit(4)
    }
    func restore() -> Bool {
        let ok = session.writeModes(originals)
        guard let after = session.readProfiles() else { return false }
        return ok && after.map { $0[0] } == originals && zip(before, after).allSatisfy { $0.0 == $0.1 }
    }
    signal(SIGINT) { _ in interrupted = 1 }
    guard session.writeModes([mode, mode, mode]) else {
        print("Запись не удалась, возвращаю исходное."); print(restore() ? "Исходное состояние восстановлено." : "ВНИМАНИЕ: восстановление не подтверждено, см. резервную копию."); exit(5)
    }
    if let mid = session.readProfiles() { print("После записи режимы: \(mid.map { $0[0] }) (ожидалось \(mode))") }
    print("Режим \(mode) включён на \(Int(hold)) с. Через это время вернётся режим \(originals).")
    let end = Date().addingTimeInterval(hold)
    while Date() < end && interrupted == 0 { CFRunLoopRunInMode(.defaultMode, 0.1, false) }
    let restored = restore()
    print(restored ? "Исходное состояние восстановлено и проверено чтением." : "ВНИМАНИЕ: восстановление не подтверждено, см. резервную копию.")
    exit(restored ? 0 : 6)
case "color-scan":
    // Перебор режимов с красным цветом: color-scan [--hold сек] [--ask] [--send]. Без --ask название режима проговаривается голосом (say);
    // с --ask режим держится до ответа y/n/s/q в терминале.
    // Меняет режим, флаг цвета и RGB; по окончании (или Ctrl+C) возвращает исходные 8 байт каждого профиля.
    var hold = 6.0
    if let i = args.firstIndex(of: "--hold"), i + 1 < args.count, let v = Double(args[i + 1]) { hold = min(max(v, 2), 30) }
    let scanModes: [UInt8] = Array(1...18) + [20]
    if !args.contains("--send") {
        print("Пробный режим. Будут показаны режимы \(scanModes) по \(Int(hold)) с с красным цветом; для запуска добавьте --send.")
        exit(0)
    }
    guard let d = devs.first(where: { intProp($0, "MaxOutputReportSize") == 64 }), let session = K530Session(device: d) else {
        fputs("Не удалось открыть служебный интерфейс.\n", stderr); exit(3)
    }
    guard let before = session.readProfiles() else { fputs("Не удалось прочитать профили.\n", stderr); exit(4) }
    guard before.allSatisfy({ (1...18).contains(Int($0[0])) || $0[0] == 20 }) else { fputs("Необычные режимы в профилях, отмена.\n", stderr); exit(4) }
    let backupPath = saveBackupOrExit(before)
    print("Резервная копия: \(backupPath)")
    signal(SIGINT) { _ in interrupted = 1 }
    func speak(_ t: String) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = [t]; try? p.run() }
    var failed = !session.writeFields([(4, [0]), (5, [255, 0, 0])])
    let ask = args.contains("--ask")
    var answers: [(UInt8, String)] = []
    if !failed {
        for m in scanModes where interrupted == 0 {
            guard session.writeModes([m, m, m]) else { failed = true; break }
            if ask {
                // Интерактивный режим: режим держится, пока вы не ответите (y — красный виден, n — нет, s — не уверен, q — выход).
                print("Режим \(m). Клавиатура светится красным? [y/n/s/q] ", terminator: ""); fflush(stdout)
                guard let line = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(), line != "q", !line.isEmpty else { break }
                answers.append((m, line.hasPrefix("y") || line.hasPrefix("д") ? "красный" : line.hasPrefix("n") || line.hasPrefix("н") ? "НЕ красный" : "не уверен"))
            } else {
                print("режим \(m)"); fflush(stdout)
                speak("Mode \(m)")
                let end = Date().addingTimeInterval(hold)
                while Date() < end && interrupted == 0 { CFRunLoopRunInMode(.defaultMode, 0.1, false) }
            }
        }
    }
    if ask {
        let summary = answers.map { "режим \($0.0): \($0.1)" }.joined(separator: "\n")
        print("\nИтог:\n" + summary)
        let resultURL = researchDirectory().appendingPathComponent("color-scan-result.txt")
        do { try summary.write(to: resultURL, atomically: true, encoding: .utf8); print("Сохранено: \(resultURL.path)") }
        catch { fputs("Не удалось сохранить итог: \(error.localizedDescription)\n", stderr) }
    }
    let ok = session.restoreHeads(before) && session.readProfiles().map { zip(before, $0).allSatisfy { Array($0.0.prefix(8)) == Array($0.1.prefix(8)) } } == true
    print(ok ? "Исходное состояние восстановлено и проверено чтением." : "ВНИМАНИЕ: восстановление не подтверждено, см. резервную копию.")
    exit(ok && !failed ? 0 : 6)
default:
    usage()
}
