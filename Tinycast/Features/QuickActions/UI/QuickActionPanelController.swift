import AppKit
import SwiftUI

/// Owns the result panel: one at a time, and the target app keeps its selection while it is up.
@MainActor
final class QuickActionPanelController: NSObject, NSWindowDelegate {
    private var panel: QuickActionPanel?
    private var state: QuickActionPanelState?
    private var onReplace: ((String) -> Void)?
    private var onRetranslate: ((Locale.Language) -> Void)?
    private var onDownloaded: (() -> Void)?

    /// Clear of the pointer, so the panel never opens under the hand that summoned it.
    private static let cursorOffset: CGFloat = 12
    private static let screenMargin: CGFloat = 8

    func present(
        _ state: QuickActionPanelState,
        languages: [Locale.Language],
        onRetranslate: @escaping (Locale.Language) -> Void,
        onDownloaded: @escaping () -> Void,
        onReplace: @escaping (String) -> Void
    ) {
        dismiss()
        self.state = state
        self.onReplace = onReplace
        self.onRetranslate = onRetranslate
        self.onDownloaded = onDownloaded

        let hosting = NSHostingView(
            rootView: QuickActionResultView(
                state: state,
                languages: languages,
                onReplace: { [weak self] in self?.replace(state.output) },
                onCopy: { [weak self] in self?.copyOutput() },
                onCancel: { [weak self] in self?.dismiss() },
                onRetranslate: { [weak self] in self?.onRetranslate?($0) },
                onDownloaded: { [weak self] in self?.onDownloaded?() },
                onHeight: { [weak self] in self?.resize(toHeight: $0) }))
        // The controller owns the frame; without this the top edge drifts as the reply grows.
        hosting.sizingOptions = []
        // Its tallest, so the first frame is never short; the view reports the real height at once.
        hosting.setFrameSize(
            NSSize(width: Theme.Size.quickActionPanel, height: Theme.Size.quickActionPanelBody))

        let panel = QuickActionPanel(content: hosting)
        panel.delegate = self
        panel.onKey = { [weak self] key in
            guard let self, let state = self.state else { return }
            switch key {
            case .replace: if state.canReplace { self.replace(state.output) }
            case .copy: if state.canReplace { self.copyOutput() }
            case .cancel: self.dismiss()
            }
        }
        self.panel = panel
        placeAtCursor(panel)
        // Non-activating like the palette: key focus without pulling the reader out of their app.
        panel.fadeIn(duration: Theme.Duration.enter) {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    func dismiss() {
        guard let closing = panel else { return }
        panel = nil
        state = nil
        onReplace = nil
        onRetranslate = nil
        onDownloaded = nil
        closing.delegate = nil
        closing.onKey = nil
        closing.fadeOut(duration: Theme.Duration.exit)
    }

    private func copyOutput() {
        guard let state else { return }
        Paster.copyPlainText(state.output)
    }

    private func replace(_ text: String) {
        let callback = onReplace
        dismiss()
        callback?(text)
    }

    /// Grows from the current top-left, so a reply landing after a drag cannot snap the panel back.
    private func resize(toHeight height: CGFloat) {
        guard let panel, height > 0, abs(height - panel.frame.height) > 0.5 else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let width = panel.frame.width
        panel.setFrame(
            NSRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height),
            display: true)
        clampOnScreen(panel)
    }

    private func placeAtCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: mouse.x + Self.cursorOffset,
                y: mouse.y - Self.cursorOffset - size.height))
        clampOnScreen(panel)
    }

    private func clampOnScreen(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = panel.frame
        let x = min(
            max(frame.minX, visible.minX + Self.screenMargin),
            max(visible.maxX - frame.width - Self.screenMargin, visible.minX + Self.screenMargin))
        let y = min(
            max(frame.minY, visible.minY + Self.screenMargin),
            max(visible.maxY - frame.height - Self.screenMargin, visible.minY + Self.screenMargin))
        guard x != frame.minX || y != frame.minY else { return }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        dismiss()
    }
}
