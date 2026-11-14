import SwiftUI
import AppKit

/// Палитра повторяет согласованный макет; акценты без неонового размытия.
private enum Theme {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.086)
    static let cyan = Color(red: 0, green: 0.90, blue: 1)
    static let muted = Color(red: 0.60, green: 0.65, blue: 0.71)
}

struct LightingView: View {
    @ObservedObject var model: LightingController
    @ObservedObject var updater: AppUpdater
    @State private var hexInput = "#00E5FF"
    @State private var invalidHex = false
    @State private var showingProfiles = false
    private var color: Color {
        Color(.sRGB, red: Double(model.draft.red) / 255,
              green: Double(model.draft.green) / 255, blue: Double(model.draft.blue) / 255)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if model.needsPermission { permissionNotice }
                    KeyboardPreview(color: model.draft.usesColor ? color : Theme.cyan,
                                    brightness: model.draft.brightness, colourful: model.draft.colourful)
                        .frame(width: 470, height: 168).frame(maxWidth: .infinity)
                        .accessibilityLabel("Предпросмотр цвета подсветки; не редактор отдельных клавиш")
                    Text("Предпросмотр цвета").font(.system(size: 10)).foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, -10)
                    Divider()
                    controls.disabled(model.busy || updater.isBusy)
                    Divider()
                    HStack(spacing: 12) {
                        Text(model.selectedProfile?.name ?? "Профили")
                            .font(.system(size: 12)).foregroundColor(Theme.muted).lineLimit(1)
                        if model.hasUnsavedProfileChanges {
                            Text("• не сохранён").font(.system(size: 10)).foregroundColor(Theme.muted)
                        }
                        Spacer(minLength: 4)
                        Button("Вернуть исходное", action: model.restore)
                            .buttonStyle(PanelActionStyle(primary: false))
                            .disabled(!model.canRestore || model.busy || updater.isBusy)
                        Button("Применить", action: model.apply)
                            .buttonStyle(PanelActionStyle(primary: true))
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(!model.connected || model.busy || !model.hasChanges || updater.isBusy)
                    }
                }.padding(24).frame(maxWidth: .infinity)
            }
            if updater.isBusy {
                if let progress = updater.progress { ProgressView(value: progress).padding(.horizontal, 16) }
                else { ProgressView().scaleEffect(0.5).frame(height: 12) }
            }
            Divider()
            status
        }
        .frame(width: 740, height: 680)
        .background(Theme.background).foregroundColor(.white)
        .accentColor(Theme.cyan).colorScheme(.dark)
        .onAppear { hexInput = model.draft.hex }
        .onChange(of: model.draft.hex) { hexInput = $0; invalidHex = false }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("K530 LIGHTING").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.cyan)
                Text("Redragon K530").font(.system(size: 24, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(model.connected ? Color.green : Theme.muted).frame(width: 6, height: 6)
                    Text(model.needsPermission ? "Нужен доступ к клавиатуре" : model.connected ? "USB подключена" : "Нет подключения")
                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                }
            }
            Spacer()
            Button { showingProfiles.toggle() } label: {
                Label("Профили", systemImage: "square.stack")
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.05)).cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.15)))
            }.buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showingProfiles, arrowEdge: .bottom) {
                    LightingProfilesView(model: model, updater: updater)
                }
            Menu {
                Button("Перечитать устройство", action: model.refresh).disabled(model.busy || updater.isBusy)
                Button(model.autostart ? "✓ Запускать при входе" : "Запускать при входе", action: model.toggleAutostart)
                Button("Проверить обновления…", action: model.checkUpdates).disabled(updater.isBusy || model.busy)
                Button("Мониторинг ввода…", action: model.openInputSettings)
                Button("Перезапустить приложение", action: model.restartApplication).disabled(model.busy || updater.isBusy)
                Button("Справка (FAQ)…", action: model.showHelp)
                Divider()
                Button("Выйти") { NSApp.terminate(nil) }.disabled(updater.isBusy || model.busy)
            } label: { Image(systemName: "gearshape").font(.system(size: 17)) }
            .menuStyle(BorderlessButtonMenuStyle()).frame(width: 30)
            .accessibilityLabel("Настройки приложения")
        }
    }

    /// Действия открывают системные настройки, но не меняют разрешения за пользователя.
    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Разрешите доступ к клавиатуре", systemImage: "lock.shield")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.orange)
            Text("В «Мониторинге ввода» включите K530Lighting. Если запись осталась от старой сборки, удалите её и добавьте текущую .app. Затем перезапустите приложение.")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Открыть настройки", action: model.openInputSettings)
                Button("Показать эту .app", action: model.revealApplication)
                Button("Перезапустить", action: model.restartApplication)
                    .disabled(model.busy || updater.isBusy)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.07)).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3)))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                rowLabel("Эффект")
                effectButton("Постоянный", id: 6, symbol: "sun.max")
                effectButton("Дыхание", id: 5, symbol: "waveform.path")
                Menu {
                    ForEach(modes, id: \.id) { mode in
                        Button("\(mode.id). \(mode.name)") { model.draft.mode = mode.id }
                    }
                } label: {
                    Text([5, 6].contains(model.draft.mode) ? "Все эффекты · 19" :
                            modes.first(where: { $0.id == model.draft.mode })?.name ?? "Эффект")
                        .lineLimit(1).frame(maxWidth: .infinity)
                }.frame(width: 190)
            }
            colorRow
            hexRow
            if !model.draft.usesColor {
                Text("Этот эффект использует собственную палитру.").font(.caption).foregroundColor(Theme.muted)
                    .padding(.leading, 82)
            }
            slider("Яркость", value: $model.draft.brightness, range: 0...4, denominator: 4)
            slider("Скорость", value: $model.draft.speed, range: 1...5, denominator: 5)
        }
    }

    private var colorRow: some View {
            HStack {
                rowLabel("Цвет")
                ForEach(0..<presets.count, id: \.self) { index in
                    swatch(presets[index])
                }
                Spacer(minLength: 0)
                ColorPicker("Другой цвет", selection: Binding(get: { color }, set: { newColor in
                    guard let c = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                    model.draft.red = UInt8((c.redComponent * 255).rounded())
                    model.draft.green = UInt8((c.greenComponent * 255).rounded())
                    model.draft.blue = UInt8((c.blueComponent * 255).rounded())
                    model.draft.colourful = false
                }), supportsOpacity: false).labelsHidden().help("Палитра macOS")
            }.disabled(!model.draft.usesColor).opacity(model.draft.usesColor ? 1 : 0.4)
    }
    private var hexRow: some View {
            HStack {
                rowLabel("")
                TextField("#RRGGBB", text: $hexInput, onCommit: {
                    invalidHex = !model.draft.setHex(hexInput)
                }).font(.system(size: 12, design: .monospaced)).frame(width: 100)
                    .textFieldStyle(RoundedBorderTextFieldStyle()).disabled(!model.draft.usesColor)
                    .accessibilityLabel("Цвет HEX; Enter для подтверждения")
                if invalidHex { Text("Введите #RRGGBB").font(.caption).foregroundColor(.orange) }
                Spacer()
                Toggle("Разноцветный", isOn: $model.draft.colourful).toggleStyle(SwitchToggleStyle())
                    .font(.system(size: 12)).disabled(!model.draft.usesColor)
            }
    }
    private func swatch(_ preset: Preset) -> some View {
        let rgb = preset.rgb
        let selected = !model.draft.colourful && model.draft.red == rgb.0 && model.draft.green == rgb.1 && model.draft.blue == rgb.2
        let fill = Color(.sRGB, red: Double(rgb.0)/255, green: Double(rgb.1)/255, blue: Double(rgb.2)/255)
        return Button {
            model.draft.red = rgb.0; model.draft.green = rgb.1; model.draft.blue = rgb.2
            model.draft.colourful = false
        } label: {
            Circle().fill(fill).frame(width: 19, height: 19).padding(3)
                .overlay(Circle().stroke(selected ? Theme.cyan : .clear, lineWidth: 1))
        }.buttonStyle(PlainButtonStyle()).help(preset.name).accessibilityLabel(preset.name)
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .medium)).frame(width: 70, alignment: .leading)
    }
    private func effectButton(_ title: String, id: UInt8, symbol: String) -> some View {
        Button { model.draft.mode = id } label: {
            Label(title, systemImage: symbol).font(.system(size: 12)).frame(maxWidth: .infinity)
                .padding(.vertical, 10).background(model.draft.mode == id ? Theme.cyan.opacity(0.09) : Color.white.opacity(0.03))
                .cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(model.draft.mode == id ? Theme.cyan : Color.white.opacity(0.15)))
        }.buttonStyle(PlainButtonStyle())
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, denominator: Int) -> some View {
        HStack(spacing: 14) {
            rowLabel(title)
            Slider(value: value, in: range, step: 1).accessibilityLabel(title)
            Text("\(Int(value.wrappedValue)) / \(denominator)").font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.muted).frame(width: 55)
        }
    }
    /// Строка закреплена вне ScrollView и остаётся у нижней границы окна.
    /// Полные сообщения доступны в подсказках и VoiceOver при сокращении текста.
    private var status: some View {
        let deviceMessage = model.hasChanges && !model.busy && !model.error && model.connected ?
            "Есть неприменённые изменения" : model.message
        return HStack(spacing: 12) {
            Label("Запись во все 3 профиля", systemImage: "square.3.stack.3d")
                .frame(width: 155, alignment: .leading)
                .help("Настройки выбранного набора записываются во все три аппаратных профиля клавиатуры")
            HStack(spacing: 5) {
                Image(systemName: model.error ? "exclamationmark.circle" : model.busy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    .foregroundColor(model.error ? .orange : Theme.muted)
                Text(model.profileError ?? deviceMessage)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .help(model.profileError ?? deviceMessage).accessibilityLabel(model.profileError ?? deviceMessage)
            Text(updater.message).frame(width: 185, alignment: .trailing)
                .help(updater.message).accessibilityLabel(updater.message)
        }
        .font(.system(size: 10)).foregroundColor(Theme.muted).lineLimit(1)
        .truncationMode(.tail).padding(.horizontal, 20).frame(height: 38)
    }

}

/// Упрощённая ANSI 60% геометрия. Это индикатор общего цвета, без per-key управления.
struct KeyboardPreview: View {
    let color: Color
    let brightness: Double
    let colourful: Bool
    private let rows: [[String]] = [
        ["Esc", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "−", "=", "⌫"],
        ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
        ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Enter"],
        ["Shift", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "Shift"],
        ["Ctrl", "Win", "Alt", "", "Alt", "Fn", "☰", "Ctrl"]
    ]
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<rows.count, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<rows[row].count, id: \.self) { column in
                        key(rows[row][column], row: row, column: column)
                    }
                }
            }
        }.padding(8).background(Color.black.opacity(0.6)).cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.16)))
    }
    private func key(_ label: String, row: Int, column: Int) -> some View {
        let tint = brightness == 0 ? Color.gray : colourful ?
            Color(hue: Double(column) / 16, saturation: 0.8, brightness: 0.9) : color
        return Text(label.isEmpty ? "━━━━" : label).font(.system(size: 8, weight: .medium))
            .foregroundColor(tint.opacity(0.25 + brightness * 0.18))
            .frame(maxWidth: .infinity).frame(width: label.isEmpty ? 172 : nil, height: 26)
            .background(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.025)]), startPoint: .top, endPoint: .bottom))
            .cornerRadius(3).overlay(RoundedRectangle(cornerRadius: 3).stroke(tint.opacity(brightness * 0.045)))
    }
}

/// Единые размеры, шрифт и контраст обеих основных кнопок, включая disabled.
struct PanelActionStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .foregroundColor(primary && enabled ? Color.black : Color.white.opacity(enabled ? 0.9 : 0.5))
            .frame(width: 154, height: 36)
            .background(primary && enabled ? Theme.cyan : Color.white.opacity(enabled ? 0.07 : 0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(primary && enabled ? 0 : 0.14)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
