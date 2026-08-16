import Foundation

/// One button; role decides its colour, severity living separately in `DialogTone`.
struct DialogAction {
    enum Role {
        case standard
        case destructive
        case cancel
    }

    let title: String
    var role: Role = .standard
}

/// How serious a dialog is; it tints the glyph but never picks one. See docs/ui.md.
enum DialogTone: Sendable {
    case neutral
    case success
    case danger
}

struct DialogRequest {
    let title: String
    var message: String?
    /// The subject's own glyph, resolved through `SymbolImage` so a bundled asset name works too.
    /// Nil where the title already names the subject and a glyph would only repeat it.
    let symbol: String?
    var tone: DialogTone = .neutral
    var actions: [DialogAction]
    /// The button ↵ fires, normally the primary action.
    var defaultIndex: Int
    /// Resolved when the dialog goes without a choice: Esc, or losing key status.
    var cancelIndex: Int
    /// Set only by the Set Volume prompt; the slider binds to it and the caller reads the result.
    var volume: VolumeState?
}
