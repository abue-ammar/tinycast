import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
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
        case .system: String(localized: "System")
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

    var preferences: [String]? { self == .system ? nil : [rawValue] }

    /// Reads a stored list, including a regional tag such as `de-DE` that System Settings writes.
    init(storedPreferences: [String]?) {
        guard let storedPreferences, !storedPreferences.isEmpty else {
            self = .system
            return
        }
        let shipped = Self.allCases.filter { $0 != .system }.map(\.rawValue)
        let match = Bundle.preferredLocalizations(from: shipped, forPreferences: storedPreferences)
        self = match.first.flatMap(Self.init(rawValue:)) ?? .english
    }

    func localization(available: [String], system: [String]) -> String? {
        Bundle.preferredLocalizations(from: available, forPreferences: preferences ?? system).first
    }
}
