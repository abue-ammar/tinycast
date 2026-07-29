import AppKit
import SwiftUI

@MainActor
final class SnippetHUDWindowController {
    private let settings: AppSettings
    private var panel: NSPanel?
    private var dismissalTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    // Transient success HUDs are recommended primarily for Custom Commands.
    func show(snippetName: String) {
        dismissalTask?.cancel()
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: SnippetHUDView(snippetName: snippetName))
        position(panel)
        panel.orderFrontRegardless()
        dismissalTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(Theme.Duration.hud))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            self?.dismissalTask = nil
        }
    }

    func hide() {
        dismissalTask?.cancel()
        dismissalTask = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0, y: 0,
                width: Theme.Size.hudWidth,
                height: Theme.Size.hudHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen: NSScreen?
        if settings.openOnCursorScreen {
            let mouse = NSEvent.mouseLocation
            screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        } else {
            screen = NSScreen.main
        }
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - Theme.Size.hudWidth / 2,
            y: visible.maxY - Theme.Size.hudEdgeOffset - Theme.Size.hudHeight))
    }
}

private struct SnippetHUDView: View {
    let snippetName: String

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Inserted \(snippetName)")
                .font(.body.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.xxl)
        .frame(width: Theme.Size.hudWidth, height: Theme.Size.hudHeight)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hud, style: .continuous))
    }
}
