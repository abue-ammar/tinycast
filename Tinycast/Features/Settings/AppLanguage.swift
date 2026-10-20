import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case japanese = "ja"
    case korean = "ko"
    case portuguese = "pt"
    case russian = "ru"
    case chineseSimplified = "zh-Hans"

    var id: String { rawValue }

    /// Each language names itself, so someone who picked the wrong one can still find their own.
    var title: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .french: "Français"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .portuguese: "Português"
        case .russian: "Русский"
        case .chineseSimplified: "简体中文"
        }
    }

    /// Reads a stored list, including a regional tag such as `de-DE` that System Settings writes.
    init(storedPreferences: [String]?, systemPreferences: [String] = []) {
        let preferences = storedPreferences ?? Array(systemPreferences.prefix(1))
        guard !preferences.isEmpty else {
            self = .english
            return
        }
        let match = Bundle.preferredLocalizations(
            from: Self.allCases.map(\.rawValue), forPreferences: preferences)
        self = match.first.flatMap(Self.init(rawValue:)) ?? .english
    }
}
