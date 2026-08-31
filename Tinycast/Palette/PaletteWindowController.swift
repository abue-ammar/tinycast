import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?
    /// Our key window at summon time, so hiding hands focus back to Settings, not a stale app.
    private weak var previousOwnWindow: NSWindow?
    private var popToRootTimer: Timer?
    /// Resolved once per show; the top edge is the one that must not drift.
    private var anchor: CGPoint?
    /// Live only between mouse-down and mouse-up on a drag handle; nil means a move was ours.
    private var drag: DragSession?
    private let dropGuides = PaletteDropGuideController()

    /// What a drag in flight needs: where home is, and whether releasing now would land there.
    private struct DragSession {
        var home: CGPoint
        var screenFrame: CGRect
        var armed = false
        /// The guides wait for this, so a click that never moves the panel doesn't flash them.
        var moved = false
    }

    init(core: AppCore) {
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        Signposts.interval("PaletteWindowController.show") {
            // Summoned over one of our own windows: there is no external paste or focus target.
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier {
                previousApp = nil
                // Never the palette itself: a mode switch re-shows it while it already holds key.
                if let key = NSApp.keyWindow, key !== panel { previousOwnWindow = key }
            } else {
                previousApp = frontmost
                previousOwnWindow = nil
            }
            // Once per summon, and from `previousApp`, so the label names the paste target.
            core.palette.pasteTarget = PasteTarget(app: previousApp)
            let panel = ensurePanel()
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

    func hide(restoreFocus: Bool) {
        panel?.orderOut(nil)
        core.inputSourceSwitcher.endSession()
        core.calendarCoordinator.paletteDidHide()
        // Drop the anchor, so the next summon re-resolves for the screen in use then.
        anchor = nil
        // The guides must never outlive the panel they point at.
        drag = nil
        dropGuides.hide()
        // Drop the multi-MB preview bitmaps, so idle RAM returns near baseline.
        ImageThumbnail.purgePreviews()
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
        // Don't pop to root if an extension is waiting for OAuth authorization in the browser.
        guard !core.extensions.isAuthorizing else { return }
        popToRootTimer?.invalidate()
        let timeout = core.settings.popToRootTimeout
        guard timeout != .immediately else {
            popToRoot()
            return
        }
        popToRootTimer = Timer.scheduledTimer(withTimeInterval: timeout.interval, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.core.extensions.isAuthorizing else { return }
                self.popToRootTimer = nil
                self.popToRoot()
            }
        }
    }

    /// The screen only: a conversation is not a typed query, and `Opens To` decides its lifetime.
    private func popToRoot() {
        core.palette.prepare(mode: .launcher)
    }

    /// True while a hidden palette still holds pre-close state; consuming cancels the reset.
    func consumePreservedState() -> Bool {
        guard let timer = popToRootTimer else { return false }
        timer.invalidate()
        popToRootTimer = nil
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

    /// Not for one of our own dialogs: hiding would tear down a command mid-`confirmAlert`.
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, !core.isShowingDialog else { return }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    /// Re-bump a turn later: on the first show a synchronous bump lands before `onChange`.
    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            core.palette.focusToken = UUID()
            // A re-summon leaves first responder where it was, so neither of these gets an event.
            panel?.trackComposition()
            if let context = panel?.fieldEditorContext {
                core.inputSourceSwitcher.applySession(to: context)
            }
        }
    }

    /// A drag re-anchors the session, so the next resize grows from where the user left it.
    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        let moved = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        anchor = moved
        guard drag != nil else { return }
        trackDrag(to: moved)
    }

    // MARK: - Dragging

    /// A drag handle took the mouse down. Nothing shows yet — the guides wait for a real move.
    func beginDrag() {
        guard let screen = panel?.screen ?? targetScreen() else { return }
        drag = DragSession(home: defaultAnchor(on: screen), screenFrame: screen.frame)
    }

    /// Release: snap home and forget the stored position, or remember where it was dropped.
    func endDrag() {
        let session = drag
        // Cleared before the snap, so `positionPanel`'s own move isn't read as more dragging.
        drag = nil
        dropGuides.hide()
        guard let panel, let session, session.moved else { return }
        guard session.armed else {
            core.settings.palettePosition = anchor
            return
        }
        anchor = session.home
        positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed)
        core.settings.palettePosition = nil
    }

    /// Keep the guides on the panel's screen, armed only while a release would snap it home.
    private func trackDrag(to moved: CGPoint) {
        guard var session = drag else { return }
        if let screen = panel?.screen, screen.frame != session.screenFrame {
            session.screenFrame = screen.frame
            session.home = defaultAnchor(on: screen)
        }
        session.armed = PalettePlacement.isSnapping(
            moved, to: session.home, within: Theme.Size.paletteSnapDistance)
        if session.moved {
            dropGuides.move(home: session.home, screenFrame: session.screenFrame)
            dropGuides.setArmed(session.armed)
        } else {
            session.moved = true
            dropGuides.show(
                home: session.home, screenFrame: session.screenFrame, armed: session.armed)
        }
        drag = session
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
        // Backspace in an empty search backs out of a sub-screen to a fresh root.
        panel.onBareBackspace = { [weak self] in
            guard let core = self?.core, core.palette.mode != .launcher, core.palette.query.isEmpty
            else { return false }
            // The argument form steps back through the answers first, one key per field.
            if core.palette.mode == .quicklinkArguments,
                let previous = core.quicklinkArguments.retreat()
            {
                core.palette.query = previous
                core.palette.selection = 0
                return true
            }
            if core.palette.mode == .customCommandArguments,
                let previous = core.customCommandArguments.retreat()
            {
                core.palette.query = previous
                core.palette.selection = 0
                return true
            }
            if core.palette.mode == .aiHistory {
                core.palette.prepare(mode: .ai)
                return true
            }
            if core.palette.mode == .ai, core.aiChatCoordinator.removeLastAttachment() {
                return true
            }
            core.palette.prepare(mode: .launcher)
            return true
        }
        // Handled at the panel: the field editor or a missing main menu eats these first.
        panel.onCommandShortcut = { [weak self] event in
            guard let self, !event.isARepeat,
                event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            else { return false }
            if self.core.palette.mode == .launcher || self.core.palette.mode == .clipboard,
                let index = FavoriteSlots.index(forKeyCode: event.keyCode)
            {
                self.core.palette.noteFavoriteSlot(index)
                return true
            }
            // Escape has no character, so it matches by key code.
            if Int(event.keyCode) == kVK_Escape {
                self.core.palette.prepare(mode: .launcher)
                return true
            }
            // Through the ASCII-capable layout: an IME must not move ⌘W off its physical key.
            guard
                let character = ASCIIKeyboardLayout.character(for: event)?.lowercased()
                    ?? event.charactersIgnoringModifiers?.lowercased()
            else { return false }
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
            case "v":
                return self.core.palette.mode == .ai && self.core.aiChatCoordinator.attachPastedImage()
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

    /// Size to height and place against the session anchor, so the list grows downward.
    private func positionPanel(_ panel: NSPanel, collapsed: Bool) {
        guard let anchor = resolveAnchor() else { return }
        let height = collapsed ? Theme.Size.compactHeight : Theme.Size.panelHeight
        let frame = NSRect(
            x: anchor.x, y: anchor.y - height, width: Theme.Size.panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    /// The display to anchor to; never `NSScreen.main`, which follows the focused window.
    private func targetScreen() -> NSScreen? {
        core.settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary
    }

    /// Cached until hide, so both placements read one `visibleFrame`; a drag outranks the setting.
    private func resolveAnchor() -> CGPoint? {
        if let anchor { return anchor }
        let resolved = restoredAnchor() ?? targetScreen().map(defaultAnchor(on:))
        anchor = resolved
        return resolved
    }

    /// Where the last drag left it, unless no display still shows enough of the bar to grab.
    private func restoredAnchor() -> CGPoint? {
        guard let stored = core.settings.palettePosition else { return nil }
        return PalettePlacement.restored(
            stored,
            graspable: CGSize(width: Theme.Size.panelWidth, height: Theme.Size.compactHeight),
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            minimumVisible: Theme.Size.paletteMinimumVisible)
    }

    /// The untouched placement on one display; the summon path and the drop guides share it.
    private func defaultAnchor(on screen: NSScreen) -> CGPoint {
        PalettePlacement.defaultAnchor(
            in: screen.visibleFrame, width: Theme.Size.panelWidth,
            topMarginFraction: Theme.Size.paletteTopMarginFraction)
    }
}
