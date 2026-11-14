import Foundation

/// Формат пакета служебного канала K530 (Report ID 4, 64 байта), восстановленный статическим анализом.
/// См. research/protocol-findings.md. На железе не проверено.
enum K530Protocol {
    static let reportID: UInt8 = 4
    static let packetSize = 64

    /// Команды, используемые в этой утилите: сеанс, чтение и запись (0x06) — запись только через `test-mode`.
    /// Команда 0x17 (блочная запись) и функция с байтами 0xEE 0xEE сюда намеренно не добавлены.
    enum Command: UInt8 {
        case begin = 0x01
        case end = 0x02
        case read = 0x05
        case write = 0x06
    }

    /// Собирает пакет: [0]=ID, [1..2]=сумма байтов 3…63 (младший первым), [3]=команда, [4]=длина, [5..6]=адрес.
    static func packet(_ cmd: Command, length: UInt8 = 0, address: UInt16 = 0, data: [UInt8] = []) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: packetSize)
        p[0] = reportID
        p[3] = cmd.rawValue
        p[4] = length
        p[5] = UInt8(address & 0xFF)
        p[6] = UInt8(address >> 8)
        for (i, byte) in data.prefix(56).enumerated() { p[8 + i] = byte }
        let sum = p[3...].reduce(0) { $0 + Int($1) }
        p[1] = UInt8(sum & 0xFF)
        p[2] = UInt8((sum >> 8) & 0xFF)
        return p
    }

    /// Приводит входящий отчёт к 64 байтам с ID в первом байте (macOS может отдать 63 байта без ID).
    static func normalize(_ raw: [UInt8]) -> [UInt8]? {
        if raw.count == packetSize && raw[0] == reportID { return raw }
        if raw.count == packetSize - 1 { return [reportID] + raw }
        return nil
    }

    enum ResponseError: Error, CustomStringConvertible {
        case malformed, commandMismatch(UInt8), deviceError(UInt8)
        var description: String {
            switch self {
            case .malformed: return "ответ неверной длины"
            case .commandMismatch(let c): return String(format: "в ответе другая команда: 0x%02X", c)
            case .deviceError(let s): return String(format: "устройство вернуло статус 0x%02X (ошибка или занято)", s)
            }
        }
    }

    /// Проверка ответа по логике штатной программы: байт 3 совпадает с командой, байт 7 не 0xFF/0xFE.
    static func validate(response: [UInt8], for cmd: Command) throws -> [UInt8] {
        guard let r = normalize(response) else { throw ResponseError.malformed }
        guard r[3] == cmd.rawValue else { throw ResponseError.commandMismatch(r[3]) }
        guard r[7] != 0xFF && r[7] != 0xFE else { throw ResponseError.deviceError(r[7]) }
        return r
    }

    // MARK: Профили

    static let profileCount = 3
    static let profileSize = 42
    /// Штатная программа читает по 56 байт с адресов 0, 42, 84 и сохраняет первые 42 байта каждого чтения.
    static let readChunk: UInt8 = 56

    /// Расшифровка известных полей профиля (см. таблицу уверенности в protocol-findings.md).
    static func describeProfile(_ b: [UInt8]) -> String {
        guard b.count >= profileSize else { return "  (мало данных)\n" }
        func h(_ r: ClosedRange<Int>) -> String { b[r].map { String(format: "%02x", $0) }.joined(separator: " ") }
        var s = ""
        s += "  +0  режим подсветки: \(b[0])" + ((1...18).contains(Int(b[0])) || b[0] == 20 ? "" : "  (вне известного набора 1–18, 20)") + "\n"
        s += "  +1  [неизвестно, ожидаются значения 21–25]: \(b[1])\n"
        s += "  +2  [неизвестно]: \(b[2])\n"
        s += "  +3  [неизвестно, 0 или 255]: \(b[3])\n"
        s += "  +4  флаг Colourful: \(b[4])\n"
        s += String(format: "  +5…+7 цвет RGB: #%02X%02X%02X\n", b[5], b[6], b[7])
        s += "  +15 [неизвестно, ожидается 0…3]: \(b[15])\n"
        s += "  +18 [неизвестно]: \(b[18])\n"
        s += "  +24 [неизвестно]: \(b[24])\n"
        s += "  сырые 42 байта: \(h(0...41))\n"
        return s
    }
}
