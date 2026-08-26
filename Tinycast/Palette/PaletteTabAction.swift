import Foundation

/// Where Tab goes next. Launcher, chat and clipboard are the three surfaces a reader opens directly,
/// so Tab rings those; every other mode is a sub-screen, which Tab leaves for the launcher.
enum PaletteTabAction: Equatable {
    /// The typed text rides along, because both ends narrow their own list by the same query.
    case carryQuery(PaletteMode)
    /// A fresh screen: chat's field holds a half-written message, which is nobody else's search.
    case freshScreen(PaletteMode)

    static func resolve(mode: PaletteMode, aiEnabled: Bool) -> Self {
        switch mode {
        // Turned off, chat is not a stop on the ring, which leaves the launcher ↔ clipboard flip.
        case .launcher: return aiEnabled ? .freshScreen(.ai) : .carryQuery(.clipboard)
        case .ai: return .freshScreen(.clipboard)
        case .clipboard: return .carryQuery(.launcher)
        default: return .carryQuery(.launcher)
        }
    }
}
