import Foundation

/// A screen to return to, held with enough state that going back looks like never having left.
struct PaletteFrame: Equatable {
    let mode: PaletteMode
    let query: String
    let selection: Int
    let clipboardFilter: ClipboardFilter
    let fileSearchFilter: FileSearchFilter
    let emojiCategoryFilter: EmojiCategoryFilter
    let emojiGridColumnsOverride: EmojiGridColumns?
}

@MainActor
@Observable
final class PaletteState {
    var mode: PaletteMode = .launcher { didSet { restoredSelection = nil } }
    /// The screens below `mode`, innermost last: a summon starts a new one, navigating pushes on.
    private(set) var backStack: [PaletteFrame] = []
    /// The bottom screen came from its own shortcut, so Escape there closes rather than backs out.
    private(set) var isOpenedByHotkey = false
    var query: String = "" {
        didSet {
            restoredSelection = nil
            // An emptied root search falls back to the compact bar, however it was expanded.
            if query.isEmpty { forceExpanded = false }
        }
    }
    @ObservationIgnored private(set) var restoredSelection: Int?
    var selection: Int = 0
    /// True while an IME holds marked text, which leaves `query` empty. The panel publishes it.
    var isComposing = false
    var clipboardFilter: ClipboardFilter = .all {
        didSet { if oldValue != clipboardFilter { restoredSelection = nil } }
    }
    var fileSearchFilter: FileSearchFilter = .all
    var emojiCategoryFilter: EmojiCategoryFilter = .all
    /// Nil means the configured default; zoom only overrides it for this picker session.
    var emojiGridColumnsOverride: EmojiGridColumns?
    /// Ordering out leaves the SwiftUI tree mounted, so a media preview needs this to stop playing.
    private(set) var isVisible = false
    /// Changes every time the palette is shown so the search field can re-focus.
    var focusToken = UUID()
    /// Bumped when a screen opens fresh, so its list lands again even when nothing else changed.
    var resetToken = UUID()
    /// Bumped when an action reorders the list, so the highlight scrolls back into view.
    var followToken = UUID()
    /// Bumped when an action rewrites the query, so the field lands with the caret after it.
    private(set) var queryRewriteToken = UUID()
    /// AppKit binds ⌘. to `cancelOperation:`, so the field editor eats it before `onKeyPress`.
    private(set) var pinChordToken = UUID()
    /// Bumped when AppKit resolves ⌘1…⌘0 to a slot index from the physical number row.
    private(set) var favoriteSlotToken = UUID()
    private(set) var favoriteSlotIndex: Int?
    /// Bumped for ⌘0 / ⌘+ / ⌘-, which the panel claims before the field editor can.
    private(set) var emojiGridZoomToken = UUID()
    private(set) var emojiGridZoom: EmojiGridZoom?
    var forceExpanded = false
    /// The paste target, mirrored on every show; `prepare` resets the screen, not this.
    var pasteTarget: PasteTarget?
    /// Values typed into a row's inline argument fields, keyed by `argumentKey`.
    var commandArguments: [String: String] = [:]
    /// Set when the palette opens to fill one row's fields; the header focuses the first empty one.
    var pendingArgumentEntryID: String?
    /// The row a shortcut opened root search onto, listed alone while the query is its name.
    var argumentEntryID: String?
    /// True once ⌘ has been *held*, which numbers the favorite rows. The panel is the only writer.
    private(set) var commandHeld = false
    /// A chord is a tap, so the numbering waits out the tap before it claims the trailing labels.
    @ObservationIgnored private var commandHoldTask: Task<Void, Never>?
    /// Set by a chord: the numbering stays hidden until ⌘ is let go.
    @ObservationIgnored private var commandChorded = false
    /// True while a form field owns the keyboard, so the palette's own text keys stay out of it.
    private(set) var isEditingField = false
    /// True while a control inside a screen has a list open, which owns the arrows and ↵ whole.
    private(set) var isControlListOpen = false
    /// Bumped when a press lands outside an open control list, which is how the list learns of it.
    private(set) var controlListDismissToken = UUID()
    /// True only once the pointer has moved of its own accord; untracked, so it never re-renders.
    @ObservationIgnored private(set) var hoverHighlightArmed = false
    /// Bumped when the highlight drops, so a lit row clears even though the pointer never left it.
    private(set) var hoverDisarmToken = UUID()
    /// Where the pointer stood when the list last moved on its own; movement is measured from here.
    @ObservationIgnored private var hoverAnchor: CGPoint = .zero
    /// A containment test, because hit-testing a rebuilding hierarchy misses the field.
    @ObservationIgnored var searchFieldFrame: CGRect = .zero
    /// True while a palette menu is open. See docs/features/palette.md#menu-open-input-freeze.
    @ObservationIgnored var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    var menuQuery = ""
    /// Fired when `menuOpen` flips, so the panel can hide the caret without a focus swap.
    @ObservationIgnored var onMenuOpenChanged: ((Bool) -> Void)?
    /// A fresh presentation resets a long popover to the row it opens with.
    private(set) var menuPresentationToken = UUID()

    func noteVisible(_ visible: Bool) {
        isVisible = visible
    }

    var canGoBack: Bool { !backStack.isEmpty }

    /// Escape closes this screen outright: its shortcut opened it and nothing was pushed since.
    var isHotkeyRoot: Bool { isOpenedByHotkey && backStack.isEmpty }

    func prepare(mode: PaletteMode) {
        start(mode, openedByHotkey: false)
    }

    /// A fresh stack for a screen its own shortcut opened, whatever was on screen before.
    func prepareFromHotkey(mode: PaletteMode) {
        start(mode, openedByHotkey: true)
    }

    /// Swap the screen in place, leaving whatever it was opened over still behind it.
    func replace(mode: PaletteMode) {
        openScreen(mode)
        resetToken = UUID()
    }

    func push(mode: PaletteMode) {
        if !self.mode.isNativeEditor { backStack.append(currentFrame) }
        replace(mode: mode)
    }

    /// The screen underneath, as it was left; false when this one is the bottom.
    func pop() -> Bool {
        guard let frame = backStack.popLast() else { return false }
        // Leaving an editor lands back on the row that was being edited.
        let keepsSelection = mode.isNativeEditor
        restore(frame)
        restoredSelection = keepsSelection ? frame.selection : nil
        // Not `resetToken`: landing the list again would throw away the selection restored here.
        followToken = UUID()
        return true
    }

    /// One step back, onto root search once nothing is left: it sits under every screen.
    func goBack() {
        guard !pop(), mode != .launcher else { return }
        prepare(mode: .launcher)
    }

    /// Root search alone, with the text it held before the screens above it were opened.
    func popToRootKeepingSearch() {
        let search = mode == .launcher ? currentFrame : backStack.first { $0.mode == .launcher }
        prepare(mode: .launcher)
        if let search { restore(search) }
    }

    /// Empties root search wherever it sits: on screen, or under the screens stacked over it.
    func clearRootSearch() {
        if mode == .launcher {
            query = ""
            selection = 0
        } else if backStack.first?.mode == .launcher {
            backStack[0] = Self.freshFrame(.launcher)
        }
    }

    /// Tab's step deeper into the ring: the screen crossed from is the step back, query and all.
    func pushCarryingQuery(mode: PaletteMode) {
        backStack.append(currentFrame)
        self.mode = mode
        resetFilters()
    }

    /// The search field is one line, so pasted line breaks become spaces; true when it rewrote.
    func collapseQueryLineBreaks() -> Bool {
        guard query.contains(where: \.isNewline) else { return false }
        query = query.split(whereSeparator: \.isNewline).joined(separator: " ")
        return true
    }

    /// Tab closing the ring on the launcher, which is its root: nothing is left behind it.
    func resetNavigation() {
        backStack.removeAll()
        isOpenedByHotkey = false
    }

    private func start(_ mode: PaletteMode, openedByHotkey: Bool) {
        backStack.removeAll()
        isOpenedByHotkey = openedByHotkey
        replace(mode: mode)
    }

    private var currentFrame: PaletteFrame {
        PaletteFrame(
            mode: mode, query: query, selection: selection, clipboardFilter: clipboardFilter,
            fileSearchFilter: fileSearchFilter, emojiCategoryFilter: emojiCategoryFilter,
            emojiGridColumnsOverride: emojiGridColumnsOverride)
    }

    private static func freshFrame(_ mode: PaletteMode) -> PaletteFrame {
        PaletteFrame(
            mode: mode, query: "", selection: 0, clipboardFilter: .all, fileSearchFilter: .all,
            emojiCategoryFilter: .all, emojiGridColumnsOverride: nil)
    }

    private func restore(_ frame: PaletteFrame) {
        openScreen(frame.mode)
        query = frame.query
        selection = frame.selection
        clipboardFilter = frame.clipboardFilter
        fileSearchFilter = frame.fileSearchFilter
        emojiCategoryFilter = frame.emojiCategoryFilter
        emojiGridColumnsOverride = frame.emojiGridColumnsOverride
    }

    private func openScreen(_ mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        isComposing = false
        isEditingField = false
        isControlListOpen = false
        commandArguments = [:]
        pendingArgumentEntryID = nil
        argumentEntryID = nil
        resetFilters()
        forceExpanded = false
        dropHoverHighlight()
        menuOpen = false
        menuQuery = ""
        focusToken = UUID()
    }

    private func resetFilters() {
        clipboardFilter = .all
        fileSearchFilter = .all
        emojiCategoryFilter = .all
        emojiGridColumnsOverride = nil
    }

    /// Long enough that ⌘↵ or ⌘K never flashes the numbering, short enough to feel like a reveal.
    private static let commandHoldDelay = Duration.milliseconds(400)

    /// U+0001 can't appear in an entry id or an argument name, so the halves stay unambiguous.
    nonisolated static func argumentKey(_ entryID: String, _ name: String) -> String {
        entryID + "\u{1}" + name
    }

    func notePinChord() {
        pinChordToken = UUID()
    }

    func noteMenuPresentation() {
        menuPresentationToken = UUID()
    }

    func rewriteQuery(_ text: String) {
        query = text
        queryRewriteToken = UUID()
    }

    func preserveSelection() {
        restoredSelection = selection
    }

    func noteFavoriteSlot(_ index: Int) {
        favoriteSlotIndex = index
        favoriteSlotToken = UUID()
    }

    func noteEmojiGridZoom(_ zoom: EmojiGridZoom) {
        emojiGridZoom = zoom
        emojiGridZoomToken = UUID()
    }

    func noteCommandHeld(_ held: Bool) {
        commandHoldTask?.cancel()
        commandHoldTask = nil
        guard held else {
            commandHeld = false
            commandChorded = false
            return
        }
        guard !commandHeld, !commandChorded else { return }
        commandHoldTask = Task { [weak self] in
            try? await Task.sleep(for: Self.commandHoldDelay)
            guard !Task.isCancelled else { return }
            self?.commandHeld = true
        }
    }

    /// A chord's own work, such as Settings starting up, can outlast the hold delay.
    func noteCommandChord() {
        commandHoldTask?.cancel()
        commandHoldTask = nil
        commandChorded = true
        commandHeld = false
    }

    func noteEditingField(_ editing: Bool) {
        guard editing != isEditingField else { return }
        isEditingField = editing
    }

    /// Set by a control whose own list is up; the palette leaves every navigation key to it.
    func noteControlListOpen(_ open: Bool) {
        guard open != isControlListOpen else { return }
        isControlListOpen = open
    }

    func dismissControlList() {
        guard isControlListOpen else { return }
        controlListDismissToken = UUID()
    }

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
