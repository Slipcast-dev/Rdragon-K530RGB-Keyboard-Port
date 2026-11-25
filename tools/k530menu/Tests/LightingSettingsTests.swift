import Foundation

/// Проверки границ протокола и преобразований UI без подключения клавиатуры.
@main
struct LightingSettingsTests {
    static func main() {
        precondition(LightingSettings(profile: []) == nil)
        precondition(LightingSettings(profile: [19, 3, 2, 0, 0, 0, 0, 0]) == nil)
        precondition(LightingSettings(profile: [5, 5, 2, 0, 0, 0, 0, 0]) == nil)
        precondition(LightingSettings(profile: [5, 4, 5, 0, 0, 0, 0, 0]) == nil)
        for rawSpeed: UInt8 in 0...4 {
            let profile: [UInt8] = [5, 4, rawSpeed, 0, 1, 18, 171, 255]
            guard let state = LightingSettings(profile: profile) else { fatalError("Профиль не разобран") }
            precondition(state.speed == Double(5 - rawSpeed))
            precondition(state.fields.first(where: { $0.offset == 2 })!.data == [rawSpeed])
            precondition(state.hex == "#12ABFF")
        }
        var state = LightingSettings()
        precondition(state.setHex("#abcdef")); precondition(state.hex == "#ABCDEF")
        let before = state
        for bad in ["#FFF", "#1234567", "GGGGGG", "１２３４５６", "12345 ", "-12345"] {
            precondition(!state.setHex(bad)); precondition(state == before)
        }
        state.mode = 4; precondition(!state.usesColor)
        state.mode = 5; precondition(state.usesColor)
        state.brightness = 0; precondition(state.fields.first(where: { $0.offset == 1 })!.data == [0])
        // Голова профиля для записи одним пакетом: байт +3 берётся из клавиатуры, остальные совпадают с fields.
        let device: [UInt8] = [20, 4, 2, 0xAB, 255, 255, 0, 0, 9]
        let head = state.head(preserving: device)
        precondition(head.count == 8 && head[3] == 0xAB)
        for field in state.fields { precondition(Array(head[field.offset..<(field.offset + field.data.count)]) == field.data) }
        precondition(LightingSettings(profile: head) == state)
        print("LightingSettings: все проверки пройдены")
    }
}
