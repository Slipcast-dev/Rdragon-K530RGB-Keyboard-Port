import AppKit
import IOKit
import IOKit.hid

// K530Lighting — приложение в строке меню для переключения режима подсветки Redragon K530 (Sonix 0C45:5004).
// Протокол восстановлен статическим анализом штатной программы (research/protocol-findings.md).
// Приложение меняет только поля профилей +0 (режим), +1 (яркость), +4 (флаг «Colourful») и +5…+7 (цвет RGB).
// Перед первой записью читает профили и сохраняет резервную копию. Назначение +1 как яркости 0–4 выведено из
// значения на реальной клавиатуре (максимум = 4) и из кода штатной программы; на других ревизиях не проверено.

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

/// Окно справки: показывает FAQ.md из ресурсов приложения. Поддерживается небольшая часть Markdown:
/// заголовки «#» и «##», списки, блоки кода, `код`, **жирный** и ссылки [текст](адрес).
final class FaqWindowController: NSWindowController {
    static let shared = FaqWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "K530 Lighting — справка"
        window.center()
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.hasVerticalScroller = true; scroll.autoresizingMask = [.width, .height]
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 18, height: 16)
        text.textStorage?.setAttributedString(FaqWindowController.render())
        scroll.documentView = text
        window.contentView = scroll
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() { NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil) }

    private static func inline(_ line: String) -> String {
        var t = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        // [текст](адрес) -> текст
        while let a = t.range(of: "["), let b = t.range(of: "](", range: a.upperBound..<t.endIndex),
              let c = t.range(of: ")", range: b.upperBound..<t.endIndex) {
            t.replaceSubrange(a.lowerBound..<c.upperBound, with: String(t[a.upperBound..<b.lowerBound]))
        }
        return t
    }

    private static func render() -> NSAttributedString {
        guard let url = Bundle.main.url(forResource: "FAQ", withExtension: "md"),
              let md = try? String(contentsOf: url, encoding: .utf8) else {
            return NSAttributedString(string: "Файл справки не найден в ресурсах приложения.")
        }
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13), mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var inCode = false
        func add(_ s: String, _ font: NSFont, before: CGFloat = 0, after: CGFloat = 4) {
            let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = before; p.paragraphSpacing = after
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: font, .paragraphStyle: p, .foregroundColor: NSColor.labelColor]))
        }
        for raw in md.components(separatedBy: "\n") {
            if raw.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { add("  " + raw, mono); continue }
            if raw.hasPrefix("## ") { add(inline(String(raw.dropFirst(3))), .boldSystemFont(ofSize: 14), before: 14, after: 4) }
            else if raw.hasPrefix("# ") { add(inline(String(raw.dropFirst(2))), .boldSystemFont(ofSize: 20), after: 6) }
            else if raw.hasPrefix("- ") { add("•  " + inline(String(raw.dropFirst(2))), body) }
            else if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            else { add(inline(raw), body) }
        }
        return out
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var session: K530Session?
    private var current: [UInt8]?          // первые 8 байт профиля, если у трёх профилей они совпадают
    private var initial: [[UInt8]]?        // профили на момент первого чтения (для отката)
    private var status = "Клавиатура не найдена"
    private var backedUp = false
    private var colorTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        if let b = statusItem.button {
            // Силуэт дракона из Resources (шаблонная иконка: цвет подстраивается под тему); запасной вариант — системный значок.
            if let url = Bundle.main.url(forResource: "StatusIcon@2x", withExtension: "png"), let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 18, height: 18); img.isTemplate = true; b.image = img
            } else {
                b.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "K530 подсветка")
            }
            b.image?.accessibilityDescription = "K530 подсветка"
            if b.image == nil { b.title = "K530" }
        }
        menu.delegate = self
        statusItem.menu = menu
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            let me = Unmanaged<AppDelegate>.fromOpaque(ctx!).takeUnretainedValue()
            me.session = nil; me.current = nil
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        // Доступ «Мониторинг ввода»: при ad-hoc подписи он привязан к конкретной сборке, после пересборки его нужно выдать заново.
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        refresh()
        rebuildMenu()
    }

    // MARK: Обмен с клавиатурой

    private func vendorInterface() -> IOHIDDevice? {
        let set = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        return set.first { (IOHIDDeviceGetProperty($0, "MaxOutputReportSize" as CFString) as? Int) == 64 }
    }

    @discardableResult
    private func refresh() -> [[UInt8]]? {
        if session == nil, let d = vendorInterface() { session = K530Session(device: d) }
        guard let s = session else {
            current = nil
            status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
                ? "Клавиатура не найдена" : "Нет доступа «Мониторинг ввода» — удалите приложение из списка и добавьте снова"
            return nil
        }
        guard let p = s.readProfiles() else {
            status = "Нет ответа (нужен доступ «Мониторинг ввода»?)"; current = nil; return nil
        }
        if initial == nil { initial = p }
        let heads = p.map { Array($0.prefix(8)) }
        current = heads.allSatisfy({ $0 == heads[0] }) ? heads[0] : nil
        if let c = current {
            let mode = modes.first { $0.id == c[0] }.map { "\($0.id). \($0.name)" } ?? "режим \(c[0])"
            let color = c[4] != 0 ? "разноцветный" : String(format: "#%02X%02X%02X", c[5], c[6], c[7])
            let speed = c[2] <= 4 ? String(5 - Int(c[2])) : "?"
            status = "\(mode) · яркость \(c[1]) · скорость \(speed) · \(color)"
        } else {
            status = "Профили различаются: \(p.map { $0[0] })"
        }
        return p
    }

    private func backup(_ profiles: [[UInt8]]) {
        guard !backedUp,
              let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("K530Lighting") else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = profiles.enumerated().map { "профиль \($0.offset + 1): " + $0.element.map { String(format: "%02x", $0) }.joined(separator: " ") }
            .joined(separator: "\n")
        let file = dir.appendingPathComponent("backup-\(Int(Date().timeIntervalSince1970)).txt")
        if (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil { backedUp = true }
    }

    /// Общий путь записи: чтение → проверка → копия → запись полей → чтение для проверки.
    /// Проверка: у каждого поля после записи должно быть записанное значение во всех профилях.
    private func apply(_ fields: [(offset: Int, data: [UInt8])]) {
        guard let s = session ?? { refresh(); return session }() else { return }
        guard let before = refresh() else { return }
        guard before.allSatisfy({ knownModes.contains($0[0]) && $0[1] <= 4 }) else {
            alert("Запись отменена", "Профили содержат необычные значения (режим/яркость): \(before.map { Array($0.prefix(3)) }). Чтобы не повредить настройки, приложение ничего не меняет.")
            return
        }
        backup(before)
        guard s.writeFields(fields) else { status = "Ошибка записи"; rebuildMenu(); return }
        guard let after = refresh() else { return }
        let ok = after.allSatisfy { p in fields.allSatisfy { Array(p[$0.offset..<($0.offset + $0.data.count)]) == $0.data } }
        if !ok { alert("Не подтверждено", "Клавиатура вернула другие значения после записи. Можно откатить к состоянию при запуске через меню.") }
        rebuildMenu()
    }

    // MARK: Действия меню

    @objc private func selectMode(_ item: NSMenuItem) {
        let m = UInt8(item.tag); guard knownModes.contains(m) else { return }
        apply([(0, [m])])
    }
    @objc private func selectBrightness(_ item: NSMenuItem) {
        apply([(1, [UInt8(item.tag)])])
    }
    @objc private func selectSpeed(_ item: NSMenuItem) {
        apply([(2, [UInt8(item.tag)])])
    }
    @objc private func selectPreset(_ item: NSMenuItem) {
        let c = presets[item.tag].rgb
        apply([(4, [0]), (5, [c.0, c.1, c.2])])
    }
    @objc private func selectColourful() { apply([(4, [1])]) }

    @objc private func pickCustomColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self); panel.setAction(#selector(customColorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    /// Запись с задержкой 0,5 с после последнего изменения, чтобы не слать пакеты при перетаскивании.
    @objc private func customColorChanged(_ panel: NSColorPanel) {
        colorTimer?.invalidate()
        colorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let c = panel.color.usingColorSpace(.sRGB) else { return }
            func b(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
            self?.apply([(4, [0]), (5, [b(c.redComponent), b(c.greenComponent), b(c.blueComponent)])])
        }
    }

    @objc private func showFaq() { FaqWindowController.shared.show() }

    @objc private func rollback() {
        guard let init0 = initial, let s = session else { return }
        // Возвращаются первые 8 байт каждого профиля (режим, яркость, цвет), остальное не трогаем.
        guard s.exchange(.begin) != nil else { return }
        var ok = true
        for (i, p) in init0.enumerated() {
            if s.exchange(.write, length: 8, address: UInt16(i * K530Protocol.profileSize), data: Array(p.prefix(8))) == nil { ok = false; break }
        }
        _ = s.exchange(.end)
        refresh(); rebuildMenu()
        if !ok { alert("Откат не выполнен", "Не удалось записать исходные значения.") }
    }

    // MARK: Автозапуск (LaunchAgent в ~/Library/LaunchAgents, работает на macOS 11 и новее)

    private var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/dev.slipcast.k530lighting.plist")
    }
    private var autostartEnabled: Bool {
        guard let d = try? Data(contentsOf: agentURL),
              let plist = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String] else { return false }
        return args.first == Bundle.main.executablePath
    }
    @objc private func toggleAutostart() {
        if autostartEnabled { try? FileManager.default.removeItem(at: agentURL); rebuildMenu(); return }
        guard let exe = Bundle.main.executablePath else { return }
        let plist: [String: Any] = ["Label": "dev.slipcast.k530lighting", "ProgramArguments": [exe],
                                    "RunAtLoad": true, "ProcessType": "Interactive"]
        do {
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let d = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try d.write(to: agentURL)
        } catch { alert("Автозапуск не включён", "\(error.localizedDescription)") }
        rebuildMenu()
    }

    // MARK: Меню

    func menuWillOpen(_ menu: NSMenu) { refresh(); rebuildMenu() }

    private func swatch(_ rgb: (UInt8, UInt8, UInt8)) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            NSColor(srgbRed: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1).setFill()
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            path.fill(); NSColor.separatorColor.setStroke(); path.stroke()
            return true
        }
    }

    private func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let m = NSMenu(title: title); build(m)
        item.submenu = m; item.isEnabled = session != nil
        return item
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let head = NSMenuItem(title: status, action: nil, keyEquivalent: ""); head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        menu.addItem(submenu("Режим") { m in
            for md in modes {
                let it = NSMenuItem(title: "\(md.id). \(md.name)" + (colorModes.contains(md.id) ? "  · цвет" : ""), action: #selector(selectMode(_:)), keyEquivalent: "")
                it.target = self; it.tag = Int(md.id); it.state = current?[0] == md.id ? .on : .off
                m.addItem(it)
            }
            m.addItem(.separator())
            let note = NSMenuItem(title: "«· цвет» — режим использует выбранный цвет", action: nil, keyEquivalent: ""); note.isEnabled = false
            m.addItem(note)
        })
        menu.addItem(submenu("Яркость") { m in
            for (v, name) in brightnessLevels {
                let it = NSMenuItem(title: name, action: #selector(selectBrightness(_:)), keyEquivalent: "")
                it.target = self; it.tag = v; it.state = current?[1] == UInt8(v) ? .on : .off
                m.addItem(it)
            }
        })
        menu.addItem(submenu("Скорость") { m in
            for (v, name) in speedLevels {
                let it = NSMenuItem(title: name, action: #selector(selectSpeed(_:)), keyEquivalent: "")
                it.target = self; it.tag = v; it.state = current?[2] == UInt8(v) ? .on : .off
                m.addItem(it)
            }
        })
        menu.addItem(submenu("Цвет") { m in
            if let c = current, !colorModes.contains(c[0]) {
                let warn = NSMenuItem(title: "В текущем режиме цвет не используется", action: nil, keyEquivalent: ""); warn.isEnabled = false
                m.addItem(warn); m.addItem(.separator())
            }
            let col = NSMenuItem(title: "Разноцветный (Colourful)", action: #selector(selectColourful), keyEquivalent: "")
            col.target = self; col.state = (current?[4] ?? 0) != 0 ? .on : .off
            m.addItem(col); m.addItem(.separator())
            for (i, p) in presets.enumerated() {
                let it = NSMenuItem(title: p.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
                it.target = self; it.tag = i; it.image = swatch(p.rgb)
                if let c = current, c[4] == 0, (c[5], c[6], c[7]) == p.rgb { it.state = .on }
                m.addItem(it)
            }
            m.addItem(.separator())
            let other = NSMenuItem(title: "Другой цвет…", action: #selector(pickCustomColor), keyEquivalent: "")
            other.target = self; m.addItem(other)
        })
        menu.addItem(.separator())
        let auto = NSMenuItem(title: "Запускать при входе в систему", action: #selector(toggleAutostart), keyEquivalent: "")
        auto.target = self; auto.state = autostartEnabled ? .on : .off
        menu.addItem(auto)
        let rb = NSMenuItem(title: "Вернуть состояние на момент запуска", action: #selector(rollback), keyEquivalent: "")
        rb.target = self; rb.isEnabled = initial != nil && session != nil
        menu.addItem(rb)
        let help = NSMenuItem(title: "Справка (FAQ)…", action: #selector(showFaq), keyEquivalent: "")
        help.target = self; menu.addItem(help)
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
