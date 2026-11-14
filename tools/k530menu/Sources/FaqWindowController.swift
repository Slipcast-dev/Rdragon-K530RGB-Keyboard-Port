import AppKit

/// Окно справки: показывает FAQ_RU.md или FAQ_EN.md из ресурсов приложения. Поддерживается небольшая часть Markdown:
/// заголовки «#» и «##», списки, блоки кода, `код`, **жирный** и ссылки [текст](адрес).
final class FaqWindowController: NSWindowController {
    static let shared = FaqWindowController()
    private var helpText: NSTextView?

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("K530 Lighting — справка", "K530 Lighting — Help")
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
        helpText = text
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
            name: .appLanguageDidChange, object: AppLocalization.shared)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        languageChanged()
        NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil)
    }

    /// Обновляем уже открытое окно, а не создаём второе при каждом переключении.
    @objc private func languageChanged() {
        window?.title = L("K530 Lighting — справка", "K530 Lighting — Help")
        helpText?.textStorage?.setAttributedString(Self.render())
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    static func resourceName(for language: AppLanguage) -> String {
        language == .russian ? "FAQ_RU" : "FAQ_EN"
    }

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
        let language = AppLocalization.shared.language
        let legacyURL = language == .russian ? Bundle.main.url(forResource: "FAQ", withExtension: "md") : nil
        guard let url = Bundle.main.url(forResource: resourceName(for: language), withExtension: "md") ?? legacyURL,
              let md = try? String(contentsOf: url, encoding: .utf8) else {
            return NSAttributedString(string: L("Файл справки не найден в ресурсах приложения.",
                                                "The help file was not found in the application resources."))
        }
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13), mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var inCode = false
        func add(_ s: String, _ font: NSFont, before: CGFloat = 0, after: CGFloat = 4) {
            let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = before; p.paragraphSpacing = after
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: font, .paragraphStyle: p, .foregroundColor: NSColor.labelColor]))
        }
        for (index, raw) in md.components(separatedBy: "\n").enumerated() {
            // Ссылки языковой навигации предназначены для GitHub; в приложении
            // язык выбирается кнопкой панели, поэтому здесь строку не показываем.
            if index < 3 && raw.contains("Русский") && raw.contains("English") { continue }
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

