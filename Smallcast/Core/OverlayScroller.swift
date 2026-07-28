import AppKit
import SwiftUI

extension View {
    func overlayScroller() -> some View {
        background(OverlayScrollerConfigurator().frame(width: 0, height: 0))
    }
}

private struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ProbeView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.applyOverlayStyle()
    }

    private final class ProbeView: NSView {
        private var attemptsRemaining = 12
        private var styleObserver: NotificationToken?

        override init(frame frameRect: NSRect) { super.init(frame: frameRect) }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                styleObserver = nil
                return
            }
            observeStyleChanges()
            attemptsRemaining = 12  // re-attached to a fresh hierarchy; give the splice a few ticks again
            applyOverlayStyle()
        }

        /// AppKit resets scroller style back to the system preference on this notification, so re-apply on the next tick after its own handler runs.
        private func observeStyleChanges() {
            guard styleObserver == nil else { return }
            let token = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.applyOverlayStyle() }
            }
            styleObserver = NotificationToken(token, center: .default)
        }

        func applyOverlayStyle() {
            guard let scrollView = enclosingScrollView else {
                // Not spliced into the scroll view yet; retry next tick, bounded so a view that never lands in one can't spin the main thread.
                guard attemptsRemaining > 0 else { return }
                attemptsRemaining -= 1
                DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
                return
            }
            guard scrollView.scrollerStyle != .overlay || !scrollView.autohidesScrollers else {
                return  // already in the target state — don't churn layout on re-runs
            }
            scrollView.scrollerStyle = .overlay  // thin floating knob that reserves no width
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = true
            scrollView.tile()  // reclaim any gutter the legacy scroller had reserved, same layout pass
        }
    }
}
