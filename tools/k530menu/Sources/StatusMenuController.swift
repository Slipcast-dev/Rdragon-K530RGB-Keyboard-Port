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
        menu.addItem(item("Открыть K530 Lighting", #selector(open)))
        menu.addItem(item("Закрыть окно", #selector(close)))
        menu.addItem(.separator())
        let profiles = NSMenu(); profiles.autoenablesItems = false
        for (index, profile) in model.profiles.enumerated() {
            let entry = item(profile.name, #selector(selectProfile(_:)))
            entry.tag = index; entry.state = profile.id == model.selectedProfileID ? .on : .off
            entry.isEnabled = !model.busy && !updater.isBusy
            profiles.addItem(entry)
        }
        let profileItem = NSMenuItem(title: "Профили", action: nil, keyEquivalent: "")
        profileItem.submenu = profiles; menu.addItem(profileItem)
        let apply = item("Применить выбранный профиль", #selector(applyProfile))
        apply.isEnabled = model.connected && !model.busy && !updater.isBusy
        menu.addItem(apply)
        let enabled = model.connected && !model.busy && !updater.isBusy
        let effects = NSMenu(); effects.autoenablesItems = false
        for mode in modes {
            let entry = item(mode.name, #selector(selectMode(_:)))
            entry.tag = Int(mode.id); entry.state = mode.id == model.draft.mode ? .on : .off
            entry.isEnabled = enabled; effects.addItem(entry)
        }
        let effectItem = NSMenuItem(title: "Эффект — применить", action: nil, keyEquivalent: "")
        effectItem.submenu = effects; menu.addItem(effectItem)
        let brightness = NSMenu(); brightness.autoenablesItems = false
        for (level, title) in brightnessLevels {
            let entry = item(title, #selector(selectBrightness(_:)))
            entry.tag = level; entry.state = Int(model.draft.brightness) == level ? .on : .off
            entry.isEnabled = enabled; brightness.addItem(entry)
        }
        let brightnessItem = NSMenuItem(title: "Яркость — применить", action: nil, keyEquivalent: "")
        brightnessItem.submenu = brightness; menu.addItem(brightnessItem)
        menu.addItem(.separator())
        let read = item("Перечитать устройство", #selector(refresh))
        read.isEnabled = !model.busy && !updater.isBusy; menu.addItem(read)
        let updates = item("Проверить обновления…", #selector(checkUpdates))
        updates.isEnabled = !model.busy && !updater.isBusy; menu.addItem(updates)
        let restart = item("Перезапустить", #selector(restart))
        restart.isEnabled = !model.busy && !updater.isBusy; menu.addItem(restart)
        menu.addItem(.separator())
        let quit = item("Завершить K530 Lighting", #selector(terminate))
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
        model.draft.mode = mode; model.apply()
    }
    @objc private func selectBrightness(_ sender: NSMenuItem) {
        guard (0...4).contains(sender.tag) else { return }
        model.draft.brightness = Double(sender.tag); model.apply()
    }
}
