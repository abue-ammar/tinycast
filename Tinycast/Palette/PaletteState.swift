import Foundation

/// Palette state shared between the panel's SwiftUI tree and the coordinator.
@MainActor
@Observable
final class PaletteState {
    var mode: PaletteMode = .launcher
    var query: String = ""
    var selection: Int = 0
    /// True while an IME holds marked text, which leaves `query` empty. The panel publishes it.
    var isComposing = false
    /// The clipboard screen's type filter, reset with the rest of the screen state on each summon.
    var clipboardFilter: ClipboardFilter = .all
    /// Changes every time the palette is shown so the search field can re-focus.
    var focusToken = UUID()
    /// Bumped only by `prepare`, so lists snap to the top even when nothing else changed.
    var resetToken = UUID()
    /// Bumped when an action reorders the list, so the highlight scrolls back into view.
    var followToken = UUID()
    /// AppKit binds ⌘. to `cancelOperation:`, so the field editor eats it before `onKeyPress`.
    private(set) var pinChordToken = UUID()
    /// Bumped when AppKit resolves ⌘1…⌘0 to a slot index from the physical number row.
    private(set) var favoriteSlotToken = UUID()
    /// The last slot index from `noteFavoriteSlot`, consumed by the SwiftUI layer.
    private(set) var favoriteSlotIndex: Int?
    /// Set by the compact bar's overflow to expand without a query; cleared by `prepare`.
    var forceExpanded = false
    /// The paste target, mirrored on every show; `prepare` resets the screen, not this.
    var pasteTarget: PasteTarget?
    /// Values typed into an extension's inline argument fields, keyed by `argumentKey`.
    var commandArguments: [String: String] = [:]
    /// True while ⌘ is held, which numbers the favorite rows. The panel is the only writer.
    private(set) var commandHeld = false
    /// True only once the pointer has moved of its own accord; untracked, so it never re-renders.
    @ObservationIgnored private(set) var hoverHighlightArmed = false
    /// Bumped when the highlight drops, so a lit row clears even though the pointer never left it.
    private(set) var hoverDisarmToken = UUID()
    /// Where the pointer stood when the list last moved on its own; movement is measured from here.
    @ObservationIgnored private var hoverAnchor: CGPoint = .zero
    /// A containment test, because hit-testing a rebuilding hierarchy misses the field.
    @ObservationIgnored var searchFieldFrame: CGRect = .zero
    /// True while a footer menu is open. See docs/features/palette.md#menu-open-input-freeze.
    @ObservationIgnored var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    /// Fired when `menuOpen` flips, so the panel can hide the caret without a focus swap.
    @ObservationIgnored var onMenuOpenChanged: ((Bool) -> Void)?

    func prepare(mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        isComposing = false
        commandArguments = [:]
        clipboardFilter = .all
        forceExpanded = false
        dropHoverHighlight()
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
    }

    /// U+0001 can't appear in an entry id or an argument name, so the halves stay unambiguous.
    nonisolated static func argumentKey(_ entryID: String, _ name: String) -> String {
        entryID + "\u{1}" + name
    }

    func notePinChord() {
        pinChordToken = UUID()
    }

    func noteFavoriteSlot(_ index: Int) {
        favoriteSlotIndex = index
        favoriteSlotToken = UUID()
    }

    func noteCommandHeld(_ held: Bool) {
        guard held != commandHeld else { return }
        commandHeld = held
    }

    /// The pointer moved, which re-lights the highlight once it has cleared the arming slop.
    func notePointerMoved(to location: CGPoint) {
        guard !hoverHighlightArmed, HoverArming.isDeliberate(location, from: hoverAnchor) else {
            return
        }
        hoverHighlightArmed = true
    }

    /// Movement is measured from where the pointer stands now: drift is not a new choice.
    func disarmHoverHighlight(pointerAt location: CGPoint) {
        hoverAnchor = location
        dropHoverHighlight()
    }

    private func dropHoverHighlight() {
        guard hoverHighlightArmed else { return }
        hoverHighlightArmed = false
        hoverDisarmToken = UUID()
    }
}
