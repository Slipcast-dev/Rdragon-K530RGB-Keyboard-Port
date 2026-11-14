import Foundation

let vendorID = 0x0C45, productID = 0x5004

/// Режимы подсветки и их названия из Lang0409.ini штатной программы (машинный перевод с китайского).
let modes: [(id: UInt8, name: String)] = [
    (1, "Go with the stream"), (2, "Clouds fly"), (3, "Winding paths"), (4, "The trial of light"),
    (5, "Breathing"), (6, "Normally on"), (7, "Pass without trace"), (8, "Ripple graff"),
    (9, "Fast run without trace"), (10, "Snow winter jasmine"), (11, "Flowers blooming"),
    (12, "Swift action"), (13, "Hurricane"), (14, "Accumulate"), (15, "Digital Times"),
    (16, "Both ways"), (17, "Surmount"), (18, "Fast and the Furious"), (20, "Coastal"),
]
let knownModes = Set(modes.map { $0.id })
/// Режимы, в которых виден выбранный цвет (проверено человеком у клавиатуры: красный в режимах 1–3, 5–10, 13–16).
/// В режимах 4, 11, 12, 17, 18 и 20 цвет не меняется — у них собственная палитра.
let colorModes: Set<UInt8> = [1, 2, 3, 5, 6, 7, 8, 9, 10, 13, 14, 15, 16]

struct Preset { let name: String; let rgb: (UInt8, UInt8, UInt8) }
let presets = [
    Preset(name: "Красный", rgb: (255, 0, 0)), Preset(name: "Оранжевый", rgb: (255, 127, 0)),
    Preset(name: "Жёлтый", rgb: (255, 255, 0)), Preset(name: "Зелёный", rgb: (0, 255, 0)),
    Preset(name: "Голубой", rgb: (0, 255, 255)), Preset(name: "Синий", rgb: (0, 0, 255)),
    Preset(name: "Фиолетовый", rgb: (128, 0, 255)), Preset(name: "Розовый", rgb: (255, 0, 255)),
    Preset(name: "Белый", rgb: (255, 255, 255)),
]
/// Скорость (+2): значение 0 — быстрее всего, 4 — медленнее всего (слайдер штатной программы инвертирован). Не проверено на клавиатуре.
let speedLevels = [(4, "1 — медленно"), (3, "2"), (2, "3"), (1, "4"), (0, "5 — быстро")]
let brightnessLevels = [(0, "0 — выключена"), (1, "1"), (2, "2"), (3, "3"), (4, "4 — максимум")]


/// Редактируемая копия настроек: до «Применить» не отправляется в устройство.
struct LightingSettings: Equatable {
    var mode: UInt8 = 5
    var brightness: Double = 3
    var speed: Double = 2
    var colourful = false
    var red: UInt8 = 0
    var green: UInt8 = 229
    var blue: UInt8 = 255

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    var usesColor: Bool { colorModes.contains(mode) }
    var fields: [(offset: Int, data: [UInt8])] {
        [(0, [mode]), (1, [UInt8(brightness.rounded())]),
         (2, [UInt8(5 - speed.rounded())]), (4, [colourful ? 1 : 0]),
         (5, [red, green, blue])]
    }

    init() {}
    init?(profile: [UInt8]) {
        guard profile.count >= 8, knownModes.contains(profile[0]),
              profile[1] <= 4, profile[2] <= 4 else { return nil }
        mode = profile[0]; brightness = Double(profile[1]); speed = Double(5 - profile[2])
        colourful = profile[4] != 0; red = profile[5]; green = profile[6]; blue = profile[7]
    }

    /// HEX допускает только шесть ASCII-цифр; некорректный ввод не меняет цвет.
    mutating func setHex(_ value: String) -> Bool {
        let text = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard text.utf8.count == 6, text.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }), let rgb = UInt32(text, radix: 16) else { return false }
        red = UInt8((rgb >> 16) & 255); green = UInt8((rgb >> 8) & 255)
        blue = UInt8(rgb & 255); colourful = false
        return true
    }
}
