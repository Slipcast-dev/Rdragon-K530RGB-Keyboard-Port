import Foundation

/// Только локальные сценарии: не вызываем refresh/apply и не открываем HID.
@main
struct LightingControllerProfileTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("K530ControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profiles.json")
        let store = LightingProfileStore(url: url)
        let controller = LightingController(profileStore: store)
        precondition(controller.profiles.count == 3 && controller.profileError == nil)
        let first = controller.selectedProfileID
        let second = controller.profiles[1].id
        controller.draft.red = 255; controller.draft.green = 0
        let redSettings = controller.draft
        controller.saveProfile(name: "Работа")
        precondition(controller.selectedProfile?.name == "Работа")
        precondition(!controller.hasUnsavedProfileChanges)
        controller.selectProfile(second)
        controller.draft.mode = 6; controller.draft.blue = 0
        controller.saveProfile(name: "Вечер")
        let eveningSettings = controller.draft
        controller.selectProfile(first)
        precondition(controller.draft == redSettings)
        controller.draft.brightness = 1
        let firstUnsaved = controller.draft
        precondition(controller.hasUnsavedProfileChanges)
        controller.selectProfile(second)
        precondition(controller.draft == eveningSettings)
        controller.draft.speed = 5
        let secondUnsaved = controller.draft
        controller.selectProfile(first)
        precondition(controller.draft == firstUnsaved)
        controller.selectProfile(second)
        precondition(controller.draft == secondUnsaved)
        // Перезапуск восстанавливает выбранный набор, но не несохранённый черновик.
        let restarted = LightingController(profileStore: store)
        precondition(restarted.selectedProfileID == second)
        precondition(restarted.draft == eveningSettings)
        restarted.selectProfile(first)
        precondition(restarted.draft == redSettings)
        // Создание явно сохраняет копию текущего черновика в отдельном наборе.
        controller.createProfile()
        precondition(controller.profiles.count == 4)
        precondition(controller.selectedProfile?.settings == secondUnsaved)
        let newID = controller.selectedProfileID
        let afterCreate = LightingController(profileStore: store)
        precondition(afterCreate.selectedProfileID == newID)
        precondition(afterCreate.draft == secondUnsaved)
        controller.draft.mode = 13
        controller.saveProfile(name: "")
        precondition(controller.profileError != nil)
        precondition(controller.selectedProfile?.settings == secondUnsaved)
        controller.saveProfile(name: "Игры")
        precondition(controller.profileError == nil)
        while controller.profiles.count > 1 { controller.deleteProfile() }
        let finalID = controller.selectedProfileID
        controller.deleteProfile()
        precondition(controller.profiles.count == 1 && controller.selectedProfileID == finalID)
        let persisted = try store.load()
        precondition(persisted?.profiles.count == 1 && persisted?.selectedID == finalID)
        // При повреждённой библиотеке ни сохранение, ни выбор не уничтожают файл.
        let corrupted = Data("damaged profiles".utf8)
        try corrupted.write(to: url)
        let damagedController = LightingController(profileStore: store)
        precondition(damagedController.profileError != nil)
        damagedController.saveProfile(name: "Замена")
        damagedController.createProfile()
        damagedController.selectProfile(damagedController.profiles[1].id)
        damagedController.deleteProfile()
        let preserved = try Data(contentsOf: url)
        precondition(preserved == corrupted)
        precondition(damagedController.profileError != nil)
        print("LightingController profiles: independent saves, draft switching, restart, create/delete, corruption passed")
    }
}
