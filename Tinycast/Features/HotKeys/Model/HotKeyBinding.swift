import Foundation

/// What an action is bound to. See docs/features/hotkeys.md.
enum HotKeyBinding: Hashable, Sendable, Codable {
    case combo(KeyShortcut)
    case doubleTap(DoubleTapModifier)
    case globe
    case doubleGlobe

    /// One string per keycap, so every display site renders all bindings through one path.
    @MainActor var keycaps: [String] {
        switch self {
        case .combo(let shortcut): shortcut.keycaps
        case .doubleTap(let modifier): modifier.keycaps
        case .globe: ["🌐︎"]
        case .doubleGlobe: ["🌐︎", "🌐︎"]
        }
    }

    var shortcut: KeyShortcut? {
        if case .combo(let shortcut) = self { return shortcut }
        return nil
    }

    var usesModifierTapMonitor: Bool {
        switch self {
        case .combo: false
        case .doubleTap, .globe, .doubleGlobe: true
        }
    }
}
