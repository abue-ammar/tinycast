import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System", bundle: .appLanguage)
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    static func selection(in defaults: UserDefaults, domain: String) -> Self {
        guard
            let languages = defaults.persistentDomain(forName: domain)?[
                AppSettingsKey.language.rawValue] as? [String],
            !languages.isEmpty
        else { return .system }
        let preferred = Bundle.preferredLocalizations(
            from: [english.rawValue, simplifiedChinese.rawValue], forPreferences: languages)
        return preferred.first.flatMap(Self.init(rawValue:)) ?? .system
    }

    func save(to defaults: UserDefaults) {
        if self == .system {
            defaults.removeObject(forKey: AppSettingsKey.language.rawValue)
        } else {
            defaults.set([rawValue], forKey: AppSettingsKey.language.rawValue)
        }
    }
}
