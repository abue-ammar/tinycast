import Foundation

/// Tab rings the three surfaces a reader opens directly; a sub-screen exits to the launcher.
enum PaletteTabAction: Equatable {
    /// The typed text rides along, because both ends narrow their own list by the same query.
    case carryQuery(PaletteMode)
    /// A fresh screen: chat's field holds a half-written message, which is nobody else's search.
    case freshScreen(PaletteMode)
    /// The typed text is the question, so chat opens on the answer rather than an empty composer.
    case ask

    static func resolve(mode: PaletteMode, aiEnabled: Bool) -> Self {
        switch mode {
        // Turned off, chat is not a stop on the ring, which leaves the launcher ↔ clipboard flip.
        case .launcher: return aiEnabled ? .ask : .carryQuery(.clipboard)
        case .ai: return .freshScreen(.clipboard)
        case .clipboard: return .carryQuery(.launcher)
        default: return .carryQuery(.launcher)
        }
    }
}
