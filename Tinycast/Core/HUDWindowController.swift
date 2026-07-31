import AppKit
import SwiftUI

/// Transient, non-interactive confirmation flashed at the bottom of the active screen after something succeeds. Any feature can use it — snippets confirm an insertion, custom commands confirm a run. A leading status dot, not an icon, carries the `ModalKind` tint: lighter weight for a glance-and-forget surface than the dialogs' full symbol.
@MainActor
final class HUDWindowController {
    private let settings: AppSettings
    private var panel: NSPanel?
    private var dismissalTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show(message: String, kind: ModalKind = .success) {
        dismissalTask?.cancel()
        let panel = panel ?? makePanel()
        let host = NSHostingView(rootView: HUDView(message: message, tint: kind.tint))
        // The capsule is only as wide as its message, so the panel takes its size from SwiftUI rather than a fixed frame.
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        position(panel)
        panel.orderFrontRegardless()
        dismissalTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(Theme.Duration.hud))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            self?.dismissalTask = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Liquid Glass carries its own elevation; a second shadow under it reads heavy, as in `PopoverMenu`.
        panel.hasShadow = false
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
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + Theme.Size.hudEdgeOffset))
    }
}

private struct HUDView: View {
    let message: String
    let tint: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(tint)
                .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
            Text(message)
                .font(Theme.Typography.bar)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: Theme.Size.hudMaxWidth, alignment: .leading)
        .fixedSize()
        .frosted(in: Capsule())
    }
}
