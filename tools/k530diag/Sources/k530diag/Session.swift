import Foundation
import IOKit
import IOKit.hid

/// Сеанс обмена со служебным интерфейсом (Output/Input Report ID 4): отправка пакета и ожидание ответа.
final class K530Session {
    private final class Inbox { var items: [[UInt8]] = [] }
    private let dev: IOHIDDevice
    private let inbox = Inbox()
    private let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)

    init?(device: IOHIDDevice) {
        dev = device
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
        IOHIDDeviceRegisterInputReportCallback(device, buf, 256, { ctx, _, _, _, id, rep, len in
            guard id == UInt32(K530Protocol.reportID) else { return }
            let bytes = Array(UnsafeBufferPointer(start: rep, count: len))
            Unmanaged<Inbox>.fromOpaque(ctx!).takeUnretainedValue().items.append(bytes)
        }, Unmanaged.passUnretained(inbox).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// Отправка с ожиданием ответа до 1 с и до 3 попыток, как в штатной программе. Возвращает проверенный ответ.
    func exchange(_ cmd: K530Protocol.Command, length: UInt8 = 0, address: UInt16 = 0, data: [UInt8] = []) -> [UInt8]? {
        let p = K530Protocol.packet(cmd, length: length, address: address, data: data)
        for _ in 0..<3 {
            inbox.items.removeAll()
            let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(p[0]), p, p.count)
            if r != kIOReturnSuccess { fputs(String(format: "SetReport: IOReturn 0x%08X\n", r), stderr); return nil }
            let deadline = Date().addingTimeInterval(1.0)
            while inbox.items.isEmpty && Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.05, false) }
            if let raw = inbox.items.first {
                do { return try K530Protocol.validate(response: raw, for: cmd) }
                catch { fputs("Ответ отклонён: \(error)\n", stderr); return nil }
            }
        }
        fputs("Нет ответа на команду 0x\(String(cmd.rawValue, radix: 16)).\n", stderr)
        return nil
    }

    /// Читает три профиля (begin → read×3 → end) и возвращает по 42 байта каждого.
    func readProfiles() -> [[UInt8]]? {
        guard exchange(.begin) != nil else { return nil }
        var out: [[UInt8]] = []
        for i in 0..<K530Protocol.profileCount {
            guard let r = exchange(.read, length: K530Protocol.readChunk, address: UInt16(i * K530Protocol.profileSize)) else {
                _ = exchange(.end); return nil
            }
            out.append(Array(r[8..<(8 + K530Protocol.profileSize)]))
        }
        _ = exchange(.end)
        return out
    }

    /// Записывает байт режима (+0) во все три профиля (begin → write×3 → end).
    func writeModes(_ modes: [UInt8]) -> Bool {
        guard exchange(.begin) != nil else { return false }
        var ok = true
        for (i, m) in modes.enumerated() {
            let addr = UInt16(i * K530Protocol.profileSize)
            if exchange(.write, length: 1, address: addr, data: [m]) == nil { ok = false; break }
        }
        _ = exchange(.end)
        return ok
    }

    /// Записывает поля профиля одним сеансом (begin → write… → end): для каждого поля и каждого из трёх профилей.
    /// `offset` — смещение внутри 42-байтового профиля. Возвращает false при первой ошибке.
    func writeFields(_ fields: [(offset: Int, data: [UInt8])]) -> Bool {
        guard exchange(.begin) != nil else { return false }
        var ok = true
        outer: for p in 0..<K530Protocol.profileCount {
            for f in fields {
                let addr = UInt16(p * K530Protocol.profileSize + f.offset)
                if exchange(.write, length: UInt8(f.data.count), address: addr, data: f.data) == nil { ok = false; break outer }
            }
        }
        _ = exchange(.end)
        return ok
    }

    /// Возвращает первые 8 байт каждого профиля (режим, яркость, скорость, +3, флаг цвета, RGB) к сохранённым значениям.
    func restoreHeads(_ before: [[UInt8]]) -> Bool {
        guard exchange(.begin) != nil else { return false }
        var ok = true
        for (i, p) in before.enumerated() {
            if exchange(.write, length: 8, address: UInt16(i * K530Protocol.profileSize), data: Array(p.prefix(8))) == nil { ok = false; break }
        }
        _ = exchange(.end)
        return ok
    }
}
