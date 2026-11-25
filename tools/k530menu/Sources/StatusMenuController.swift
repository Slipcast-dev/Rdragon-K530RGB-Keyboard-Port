import AppKit

/// Контекстное меню создаётся перед показом, чтобы галочки и доступность команд
/// отражали текущее состояние. Левая кнопка продолжает открывать окно.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: LightingController
    private let updater: AppUpdater
    var openWindow: () -> Void = {}
    var closeWindow: () -> Void = {}
    var didClose: () -> Void = {}

    init(model: LightingController, updater: AppUpdater) {
        self.model = model; self.updater = updater
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        menu.addItem(item(L("Открыть K530 Lighting", "Open K530 Lighting"), #selector(open)))
        menu.addItem(item(L("Закрыть окно", "Close Window"), #selector(close)))
        menu.addItem(.separator())
        let profiles = NSMenu(); profiles.autoenablesItems = false
        for (index, profile) in model.profiles.enumerated() {
            let entry = item(profile.name, #selector(selectProfile(_:)))
            entry.tag = index; entry.state = profile.id == model.selectedProfileID ? .on : .off
            entry.isEnabled = !model.busy && !updater.isBusy
            profiles.addItem(entry)
        }
        let profileItem = NSMenuItem(title: L("Профили", "Profiles"), action: nil, keyEquivalent: "")
        profileItem.submenu = profiles; menu.addItem(profileItem)
        let apply = item(L("Применить выбранный профиль", "Apply Selected Profile"), #selector(applyProfile))
        apply.isEnabled = model.connected && !model.busy && !updater.isBusy
        menu.addItem(apply)
        let enabled = model.connected && !model.busy && !updater.isBusy
        let effects = NSMenu(); effects.autoenablesItems = false
        for mode in modes {
            let entry = item(localizedModeName(mode.id), #selector(selectMode(_:)))
            entry.tag = Int(mode.id); entry.state = mode.id == model.draft.mode ? .on : .off
            entry.isEnabled = enabled; effects.addItem(entry)
        }
        let effectItem = NSMenuItem(title: L("Эффект — применить", "Effect — Apply"), action: nil, keyEquivalent: "")
        effectItem.submenu = effects; menu.addItem(effectItem)
        let brightness = NSMenu(); brightness.autoenablesItems = false
        for level in brightnessLevels {
            let entry = item(localizedBrightnessName(level), #selector(selectBrightness(_:)))
            entry.tag = level; entry.state = Int(model.draft.brightness) == level ? .on : .off
            entry.isEnabled = enabled; brightness.addItem(entry)
        }
        let brightnessItem = NSMenuItem(title: L("Яркость — применить", "Brightness — Apply"), action: nil, keyEquivalent: "")
        brightnessItem.submenu = brightness; menu.addItem(brightnessItem)
        menu.addItem(.separator())
        let read = item(L("Перечитать устройство", "Read Device Settings"), #selector(refresh))
        read.isEnabled = !model.busy && !updater.isBusy; menu.addItem(read)
        let updates = item(updater.availableVersion.map { L("Установить версию \($0)…", "Install Version \($0)…") }
                           ?? L("Проверить обновления…", "Check for Updates…"), #selector(checkUpdates))
        updates.isEnabled = !model.busy && !updater.isBusy; menu.addItem(updates)
        let restart = item(L("Перезапустить", "Restart"), #selector(restart))
        restart.isEnabled = !model.busy && !updater.isBusy; menu.addItem(restart)
        menu.addItem(.separator())
        let quit = item(L("Завершить K530 Lighting", "Quit K530 Lighting"), #selector(terminate))
        quit.isEnabled = !model.busy && !updater.isBusy; quit.keyEquivalent = "q"
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self; return item
    }
    func menuDidClose(_ menu: NSMenu) { didClose() }
    @objc private func open() { openWindow() }
    @objc private func close() { closeWindow() }
    @objc private func refresh() { model.refresh() }
    @objc private func checkUpdates() { model.checkUpdates() }
    @objc private func restart() { model.restartApplication() }
    @objc private func terminate() { NSApp.terminate(nil) }
    @objc private func applyProfile() { model.apply() }
    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard model.profiles.indices.contains(sender.tag) else { return }
        model.selectProfile(model.profiles[sender.tag].id); openWindow()
    }
    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = UInt8(exactly: sender.tag), knownModes.contains(mode) else { return }
        model.applyQuick { $0.mode = mode }
    }
    @objc private func selectBrightness(_ sender: NSMenuItem) {
        guard (0...4).contains(sender.tag) else { return }
        let level = Double(sender.tag)
        model.applyQuick { $0.brightness = level }
    }
}
