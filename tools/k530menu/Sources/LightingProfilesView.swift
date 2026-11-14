import SwiftUI

/// Локальная библиотека наборов. «Сохранить» пишет JSON, «Применить» в основном
/// окне меняет клавиатуру. Несохранённые черновики не теряются при выборе набора.
struct LightingProfilesView: View {
    @ObservedObject var model: LightingController
    @ObservedObject var updater: AppUpdater
    @State private var name = ""
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Профили подсветки").font(.system(size: 16, weight: .semibold))
            Text("Выберите набор, сохраните изменения и нажмите «Применить» в основном окне.")
                .font(.system(size: 11)).foregroundColor(.secondary)
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
                                .background(profile.id == model.selectedProfileID ? Color(red: 0, green: 0.9, blue: 1).opacity(0.12) : Color.clear)
                                .cornerRadius(6)
                        }.buttonStyle(PlainButtonStyle())
                    }
                }
            }.frame(height: min(180, CGFloat(model.profiles.count) * 38))
            TextField("Название профиля", text: $name).textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Сохранить настройки профиля") { model.saveProfile(name: name) }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            HStack {
                Button("Создать", action: model.createProfile).disabled(model.profiles.count >= 100)
                Spacer()
                Button("Удалить…") { confirmingDelete = true }.disabled(model.profiles.count <= 1)
            }
            if let error = model.profileError {
                Text(error).font(.system(size: 11)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(18).frame(width: 320).colorScheme(.dark)
            .disabled(model.busy || updater.isBusy)
            .onAppear { name = model.selectedProfile?.name ?? "" }
            .onChange(of: model.selectedProfileID) { _ in name = model.selectedProfile?.name ?? "" }
            .alert(isPresented: $confirmingDelete) {
                Alert(title: Text("Удалить профиль «\(model.selectedProfile?.name ?? "")»?"),
                      message: Text("Сохранённый набор и его черновик будут удалены. Настройки клавиатуры останутся прежними."),
                      primaryButton: .destructive(Text("Удалить"), action: model.deleteProfile),
                      secondaryButton: .cancel(Text("Отмена")))
            }
    }
}
