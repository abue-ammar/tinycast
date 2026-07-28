import AppKit
import SwiftUI

/// The floating confirmation pill `showHUD` puts on screen.
///
/// It needs its own window rather than a palette overlay: `showHUD` is what a **no-view** command uses,
/// and those close the palette before they finish — Raycast shows the same pill over whatever the user
/// is actually looking at.
@MainActor
final class HUDWindowController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private let text = HUDText()

    /// Observable box so a second `showHUD` re-labels the visible pill instead of stacking windows.
    final class HUDText: ObservableObject {
        @Published var value = ""
    }

    func show(_ message: String, duration: Duration = .seconds(2)) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text.value = trimmed

        let panel = ensurePanel()
        position(panel)
        panel.orderFrontRegardless()

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Never take focus: a HUD appears while the user is typing in another app.
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: HUDView(text: text))
        // Let the hosting view drive this window's size — unlike the palette, the pill is
        // content-sized, and its width changes with the message.
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        self.panel = panel
        return panel
    }

    /// Bottom-centre of the active screen, matching where Raycast puts it.
    private func position(_ panel: NSPanel) {
        panel.layoutIfNeeded()
        // A borderless panel can report a zero fitting size before its first layout; fall back to the
        // hosting view's intrinsic size, then to a sane minimum, so the pill is never a 10pt dot.
        let content = panel.contentView
        let candidates = [content?.fittingSize, content?.intrinsicContentSize].compactMap { $0 }
        let measured = candidates.first { $0.width > 1 && $0.height > 1 }
        let size = measured ?? NSSize(width: 220, height: 44)
        panel.setContentSize(size)
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * Self.bottomMarginFraction))
    }

    private static let bottomMarginFraction: CGFloat = 0.12
}

private struct HUDView: View {
    @ObservedObject var text: HUDWindowController.HUDText

    var body: some View {
        Text(text.value)
            .font(Theme.Typography.bar)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: 420)
            .background(Color.black.opacity(Theme.Colors.panelDimming))
            .background(VisualEffectView())
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .fixedSize()
            // The panel is borderless and clear, so the pill needs the app's dark appearance itself.
            .environment(\.colorScheme, .dark)
    }
}
