import Foundation

/// What an action is bound to. See docs/features/hotkeys.md.
enum HotKeyBinding: Hashable, Sendable, Codable {
    case combo(KeyShortcut)
    case doubleTap(DoubleTapModifier)
    case modifier(ModifierKey)
    case doubleModifier(ModifierKey)
    case globe
    case doubleGlobe

    /// One string per keycap, so every display site renders all bindings through one path.
    @MainActor var keycaps: [String] {
        switch self {
        case .combo(let shortcut): shortcut.keycaps
        case .doubleTap(let modifier): modifier.keycaps
        case .modifier(let key): key.keycaps
        case .doubleModifier(let key): key.modifier?.keycaps ?? ["🌐︎", "🌐︎"]
        case .globe: ["🌐︎"]
        case .doubleGlobe: ["🌐︎", "🌐︎"]
        }
    }

    var recorderPrefix: String? {
        switch self {
        case .modifier(let key): key.side.map { String($0.prefix(1)) }
        default: nil
        }
    }

    @MainActor var recorderKeycaps: [String] {
        recorderPrefix == nil ? keycaps : Array(keycaps.dropFirst())
    }

    var shortcut: KeyShortcut? {
        if case .combo(let shortcut) = self { return shortcut }
        return nil
    }

    var usesModifierTapMonitor: Bool {
        switch self {
        case .combo: false
        case .doubleTap, .modifier, .doubleModifier, .globe, .doubleGlobe: true
        }
    }

    var holdKey: ModifierKey? {
        switch self {
        case .modifier(let key): key
        case .globe: .globe
        default: nil
        }
    }

    private var modifierKeys: Set<ModifierKey> {
        switch self {
        case .modifier(let key), .doubleModifier(let key): [key]
        case .globe, .doubleGlobe: [.globe]
        case .doubleTap(let modifier): Set(ModifierKey.allCases.filter { $0.modifier == modifier })
        case .combo: []
        }
    }

    func conflicts(with other: Self, holdsModifier: Bool = false) -> Bool {
        if self == other { return true }
        guard !modifierKeys.isDisjoint(with: other.modifierKeys) else { return false }
        if holdsModifier { return true }
        switch (self, other) {
        case (.doubleTap, .doubleModifier), (.doubleModifier, .doubleTap): return true
        case (.globe, .modifier), (.modifier, .globe): return true
        case (.doubleGlobe, .doubleModifier), (.doubleModifier, .doubleGlobe): return true
        default: return false
        }
    }
}
