import AppKit
import SwiftUI

@MainActor
final class InlineEmojiWindowController {
    private var panel: Panel?

    func show(coordinator: InlineEmojiCoordinator, settings: AppSettings, anchor: CGRect) {
        let panel: Panel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = Panel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }
        let hosting = NSHostingView(
            rootView: InlineEmojiPickerView()
                .environment(coordinator).environment(settings)
                .environment(\.metrics, settings.interfaceSize.metrics))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        let metrics = settings.interfaceSize.metrics
        let width = metrics.size.menuWidth
        hosting.setFrameSize(NSSize(width: width, height: 1))
        let height = hosting.fittingSize.height
        guard let screenTop = NSScreen.screens.first?.frame.maxY else { return }
        let target = CGRect(
            x: anchor.minX, y: screenTop - anchor.maxY, width: anchor.width, height: anchor.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(target) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let gap = metrics.spacing.xs
        let below = target.minY - gap - height
        let y = below >= visible.minY ? below : target.maxY + gap
        let frame = CGRect(
            x: min(max(target.minX, visible.minX), visible.maxX - width),
            y: min(max(y, visible.minY), visible.maxY - height), width: width, height: height)
        panel.setFrame(frame, display: true)
        hosting.setFrameSize(frame.size)
        coordinator.listener.setPanelBounds(
            CGRect(x: frame.minX, y: screenTop - frame.maxY, width: frame.width, height: frame.height))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}
