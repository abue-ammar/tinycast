import AppKit
import SwiftUI

/// What both HUDs agree on: one at a time, replace, fade, dwell, fade away.
@MainActor
final class HUDPresenter {
    /// Where the panel sits above the bottom of the visible frame.
    enum Anchor {
        case edgeInset(CGFloat)
        case heightFraction(CGFloat)
    }

    private let anchor: Anchor
    private let dwell: TimeInterval
    private let screen: () -> NSScreen?
    private var panel: HUDPanel?
    private var dismissal: Task<Void, Never>?

    init(anchor: Anchor, dwell: TimeInterval, screen: @escaping () -> NSScreen?) {
        self.anchor = anchor
        self.dwell = dwell
        self.screen = screen
    }

    /// A nil `size` lets SwiftUI measure; progress has no dwell, so it waits to be replaced.
    func show(_ view: some View, size: CGSize? = nil, dwells: Bool = true) {
        let panel = panel ?? make()
        let host = NSHostingView(rootView: view)
        // Never size from `host.frame` after attaching: AppKit resets it to the content rect.
        let content = size ?? host.fittingSize
        host.setFrameSize(content)
        panel.setContentSize(content)
        panel.contentView = host
        place(panel)
        // A panel on screen may be mid-fade, so bring it back rather than start another.
        if panel.isVisible {
            panel.cancelFade()
        } else {
            panel.fadeIn(duration: Theme.Duration.enter) { panel.orderFrontRegardless() }
        }
        if dwells { scheduleDismissal() } else { dismissal?.cancel() }
    }

    func dismiss() {
        dismissal?.cancel()
        guard let panel, panel.isVisible else { return }
        panel.fadeOut(duration: Theme.Duration.exit)
    }

    /// Re-arms the dismissal, so a repeat extends the dwell rather than replaying it.
    func extend() {
        guard let panel, panel.isVisible else { return }
        panel.cancelFade()
        scheduleDismissal()
    }

    var isShowing: Bool { panel?.isVisible ?? false }

    private func scheduleDismissal() {
        dismissal?.cancel()
        dismissal = Task { [weak self, dwell] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self?.panel?.fadeOut(duration: Theme.Duration.exit)
        }
    }

    private func make() -> HUDPanel {
        let panel = HUDPanel()
        self.panel = panel
        return panel
    }

    private func place(_ panel: NSPanel) {
        guard let visible = screen()?.visibleFrame else { return }
        let y: CGFloat
        switch anchor {
        case .edgeInset(let inset):
            y = visible.minY + inset
        case .heightFraction(let fraction):
            y = visible.minY + visible.height * fraction
        }
        panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: y))
    }
}
