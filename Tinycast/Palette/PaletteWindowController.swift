import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?
    /// Our key window at summon time, so hiding hands focus back to Settings, not a stale app.
    private(set) weak var previousOwnWindow: NSWindow?
    private var popToRootTimer: Timer?
    // Reopen beat the timeout, so select the preserved query.
    private var queryWasPreserved = false
    /// Set by a pop to root while hidden and spent by the next show: that screen is already fresh.
    private(set) var isPoppedToRoot = false
    /// Resolved once per show; the top edge is the one that must not drift.
    private var anchor: CGPoint?
    /// Live only between mouse-down and mouse-up on a drag handle; nil means a move was ours.
    private var drag: DragSession?
    private let dropGuides = PaletteDropGuideController()
    /// ⌘V: `Edit ▸ Paste` claims it before `sendEvent` whenever the board also carries text.
    private var pasteMonitor: Any?
    /// ⌘⎋: the window server claims it, so no keystroke is left for the responder chain to see.
    private lazy var commandEscapeTap = CommandEscapeTap { [weak self] in
        guard let self, self.panel?.isKeyWindow == true else { return false }
        self.core.palette.prepare(mode: .launcher)
        return true
    }

    /// The centre line and its height detents for a drag in flight.
    private struct DragSession {
        var home: CGPoint
        var screenFrame: CGRect
        var visibleFrame: CGRect
        var displayKey: String
        var snap: PalettePlacement.Snap
        var verticalEntryY: CGFloat?
        var lastRawAnchor: CGPoint
        var lastSampleTime: TimeInterval?
        var moved = false
    }

    init(core: AppCore) {
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Where the panel sits in screen coordinates, so an overlay drawn under it can avoid it.
    var visibleFrame: CGRect? { panel.flatMap { $0.isVisible ? $0.frame : nil } }

    /// The palette's own view, for AppKit UI that must be anchored to it rather than drawn.
    var anchorView: NSView? { panel?.isVisible == true ? panel?.contentView : nil }

    /// What the palette covered when it was summoned, for anything it expands into on dismissal.
    var previousTarget: InjectionTarget? {
        InjectionTarget.behindPalette(ownWindow: previousOwnWindow, app: previousApp)
    }

    func show() {
        Signposts.interval("PaletteWindowController.show") {
            isPoppedToRoot = false
            core.palette.focusToken = UUID()
            // Summoned over one of our own windows: there is no external paste or focus target.
            let frontmost = NSWorkspace.shared.frontmostApplication
            let ownPID = NSRunningApplication.current.processIdentifier
            previousApp = frontmost?.processIdentifier == ownPID ? nil : frontmost
            // Recorded even when another app is frontmost: our panels take key without activating.
            let key = NSApp.keyWindow
            // A mode switch re-shows the palette while it holds key; keep what it recorded then.
            if key !== panel { previousOwnWindow = key }
            // Once per summon, and from `previousApp`, so the label names the paste target.
            core.palette.pasteTarget = PasteTarget(app: previousApp)
            let panel = ensurePanel()
            // Undo a sink a modal left behind, unless one is still up.
            if NSApp.modalWindow == nil { panel.level = .palette }
            // Open disarmed: a pointer already over a row must not highlight it.
            core.palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
            // Re-resolve the anchor now, then hold it so resizes never move the window.
            anchor = nil
            // Size and place before ordering front, so a compact summon never flashes.
            positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed)
            // Flush first-mount layout off-screen, so the safe-area settle isn't visible.
            panel.contentView?.layoutSubtreeIfNeeded()
            core.inputSourceSwitcher.beginSession(
                preferredInputSourceID: core.settings.autoSwitchInputSourceID)
            // Events go stale while the palette is closed, and the countdown only ticks while up.
            core.calendarCoordinator.paletteDidShow()
            core.palette.noteVisible(true)
            core.clipboardStore.setTextSearchActive(true)
            // Only while we are on screen: a system-wide tap has no business outliving the window.
            commandEscapeTap.enable()
            // Non-activating, so summoning never raises our own aux windows behind it.
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            // A never-activated login item can drop the first key request, so re-assert.
            DispatchQueue.main.async { [weak panel] in
                guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    // Isolated so teardown may touch the main-actor monitor; the block is already weak.
    isolated deinit {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
    }

    /// The character a bare-⌘ chord names, through the ASCII layout so an IME cannot move it.
    private static func commandCharacter(from event: NSEvent) -> String? {
        guard !event.isARepeat,
            event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        else { return nil }
        return ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
    }

    /// Shift is allowed, since ⌘+ is a shifted = on most layouts; the base key decides.
    private static func emojiGridZoom(from event: NSEvent) -> EmojiGridZoom? {
        guard !event.isARepeat, event.modifierFlags.isDisjoint(with: [.option, .control]) else {
            return nil
        }
        switch ASCIIKeyboardLayout.character(for: event) {
        case "0": return .actualSize
        case "=", "+": return .zoomIn
        case "-": return .zoomOut
        default: return nil
        }
    }

    /// A local monitor sees the key before menu dispatch; returning nil swallows it.
    private func installPasteMonitor() {
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.panel?.isKeyWindow == true,
                Self.commandCharacter(from: event) == "v"
            else { return event }
            return self.attachPastedFile() ? nil : event
        }
    }

    /// Read once here: ⌘V is a keystroke path, and both routes want the same answer.
    private func attachPastedFile() -> Bool {
        let files = PasteboardFiles.urls(on: .general)
        switch core.palette.mode {
        case .ai: return core.quickAICoordinator.attachPastedFile(files: files)
        case .launcher: return core.quickAICoordinator.attachPastedFileFromLauncher(files: files)
        default: return false
        }
    }

    func hide(restoreFocus: Bool) {
        panel?.orderOut(nil)
        commandEscapeTap.disable()
        core.inputSourceSwitcher.endSession()
        core.calendarCoordinator.paletteDidHide()
        core.roomCoordinator.paletteDidHide()
        core.palette.noteVisible(false)
        core.clipboardStore.setTextSearchActive(false)
        // Drop the anchor, so the next summon re-resolves for the screen in use then.
        anchor = nil
        // The guides must never outlive the panel they point at.
        drag = nil
        dropGuides.hide()
        // Drop the multi-MB preview bitmaps, so idle RAM returns near baseline.
        ImageThumbnail.purgePreviews()
        FilePreviewThumbnail.purgePreviews()
        IconCache.purgeFitted()
        schedulePopToRoot()
        guard restoreFocus else { return }
        // Our own window first: it is still open, and activating another app would bury it.
        if let own = previousOwnWindow, own.isVisible {
            own.makeKeyAndOrderFront(nil)
        } else {
            previousApp?.activate()
        }
    }

    /// Pop to Root Search: reset now, or after the delay unless a reopen consumes it.
    private func schedulePopToRoot() {
        popToRootTimer?.invalidate()
        let timeout = core.settings.popToRootTimeout
        guard timeout != .immediately else {
            popToRoot()
            return
        }
        popToRootTimer = Timer.scheduledTimer(withTimeInterval: timeout.interval, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.popToRootTimer = nil
                self.popToRoot()
            }
        }
    }

    /// The screen only: a conversation is not a typed query, and `Opens To` decides its lifetime.
    private func popToRoot() {
        core.palette.prepare(mode: .launcher)
        isPoppedToRoot = true
    }

    /// Skip the Pop to Root Search delay, for a close that means to reset as well as hide.
    func popToRootNow() {
        popToRootTimer?.invalidate()
        popToRootTimer = nil
        popToRoot()
    }

    /// True while a hidden palette still holds pre-close state; consuming cancels the reset.
    func consumePreservedState() -> Bool {
        guard let timer = popToRootTimer else { return false }
        timer.invalidate()
        popToRootTimer = nil
        queryWasPreserved = true
        return true
    }

    /// Paste into the previous app while the palette stays frontmost.
    @discardableResult
    func pasteKeepingWindowOpen(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        Paster.pasteInPlace(item, store: store, into: previousApp)
    }

    /// String flavor of the above, for emoji/symbol pastes.
    func pasteStringKeepingWindowOpen(_ text: String) {
        Paster.pasteStringInPlace(text, into: previousApp)
    }

    // MARK: - NSWindowDelegate

    /// Not for a dialog or a modal: hiding tears down a running command.
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, !core.isShowingDialog else { return }
        if core.palette.menuOpen { return }
        // A file panel sets its own level under ours, so sink rather than dismiss.
        if NSApp.modalWindow != nil {
            panel?.level = .normal
            return
        }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        panel?.level = .palette
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // A re-summon leaves first responder where it was, so neither of these gets an event.
            panel?.trackComposition()
            if let context = panel?.fieldEditorContext {
                core.inputSourceSwitcher.applySession(to: context)
            }
            if queryWasPreserved {
                queryWasPreserved = false
                panel?.selectAllFieldEditorText()
            }
        }
    }

    /// A drag re-anchors the session, so the next resize grows from where the user left it.
    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        let moved = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        guard moved != anchor else { return }
        guard drag != nil else { anchor = moved; return }
        let snapped = trackDrag(to: moved)
        anchor = snapped
        if snapped != moved {
            panel.setFrameOrigin(CGPoint(x: snapped.x, y: snapped.y - panel.frame.height))
        }
    }

    // MARK: - Dragging

    /// A press on a drag handle passed the slop that makes it a drag; the guides follow the move.
    func beginDrag() {
        guard let panel, let screen = panel.screen ?? targetScreen() else { return }
        let home = defaultAnchor(on: screen)
        let current = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let candidate = PalettePlacement.snapped(
            current, home: home, visibleFrame: screen.visibleFrame,
            expandedHeight: metrics.size.panelHeight,
            within: Theme.Size.paletteSnapDistance, previous: nil, speed: 0)
        // Mere proximity must not latch a fast drag before its first move.
        let pixel = 1 / screen.backingScaleFactor
        let restingSnap = PalettePlacement.Snap(
            anchor: current,
            centeredX: candidate.centeredX && abs(candidate.anchor.x - current.x) <= pixel,
            height: abs(candidate.anchor.y - current.y) <= pixel ? candidate.height : nil)
        drag = DragSession(
            home: home, screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            displayKey: screen.displayKey, snap: restingSnap,
            lastRawAnchor: current, lastSampleTime: nil)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// The home detent restores the default; other drops remember their display-relative position.
    func endDrag() {
        let session = drag
        drag = nil
        dropGuides.hide()
        guard let session, session.moved, let anchor else { return }
        if session.snap.centeredX && session.snap.height == .home {
            core.settings.setPalettePosition(nil, on: session.displayKey, expandedCenter: false)
            return
        }
        core.settings.setPalettePosition(
            PalettePlacement.offset(of: anchor, on: session.visibleFrame), on: session.displayKey,
            expandedCenter: session.snap.centeredX && session.snap.height == .expandedCenter)
    }

    /// Snap live, with height detents available only on the centre line.
    private func trackDrag(to moved: CGPoint) -> CGPoint {
        guard var session = drag else { return moved }
        let now = ProcessInfo.processInfo.systemUptime
        let travel = hypot(moved.x - session.lastRawAnchor.x, moved.y - session.lastRawAnchor.y)
        let elapsed = session.lastSampleTime.map { now - $0 } ?? 1.0 / 60
        let speed = travel / max(elapsed, 0.001)
        session.lastRawAnchor = moved
        session.lastSampleTime = now
        if let screen = panel?.screen, screen.frame != session.screenFrame {
            session.screenFrame = screen.frame
            session.visibleFrame = screen.visibleFrame
            session.displayKey = screen.displayKey
            session.home = defaultAnchor(on: screen)
            session.snap = PalettePlacement.Snap(anchor: moved, centeredX: false, height: nil)
            session.verticalEntryY = nil
        }
        let snap = PalettePlacement.snapped(
            moved, home: session.home, visibleFrame: session.visibleFrame,
            expandedHeight: metrics.size.panelHeight, within: Theme.Size.paletteSnapDistance,
            previous: session.snap, speed: speed)
        let enteredVertical = snap.centeredX && !session.snap.centeredX
        let enteredHome = snap.height == .home && session.snap.height != .home
        if enteredVertical { session.verticalEntryY = moved.y }
        if let verticalEntryY = session.verticalEntryY,
            !snap.centeredX || abs(moved.y - verticalEntryY) > Theme.Size.dropGuideCombinedFlashTolerance
        {
            session.verticalEntryY = nil
        }
        if enteredVertical || (snap.height != nil && snap.height != session.snap.height) {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment, performanceTime: .drawCompleted)
        }
        if session.moved {
            dropGuides.move(
                home: session.home, screenFrame: session.screenFrame, dragged: snap.anchor)
        } else {
            dropGuides.show(
                home: session.home, width: metrics.size.panelWidth,
                screenFrame: session.screenFrame, dragged: snap.anchor)
        }
        if enteredHome {
            dropGuides.flash(session.verticalEntryY == nil ? .horizontal : .both)
            session.verticalEntryY = nil
        } else if enteredVertical {
            dropGuides.flash(.vertical)
        }
        session.snap = snap
        session.moved = true
        drag = session
        return snap.anchor
    }

    // MARK: - Private

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let root = RootPaletteView().paletteEnvironment(core)
        let panel = PalettePanel(rootView: root)
        panel.delegate = self
        panel.paletteState = core.palette
        // The switch is scoped to the palette's own editing context, never applied globally.
        panel.onFieldEditorFocused = { [weak self] context in
            self?.core.inputSourceSwitcher.applySession(to: context)
        }
        // Backspace takes Escape's back step but never closes: a root screen falls to the launcher.
        panel.onBareBackspace = { [weak self] in
            guard let core = self?.core, core.palette.query.isEmpty else { return false }
            // A form field owns the key: the text it deletes is the field's, not a query's.
            if core.palette.isEditingField { return false }
            if core.palette.mode == .extensionCommand {
                core.extensionCoordinator.exitExtensionScreen()
                return true
            }
            if core.palette.mode == .ai, core.quickAICoordinator.removeLastAttachment() {
                return true
            }
            if core.palette.pop() { return true }
            guard core.palette.mode != .launcher else { return false }
            core.palette.prepare(mode: .launcher)
            return true
        }
        installPasteMonitor()
        // Handled at the panel: a focused preview answers Escape before the palette's own handler.
        panel.onEscape = { [weak self] in
            guard let self else { return false }
            if core.palette.mode == .customCommandEditor, !core.palette.isComposing {
                core.customCommandCoordinator.cancelCustomCommandEditing()
                return true
            }
            if core.palette.mode == .eventEditor, !core.palette.isComposing {
                core.calendarCoordinator.cancelEventEditing()
                return true
            }
            if core.palette.mode == .quicklinkEditor, !core.palette.isComposing {
                core.quicklinkCoordinator.cancelQuicklinkEditing()
                return true
            }
            if core.palette.mode == .snippetEditor, !core.palette.isComposing {
                core.snippetCoordinator.cancelSnippetEditing()
                return true
            }
            guard core.palette.fileSearchQuickLook else { return false }
            core.palette.fileSearchQuickLook = false
            return true
        }
        // Handled at the panel: the field editor or a missing main menu eats these first.
        panel.onCommandShortcut = { [weak self] event in
            guard let self else { return false }
            if core.palette.mode.isNativeEditor,
                event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter,
                event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
                !core.palette.isComposing
            {
                switch core.palette.mode {
                case .quicklinkEditor:
                    core.quicklinkCoordinator.saveQuicklink()
                case .snippetEditor:
                    core.snippetCoordinator.requestSnippetSave()
                case .eventEditor:
                    core.calendarCoordinator.saveEvent()
                case .customCommandEditor:
                    core.customCommandCoordinator.saveCustomCommand()
                default: break
                }
                return true
            }
            if self.core.palette.mode == .emoji, let zoom = Self.emojiGridZoom(from: event) {
                self.core.palette.noteEmojiGridZoom(zoom)
                return true
            }
            guard Self.commandCharacter(from: event) != nil else { return false }
            if self.core.palette.mode == .launcher || self.core.palette.mode == .clipboard,
                let index = FavoriteSlots.index(forKeyCode: event.keyCode)
            {
                self.core.palette.noteFavoriteSlot(index)
                return true
            }
            guard let character = Self.commandCharacter(from: event) else { return false }
            switch character {
            case ",":
                self.core.settingsCoordinator.showSettings()
                return true
            // Pin. Swallowed on every screen, since ⌘. only ever means cancel to a search field.
            case ".":
                self.core.palette.notePinChord()
                return true
            case "w":
                self.core.paletteCoordinator.hidePalette()
                return true
            default:
                return false
            }
        }
        self.panel = panel
        return panel
    }

    /// Resize to the given state, top edge anchored; applied even while hidden.
    func applyCollapsed(_ collapsed: Bool) {
        guard let panel else { return }
        positionPanel(panel, collapsed: collapsed)
    }

    /// A new width invalidates the placement the cached anchor encoded, so re-resolve it.
    func applyInterfaceSize() {
        guard let panel else { return }
        anchor = nil
        positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed)
    }

    /// Size to height and place against the session anchor, so the list grows downward.
    private func positionPanel(_ panel: NSPanel, collapsed: Bool) {
        guard let anchor = resolveAnchor() else { return }
        let size = metrics.size
        let height = collapsed ? size.compactHeight : size.panelHeight
        let frame = NSRect(
            x: anchor.x, y: anchor.y - height, width: size.panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    /// The display to anchor to; never `NSScreen.main`, which follows the focused window.
    private func targetScreen() -> NSScreen? {
        core.settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary
    }

    /// Cached until hide, so both placements read one `visibleFrame`; a drag outranks the setting.
    private func resolveAnchor() -> CGPoint? {
        if let anchor { return anchor }
        let resolved = targetScreen().flatMap { restoredAnchor(on: $0) ?? defaultAnchor(on: $0) }
        anchor = resolved
        return resolved
    }

    /// This display's own corner, unless too little of the bar would stay grabbable.
    private func restoredAnchor(on screen: NSScreen) -> CGPoint? {
        guard let offset = core.settings.palettePosition(on: screen.displayKey) else { return nil }
        let stored = PalettePlacement.anchor(for: offset, on: screen.visibleFrame)
        let position =
            core.settings.paletteExpandedCenterDisplays.contains(screen.displayKey)
            ? CGPoint(
                x: defaultAnchor(on: screen).x,
                y: PalettePlacement.expandedCenterY(
                    in: screen.visibleFrame, expandedHeight: metrics.size.panelHeight))
            : stored
        return PalettePlacement.restored(
            position,
            graspable: CGSize(width: metrics.size.panelWidth, height: metrics.size.compactHeight),
            visibleFrame: screen.visibleFrame,
            minimumVisible: Theme.Size.paletteMinimumVisible)
    }

    /// The untouched placement on one display; the summon path and the drop guides share it.
    private func defaultAnchor(on screen: NSScreen) -> CGPoint {
        PalettePlacement.defaultAnchor(
            in: screen.visibleFrame, width: metrics.size.panelWidth,
            topMarginFraction: Theme.Size.paletteTopMarginFraction)
    }

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
}

extension NSScreen {
    /// Survives a replug; the display ID is a session-only fallback.
    fileprivate var displayKey: String {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let id = number?.uint32Value else { return "primary" }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid) as String?
        else { return String(id) }
        return string.lowercased()
    }
}
