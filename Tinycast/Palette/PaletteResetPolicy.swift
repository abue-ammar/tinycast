import Foundation

/// What a hide owes the screen it leaves behind. See docs/features/palette.md#screens.
enum PaletteReset: Sendable, Equatable {
    /// Honour the user's Pop to Root Search delay — what a hide with nothing to say means.
    case standard
    /// Reset now, whatever the delay says.
    case immediate
    /// Hold the screen until the next summon restores it.
    case suspended

    /// `PopToRootType` as an extension spells it; an unrecognised string is never a capability.
    init(wire: String?) {
        switch wire {
        case "immediate": self = .immediate
        case "suspended": self = .suspended
        default: self = .standard
        }
    }
}

/// The one place deciding whether a hide outranks the user's delay.
enum PaletteResetPolicy {
    /// A command closing its own window has finished, so the delay has no screen left to hold.
    static func resolve(_ request: PaletteReset, commandOwnsScreen: Bool) -> PaletteReset {
        request == .standard && commandOwnsScreen ? .immediate : request
    }

    /// What a command's HUD may do to the palette, which is nothing unless the screen is its own.
    enum HUDEffect: Sendable, Equatable {
        case close
        case reset
        case none
    }

    /// A headless command finishing late must not close a palette the user summoned meanwhile.
    static func hudEffect(paletteVisible: Bool, commandOwnsScreen: Bool) -> HUDEffect {
        guard paletteVisible else { return .reset }
        return commandOwnsScreen ? .close : .none
    }
}
