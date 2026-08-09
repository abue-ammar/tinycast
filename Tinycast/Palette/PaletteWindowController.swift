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
    /// The session anchor, resolved once per show. See docs/features/palette.md#window-placement.
    private var anchor: (x: CGFloat, topEdgeY: CGFloat)?

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
            core.palette.hoverHighlightArmed = false
            // Re-resolve the anchor now, then hold it so resizes never move the window.
            anchor = nil
            // Size and place before ordering front, so a compact summon never flashes.
            positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed)
            // Flush first-mount layout off-screen, so the safe-area settle isn't visible.
            panel.contentView?.layoutSubtreeIfNeeded()
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
        // Drop the anchor, so the next summon re-resolves for the screen in use then.
        anchor = nil
        // Drop the multi-MB preview bitmaps, so idle RAM returns near baseline.
        ImageThumbnail.purgePreviews()
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
            core.palette.prepare(mode: .launcher)
            return
        }
        popToRootTimer = Timer.scheduledTimer(withTimeInterval: timeout.interval, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.popToRootTimer = nil
                self?.core.palette.prepare(mode: .launcher)
            }
        }
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

    /// Dismiss when the palette loses key status (click-away, ⌘-Tab, app switch).
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        hide(restoreFocus: false)
    }

    /// Re-bump a turn later: on the first show a synchronous bump lands before `onChange`.
    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.core.palette.focusToken = UUID()
        }
    }

    // MARK: - Private

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let root = RootPaletteView()
            .environment(core)
            .environment(core.settings)
            .environment(core.palette)
            .environment(core.appIndex)
            .environment(core.clipboardStore)
            .environment(core.favorites)
            .environment(core.visibility)
            .environment(core.calcHistory)
            .environment(core.currencyRates)
            .environment(core.emojiIndex)
            .environment(core.frequentEmoji)
            .environment(core.runningApps)
            .environment(core.hotKeys)
            .environment(core.uninstall)
            .environment(core.quicklinks)
            .environment(core.quicklinkArguments)
        let panel = PalettePanel(rootView: root)
        panel.delegate = self
        panel.paletteState = core.palette
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
            core.palette.prepare(mode: .launcher)
            return true
        }
        // Handled at the panel: the field editor or a missing main menu eats these first.
        panel.onCommandShortcut = { [weak self] event in
            guard let self, !event.isARepeat,
                event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            else { return false }
            // Escape has no character, so it matches by key code.
            if Int(event.keyCode) == kVK_Escape {
                self.core.palette.prepare(mode: .launcher)
                return true
            }
            // Character chords, not key codes: Dvorak transposes the two.
            guard let character = event.charactersIgnoringModifiers?.lowercased() else { return false }
            switch character {
            case ",":
                self.core.settingsCoordinator.showSettings()
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

    /// Size to height and place against the session anchor, so the list grows downward.
    private func positionPanel(_ panel: NSPanel, collapsed: Bool) {
        guard let anchor = resolveAnchor() else { return }
        let height = collapsed ? Theme.Size.compactHeight : Theme.Size.panelHeight
        let frame = NSRect(
            x: anchor.x, y: anchor.topEdgeY - height, width: Theme.Size.panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    /// The display to anchor to; `NSScreen.main` would give the menu-bar one instead.
    private func targetScreen() -> NSScreen? {
        guard core.settings.openOnCursorScreen else { return NSScreen.main }
        let mouse = NSEvent.mouseLocation
        // NSMouseInRect, not `contains`: the topmost row otherwise reads as the display above.
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// The session anchor, cached until hide so both placements read one `visibleFrame`.
    private func resolveAnchor() -> (x: CGFloat, topEdgeY: CGFloat)? {
        if let anchor { return anchor }
        guard let screen = targetScreen() else { return nil }
        let visible = screen.visibleFrame
        let resolved = (
            x: visible.midX - Theme.Size.panelWidth / 2,
            topEdgeY: visible.maxY - visible.height * Theme.Size.paletteTopMarginFraction
        )
        anchor = resolved
        return resolved
    }
}
