import Foundation

/// Минимальный разборщик HID Report Descriptor для диагностики (только вывод, без интерпретации семантики).
enum HIDDescriptor {
    private static let mainNames: [UInt8: String] = [
        0x8: "Input", 0x9: "Output", 0xB: "Feature", 0xA: "Collection", 0xC: "End Collection",
    ]
    private static let globalNames: [UInt8: String] = [
        0x0: "Usage Page", 0x1: "Logical Min", 0x2: "Logical Max", 0x3: "Physical Min", 0x4: "Physical Max",
        0x5: "Unit Exponent", 0x6: "Unit", 0x7: "Report Size", 0x8: "Report ID", 0x9: "Report Count",
        0xA: "Push", 0xB: "Pop",
    ]
    private static let localNames: [UInt8: String] = [
        0x0: "Usage", 0x1: "Usage Min", 0x2: "Usage Max",
    ]

    /// Описание одного отчёта: направление, ID и размер в байтах (без байта Report ID).
    struct Report: Hashable {
        let kind: String
        let id: UInt8
        var bits: Int
        var bytes: Int { (bits + 7) / 8 }
    }

    static func dump(_ d: [UInt8]) -> (text: String, reports: [Report]) {
        var out = ""
        var i = 0, indent = 0
        var size = 0, count = 0, rid: UInt8 = 0
        var bits: [String: Int] = [:]
        var order: [Report] = []
        while i < d.count {
            let prefix = d[i]
            if prefix == 0xFE { break }
            let sz = [0, 1, 2, 4][Int(prefix & 3)]
            let type = (prefix >> 2) & 3, tag = prefix >> 4
            var v = 0
            for k in 0..<sz where i + 1 + k < d.count { v |= Int(d[i + 1 + k]) << (8 * k) }
            let raw = d[i..<min(i + 1 + sz, d.count)].map { String(format: "%02X", $0) }.joined(separator: " ")
            var name: String
            switch type {
            case 0:
                name = mainNames[tag] ?? "Main(\(tag))"
                if tag == 0xC { indent = max(0, indent - 1) }
                if tag == 0x8 || tag == 0x9 || tag == 0xB {
                    let kind = tag == 0x8 ? "Input" : tag == 0x9 ? "Output" : "Feature"
                    let key = "\(kind)/\(rid)"
                    if bits[key] == nil { order.append(Report(kind: kind, id: rid, bits: 0)) }
                    bits[key, default: 0] += size * count
                    name += String(format: " (0x%02X)", v)
                }
            case 1:
                name = globalNames[tag] ?? "Global(\(tag))"
                if tag == 0x7 { size = v }
                if tag == 0x9 { count = v }
                if tag == 0x8 { rid = UInt8(truncatingIfNeeded: v) }
                name += String(format: " (%d / 0x%X)", v, v)
            case 2:
                name = localNames[UInt8(tag)] ?? "Local(\(tag))"
                name += String(format: " (0x%X)", v)
            default:
                name = "Reserved"
            }
            out += String(repeating: "  ", count: indent) + String(format: "%-14@ ", raw as NSString) + name + "\n"
            if type == 0 && tag == 0xA { indent += 1 }
            i += 1 + sz
        }
        let reports = order.map { Report(kind: $0.kind, id: $0.id, bits: bits["\($0.kind)/\($0.id)"] ?? 0) }
        return (out, reports)
    }
}
