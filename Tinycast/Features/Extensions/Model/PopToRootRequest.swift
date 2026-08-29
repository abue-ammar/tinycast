import Foundation

/// `PopToRootType` as an extension asks for it: what a close does to the palette's pending reset.
enum PopToRootRequest: String, Sendable, Equatable {
    /// Honour the user's Pop to Root Search delay — what a close with no option means.
    case standard = "default"
    /// Reset now, whatever the delay says; the command is torn down with the screen.
    case immediate
    /// Hold the screen indefinitely, so the next summon lands back where the command was.
    case suspended

    init(raw: String?) {
        self = PopToRootRequest(rawValue: raw ?? "") ?? .standard
    }
}
