import Foundation

@MainActor
enum TranslationSettingsFile {
    static func modelBinding(store: TranslationSettingsStore) -> SettingsFileBinding {
        SettingsFileBinding(
            .translationModel,
            read: {
                guard case .api(let connection, let model, let effort) = store.model else {
                    return .null
                }
                return .object([
                    "connection": .string(connection.uuidString), "model": .string(model),
                    "effort": effort.map(SettingsFileJSON.string) ?? .null
                ])
            },
            write: { value in
                if value == .null {
                    store.select(nil)
                    return []
                }
                guard let members = value.members, members.count == 3,
                    Set(members.map(\.key)) == ["connection", "model", "effort"],
                    let connection = value["connection"]?.string.flatMap(UUID.init(uuidString:)),
                    let model = value["model"]?.string,
                    !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    let effort = value["effort"], effort == .null || effort.string != nil
                else { return [.invalidValue(.translationModel)] }
                store.select(.api(connection: connection, model: model, effort: effort.string))
                return []
            })
    }
}
