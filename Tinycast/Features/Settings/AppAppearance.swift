import AppKit

/// Which appearance Tinycast renders in; an unset key reads as `.system`.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System", bundle: .appLanguage)
        case .light: String(localized: "Light", bundle: .appLanguage)
        case .dark: String(localized: "Dark", bundle: .appLanguage)
        }
    }

    /// `nil` hands the choice back to AppKit, which then follows macOS live and for free.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
