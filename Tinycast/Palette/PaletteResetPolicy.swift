import Foundation

/// What a hide owes the screen it leaves behind. See docs/features/palette.md#screens.
enum PaletteReset: Sendable, Equatable {
    /// Honour the user's Pop to Root Search delay — what a hide with nothing to say means.
    case standard
    /// Reset now, whatever the delay says.
    case immediate
    /// Hold the screen until the next summon restores it.
    case suspended
}

/// The one place deciding whether a hide outranks the user's delay.
enum PaletteResetPolicy {
    /// A command closing its own window has finished, so the delay has no screen left to hold.
    static func resolve(_ request: PaletteReset, commandOwnsScreen: Bool) -> PaletteReset {
        request == .standard && commandOwnsScreen ? .immediate : request
    }
}
