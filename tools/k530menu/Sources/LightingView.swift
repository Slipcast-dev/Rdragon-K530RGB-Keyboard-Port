import SwiftUI
import AppKit

/// Палитра повторяет согласованный макет; акценты без неонового размытия.
enum AppTheme {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.086)
    static let cyan = Color(red: 0, green: 0.90, blue: 1)
    static let muted = Color(red: 0.60, green: 0.65, blue: 0.71)
}

struct LightingView: View {
    @ObservedObject var model: LightingController
    @ObservedObject var updater: AppUpdater
    @ObservedObject private var localization = AppLocalization.shared
    @State private var hexInput = "#00E5FF"
    @State private var invalidHex = false
    @State private var showingProfiles = false
    @State private var showingSettings = false
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
                    KeyboardPreview(color: model.draft.usesColor ? color : AppTheme.cyan,
                                    brightness: model.draft.brightness, colourful: model.draft.colourful)
                        .frame(width: 470, height: 168).frame(maxWidth: .infinity)
                        .accessibilityLabel(L("Предпросмотр цвета подсветки; не редактор отдельных клавиш", "Lighting color preview; not a per-key editor"))
                    Text(L("Предпросмотр цвета", "Color preview")).font(.system(size: 10)).foregroundColor(AppTheme.muted)
                        .frame(maxWidth: .infinity).padding(.top, -10)
                    Divider()
                    controls.disabled(model.busy || updater.isBusy)
                    Divider()
                    HStack(spacing: 12) {
                        Text(model.selectedProfile?.name ?? L("Профили", "Profiles"))
                            .font(.system(size: 12)).foregroundColor(AppTheme.muted).lineLimit(1)
                        if model.hasUnsavedProfileChanges {
                            Text(L("• не сохранён", "• unsaved")).font(.system(size: 10)).foregroundColor(AppTheme.muted)
                        }
                        Spacer(minLength: 4)
                        Button { showingProfiles.toggle() } label: {
                            Label(L("Профили", "Profiles"), systemImage: "square.stack")
                        }
                        .buttonStyle(PanelActionStyle(primary: false))
                        .popover(isPresented: $showingProfiles, arrowEdge: .top) {
                            LightingProfilesView(model: model, updater: updater)
                        }
                        Button(L("Вернуть исходное", "Restore initial"), action: model.restore)
                            .buttonStyle(PanelActionStyle(primary: false))
                            .disabled(!model.canRestore || model.busy || updater.isBusy)
                        Button(L("Применить", "Apply"), action: model.apply)
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
        .background(AppTheme.background).foregroundColor(.white)
        .accentColor(AppTheme.cyan).colorScheme(.dark)
        .onAppear { hexInput = model.draft.hex }
        .onChange(of: model.draft.hex) { hexInput = $0; invalidHex = false }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("K530 LIGHTING").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.cyan)
                Text("Redragon K530").font(.system(size: 24, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(model.connected ? Color.green : AppTheme.muted).frame(width: 6, height: 6)
                    Text(model.needsPermission ? L("Нужен доступ к клавиатуре", "Keyboard access required") : model.connected ? L("USB подключена", "USB connected") : L("Нет подключения", "Disconnected"))
                        .font(.system(size: 11)).foregroundColor(AppTheme.muted)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button { localization.toggle() } label: {
                    Text(localization.language.rawValue.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .buttonStyle(HeaderControlStyle())
                .help(L("Переключить на английский", "Switch to Russian"))
                .accessibilityLabel(L("Язык: русский. Переключить на английский", "Language: English. Switch to Russian"))
                Button { showingSettings.toggle() } label: {
                    Image(systemName: "gearshape").font(.system(size: 16))
                }
                .buttonStyle(HeaderControlStyle())
                .help(L("Настройки приложения", "App settings"))
                .accessibilityLabel(L("Настройки приложения", "App settings"))
                .popover(isPresented: $showingSettings, arrowEdge: .bottom) { settingsPopover }
            }

        }
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            settingsAction(L("Перечитать устройство", "Read device again"), enabled: !model.busy && !updater.isBusy, action: model.refresh)
            settingsAction((model.autostart ? "✓ " : "") + L("Запускать при входе", "Launch at login"), action: model.toggleAutostart)
            settingsAction(L("Проверить обновления…", "Check for updates…"), enabled: !model.busy && !updater.isBusy, action: model.checkUpdates)
            settingsAction(L("Перезапустить приложение", "Restart application"), enabled: !model.busy && !updater.isBusy, action: model.restartApplication)
            settingsAction(L("Справка (FAQ)…", "Help (FAQ)…"), action: model.showHelp)
            Divider().padding(.vertical, 4)
            settingsAction(L("Выйти", "Quit"), enabled: !model.busy && !updater.isBusy) { NSApp.terminate(nil) }
        }.padding(10).frame(width: 250)
            .background(AppTheme.background).foregroundColor(.white)
            .preferredColorScheme(.dark)
    }

    private func settingsAction(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            showingSettings = false
            action()
        } label: {
            Text(title).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(PlainButtonStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }

    /// Действия открывают системные настройки, но не меняют разрешения за пользователя.
    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Разрешите доступ к клавиатуре", "Allow keyboard access"), systemImage: "lock.shield")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.orange)
            Text(L("В «Мониторинге ввода» включите K530Lighting. Если запись осталась от старой сборки, удалите её и добавьте текущую .app. Затем перезапустите приложение.", "Enable K530Lighting in Input Monitoring. If an entry from an older build remains, remove it and add this .app, then restart the application."))
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(L("Открыть настройки", "Open Settings"), action: model.openInputSettings)
                Button(L("Показать эту .app", "Show this .app"), action: model.revealApplication)
                Button(L("Перезапустить", "Restart"), action: model.restartApplication)
                    .disabled(model.busy || updater.isBusy)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.07)).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3)))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                rowLabel(L("Эффект", "Effect"))
                effectButton(L("Постоянный", "Steady"), id: 6, symbol: "sun.max")
                effectButton(L("Дыхание", "Breathing"), id: 5, symbol: "waveform.path")
                Menu {
                    ForEach(modes, id: \.id) { mode in
                        Button("\(mode.id). \(localizedModeName(mode.id))") { model.draft.mode = mode.id }
                    }
                } label: {
                    Text([5, 6].contains(model.draft.mode) ? L("Все эффекты · 19", "All effects · 19") :
                            localizedModeName(model.draft.mode))
                        .lineLimit(1).frame(maxWidth: .infinity)
                }.frame(width: 190)
            }
            colorRow
            hexRow
            if !model.draft.usesColor {
                Text(L("Этот эффект использует собственную палитру.", "This effect uses its own palette.")).font(.caption).foregroundColor(AppTheme.muted)
                    .padding(.leading, 82)
            }
            slider(L("Яркость", "Brightness"), value: $model.draft.brightness, range: 0...4, denominator: 4)
            slider(L("Скорость", "Speed"), value: $model.draft.speed, range: 1...5, denominator: 5)
        }
    }

    private var colorRow: some View {
            HStack {
                rowLabel(L("Цвет", "Color"))
                ForEach(0..<presets.count, id: \.self) { index in
                    swatch(presets[index])
                }
                Spacer(minLength: 0)
                ColorPicker(L("Другой цвет", "Custom color"), selection: Binding(get: { color }, set: { newColor in
                    guard let c = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                    model.draft.red = UInt8((c.redComponent * 255).rounded())
                    model.draft.green = UInt8((c.greenComponent * 255).rounded())
                    model.draft.blue = UInt8((c.blueComponent * 255).rounded())
                    model.draft.colourful = false
                }), supportsOpacity: false).labelsHidden().help(L("Палитра macOS", "macOS color picker"))
            }.disabled(!model.draft.usesColor).opacity(model.draft.usesColor ? 1 : 0.4)
    }
    private var hexRow: some View {
            HStack {
                rowLabel("")
                TextField("#RRGGBB", text: $hexInput, onCommit: {
                    invalidHex = !model.draft.setHex(hexInput)
                }).font(.system(size: 12, design: .monospaced)).frame(width: 100)
                    .textFieldStyle(RoundedBorderTextFieldStyle()).disabled(!model.draft.usesColor)
                    .accessibilityLabel(L("Цвет HEX; Enter для подтверждения", "HEX color; press Enter to confirm"))
                if invalidHex { Text(L("Введите #RRGGBB", "Enter #RRGGBB")).font(.caption).foregroundColor(.orange) }
                Spacer()
                Toggle(L("Разноцветный", "Multicolor"), isOn: $model.draft.colourful).toggleStyle(SwitchToggleStyle())
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
                .overlay(Circle().stroke(selected ? AppTheme.cyan : .clear, lineWidth: 1))
        }.buttonStyle(PlainButtonStyle()).help(preset.localizedName).accessibilityLabel(preset.localizedName)
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .medium)).frame(width: 70, alignment: .leading)
    }
    private func effectButton(_ title: String, id: UInt8, symbol: String) -> some View {
        Button { model.draft.mode = id } label: {
            Label(title, systemImage: symbol).font(.system(size: 12)).frame(maxWidth: .infinity)
                .padding(.vertical, 10).background(model.draft.mode == id ? AppTheme.cyan.opacity(0.09) : Color.white.opacity(0.03))
                .cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(model.draft.mode == id ? AppTheme.cyan : Color.white.opacity(0.15)))
        }.buttonStyle(PlainButtonStyle())
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, denominator: Int) -> some View {
        HStack(spacing: 14) {
            rowLabel(title)
            Slider(value: value, in: range, step: 1).accessibilityLabel(title)
            Text("\(Int(value.wrappedValue)) / \(denominator)").font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppTheme.muted).frame(width: 55)
        }
    }
    /// Строка закреплена вне ScrollView и остаётся у нижней границы окна.
    /// Полные сообщения доступны в подсказках и VoiceOver при сокращении текста.
    private var status: some View {
        let deviceMessage = model.hasChanges && !model.busy && !model.error && model.connected ?
            L("Есть неприменённые изменения", "Unapplied changes") : model.message
        return HStack(spacing: 12) {
            Label(L("Запись во все 3 профиля", "Writes all 3 profiles"), systemImage: "square.3.stack.3d")
                .frame(width: 155, alignment: .leading)
                .help(L("Настройки выбранного набора записываются во все три аппаратных профиля клавиатуры", "The selected settings are written to all three hardware profiles on the keyboard"))
            HStack(spacing: 5) {
                Image(systemName: model.error ? "exclamationmark.circle" : model.busy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    .foregroundColor(model.error ? .orange : AppTheme.muted)
                Text(model.profileError ?? deviceMessage)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .help(model.profileError ?? deviceMessage).accessibilityLabel(model.profileError ?? deviceMessage)
            Text(updater.message).frame(width: 185, alignment: .trailing)
                .help(updater.message).accessibilityLabel(updater.message)
        }
        .font(.system(size: 10)).foregroundColor(AppTheme.muted).lineLimit(1)
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
            .frame(width: 142, height: 36)
            .background(primary && enabled ? AppTheme.cyan : Color.white.opacity(enabled ? 0.07 : 0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(primary && enabled ? 0 : 0.14)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Общий стиль гарантирует одинаковые 36 × 36 точек у языка и шестерёнки.
private struct HeaderControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.05))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15)))
    }
}
