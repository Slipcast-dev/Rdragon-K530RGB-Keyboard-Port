import AppKit

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

