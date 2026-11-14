import SwiftUI

/// Локальная библиотека наборов. «Сохранить» пишет JSON, «Применить» в основном
/// окне меняет клавиатуру. Несохранённые черновики не теряются при выборе набора.
struct LightingProfilesView: View {
    @ObservedObject var model: LightingController
    @ObservedObject var updater: AppUpdater
    @ObservedObject private var localization = AppLocalization.shared
    @State private var name = ""
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Профили подсветки", "Lighting profiles")).font(.system(size: 16, weight: .semibold))
            Text(L("Выберите набор, сохраните изменения и нажмите «Применить» в основном окне.", "Select a profile, save your changes, then click Apply in the main window."))
                .font(.system(size: 11)).foregroundColor(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.profiles) { profile in
                        Button { model.selectProfile(profile.id) } label: {
                            HStack {
                                Text(profile.name).lineLimit(1)
                                Spacer()
                                if profile.id == model.selectedProfileID { Image(systemName: "checkmark") }
                            }.padding(9).contentShape(Rectangle())
                                .background(profile.id == model.selectedProfileID ? AppTheme.cyan.opacity(0.10) : Color.clear)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(profile.id == model.selectedProfileID ? AppTheme.cyan.opacity(0.65) : Color.clear))
                        }.buttonStyle(PlainButtonStyle())
                    }
                }
            }.frame(height: min(180, CGFloat(model.profiles.count) * 38))
            Text(L("НАЗВАНИЕ", "NAME")).font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(AppTheme.muted)
            TextField(L("Название профиля", "Profile name"), text: $name)
                .textFieldStyle(PlainTextFieldStyle()).font(.system(size: 12)).padding(10)
                .background(Color.white.opacity(0.05)).cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15)))
            Button(L("Сохранить настройки профиля", "Save profile settings")) { model.saveProfile(name: name) }
                .buttonStyle(ProfileActionStyle(primary: true))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            HStack {
                Button(L("Создать", "Create"), action: model.createProfile)
                    .buttonStyle(ProfileActionStyle(primary: false)).disabled(model.profiles.count >= 100)
                Button(L("Удалить…", "Delete…")) { confirmingDelete = true }
                    .buttonStyle(ProfileActionStyle(primary: false, destructive: true)).disabled(model.profiles.count <= 1)
            }
            if let error = model.profileError {
                Text(error).font(.system(size: 11)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(18).frame(width: 320)
            .background(AppTheme.background).foregroundColor(.white).accentColor(AppTheme.cyan)
            // preferredColorScheme меняет и контейнер popover; одного colorScheme
            // для вложенного текста недостаточно при светлой теме системы.
            .preferredColorScheme(.dark)
            .disabled(model.busy || updater.isBusy)
            .onAppear { name = model.selectedProfile?.name ?? "" }
            .onChange(of: model.selectedProfileID) { _ in name = model.selectedProfile?.name ?? "" }
            .alert(isPresented: $confirmingDelete) {
                Alert(title: Text(L("Удалить профиль «\(model.selectedProfile?.name ?? "")»?", "Delete profile ‘\(model.selectedProfile?.name ?? "")’?")),
                      message: Text(L("Сохранённый набор и его черновик будут удалены. Настройки клавиатуры останутся прежними.", "The saved profile and its draft will be deleted. The keyboard settings will stay unchanged.")),
                      primaryButton: .destructive(Text(L("Удалить", "Delete")), action: model.deleteProfile),
                      secondaryButton: .cancel(Text(L("Отмена", "Cancel"))))
            }
    }
}

/// Собственные кнопки исключают светлые нативные подложки в тёмном popover.
private struct ProfileActionStyle: ButtonStyle {
    let primary: Bool
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold))
            .foregroundColor(!enabled ? Color.white.opacity(0.4) : primary ? .black : destructive ? .red : .white)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(primary && enabled ? AppTheme.cyan : Color.white.opacity(0.05))
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(primary && enabled ? 0 : 0.14)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
