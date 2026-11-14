import AppKit
import SwiftUI
import IOKit.hid

/// AppKit управляет жизненным циклом и строкой меню; содержимое окна — SwiftUI.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = LightingController()
    private let updater = AppUpdater()
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var statusMenu: StatusMenuController!
    private let discovery = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.restartApplication = { [weak self] in self?.restartApplication() }
        model.showHelp = { FaqWindowController.shared.show() }
        model.checkUpdates = { [weak self] in self?.updater.checkManually() }
        model.updaterBusy = { [weak self] in self?.updater.isBusy ?? false }
        updater.canStartUpdate = { [weak self] in !(self?.model.busy ?? true) }
        updater.onPresentationRequested = { [weak self] in self?.showPanel() }
        configureApplicationMenu()
        model.loadAutostart()
        let content = LightingView(model: model, updater: updater)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "K530 Lighting"
        // Собственный текст в поддерживаемом titlebar accessory не зависит
        // от цвета системного заголовка или пользовательской темы macOS.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        let titlebar = NSTitlebarAccessoryViewController()
        titlebar.layoutAttribute = .right
        let title = NSTextField(labelWithString: "K530 Lighting")
        title.textColor = .white; title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.alignment = .center
        title.frame = NSRect(x: 0, y: 2, width: 160, height: 20)
        let titleContainer = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        titleContainer.addSubview(title); titlebar.view = titleContainer
        window.addTitlebarAccessoryViewController(titlebar)
        window.backgroundColor = NSColor(srgbRed: 0.055, green: 0.067, blue: 0.086, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: content)
        window.contentView = hosting
        let size = hosting.fittingSize
        window.setContentSize(NSSize(width: 740, height: max(620, size.height)))
        window.center()
        statusMenu = StatusMenuController(model: model, updater: updater)
        statusMenu.openWindow = { [weak self] in self?.showPanel() }
        statusMenu.closeWindow = { [weak self] in self?.closePanel() }
        statusMenu.didClose = { [weak self] in self?.statusItem.menu = nil }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let url = Bundle.main.url(forResource: "StatusIcon@2x", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 18, height: 18); image.isTemplate = true; button.image = image
            } else { button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "K530 Lighting") }
            button.target = self; button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "K530 Lighting — управление подсветкой"
        }
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        IOHIDManagerSetDeviceMatching(discovery, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(discovery, { context, _, _, _ in
            guard let context = context else { return }
            let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            owner.model.refresh()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(discovery, { context, _, _, _ in
            guard let context = context else { return }
            let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            owner.model.deviceRemoved()
        }, context)
        IOHIDManagerScheduleWithRunLoop(discovery, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(discovery, IOOptionBits(kIOHIDOptionsTypeNone))
        showPanel()
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        updater.start()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()
        let root = NSMenuItem(); mainMenu.addItem(root)
        let appMenu = NSMenu(title: "K530 Lighting")
        let close = NSMenuItem(title: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.target = nil; appMenu.addItem(close)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Завершить K530 Lighting", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp; appMenu.addItem(quit)
        root.submenu = appMenu
        let editRoot = NSMenuItem(); mainMenu.addItem(editRoot)
        let edit = NSMenu(title: "Правка")
        for (title, action, key) in [
            ("Вырезать", #selector(NSText.cut(_:)), "x"),
            ("Копировать", #selector(NSText.copy(_:)), "c"),
            ("Вставить", #selector(NSText.paste(_:)), "v"),
            ("Выбрать всё", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editRoot.submenu = edit; NSApp.mainMenu = mainMenu
    }

    @objc private func statusButtonClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = statusMenu.makeMenu()
            statusItem.button?.performClick(nil)
        } else { showPanel() }
    }

    @objc private func showPanel() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !model.connected { model.refresh() }
    }

    @objc private func closePanel() { window.performClose(nil) }

    /// Красная кнопка и «Закрыть окно» используют один жизненный цикл:
    /// окно закрыто — убираем Dock, продолжая обслуживать значок строки меню.
    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel(); return true
    }

    @objc private func becameActive() {
        if !model.connected { model.refresh() }
    }

    private func restartApplication() {
        guard !model.busy, !updater.isBusy else { return }
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", Bundle.main.bundlePath]
            process.terminationHandler = { process in
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 { NSApp.terminate(nil) }
                    else {
                        let alert = NSAlert(); alert.messageText = "Не удалось перезапустить приложение"
                        alert.informativeText = "Закройте приложение через меню и откройте снова."
                        alert.runModal()
                    }
                }
            }
            try process.run()
        } catch {
            let alert = NSAlert(); alert.messageText = "Не удалось перезапустить приложение"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }

    /// Не обрываем обмен или замену приложения командой завершения.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (model.busy || (updater.isBusy && !updater.readyToRelaunch)) ? .terminateCancel : .terminateNow
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
