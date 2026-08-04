import SwiftUI

/// A palette scroll request: reset and follow need different, estimation-safe scroll ops on a lazy container, so the caller states which it wants instead of the view guessing from one shared token.
struct ScrollIntent: Equatable {
    enum Kind {
        /// Reset: restore the content origin. Estimation-proof — the origin anchor sits at offset 0, so no row height has to be guessed.
        case top
        /// Keyboard nav: minimal scroll-to-visible, which leaves an already-visible row exactly where it is.
        case follow
    }

    var kind: Kind
    /// Distinguishes back-to-back intents of the same kind so `onChange` still fires.
    var nonce = UUID()
}

extension View {
    /// Marks the top of a scroll view's content as the `scrollToOrigin` target. Apply to the scrolled content *after* its padding: the anchor rides in a zero-height overlay, so it pins the true origin (offset 0) without taking part in layout — scrolling to the first row instead would leave the content's top padding hidden under the header.
    func scrollOriginAnchor() -> some View {
        overlay(alignment: .top) {
            Color.clear.frame(height: 0).id(ScrollOrigin.id)
        }
    }

    /// Restores the origin when the floating header's safe-area inset settles the frame after a scroll view mounts.
    func pinOriginOnInsetSettle(_ scroll: ScrollIntent, proxy: ScrollViewProxy) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, _ in
            guard scroll.kind == .top else { return }
            proxy.scrollToOrigin()
        }
    }
}

private enum ScrollOrigin {
    nonisolated static let id = "scroll-origin-anchor"
}

extension ScrollViewProxy {
    /// Restores the exact resting offset, insets included — requires `scrollOriginAnchor()` on the content.
    func scrollToOrigin() {
        scrollTo(ScrollOrigin.id, anchor: .top)
    }

    /// Minimal scroll-to-visible: brings `id` just inside the viewport and never repositions it once visible, so the list stays put while the selection walks across it.
    func reveal(_ id: String) {
        scrollTo(id, anchor: nil)
    }
}
