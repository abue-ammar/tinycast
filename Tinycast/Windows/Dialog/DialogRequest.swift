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
    /// The one control a dialog may carry beyond its buttons; the caller reads the result back
    /// out of the state object it passed in.
    var accessory: DialogAccessory?
}

/// A dialog carries at most one control, so the cases are exclusive by construction.
enum DialogAccessory {
    case volume(VolumeState)
    case eventDraft(EventDraftState)

    /// Whether ←/→/↑/↓ belong to the control rather than to whatever has focus inside it.
    var claimsArrowKeys: Bool {
        if case .volume = self { return true }
        return false
    }
}
