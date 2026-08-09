import SwiftUI

/// A scroll request; reset and follow need different ops, so the caller states which.
struct ScrollIntent: Equatable {
    enum Kind {
        /// Reset to the content origin; the anchor sits at offset 0, so nothing is guessed.
        case top
        /// Keyboard nav: minimal scroll-to-visible, leaving a visible row where it is.
        case follow
    }

    var kind: Kind
    /// Distinguishes back-to-back intents of the same kind so `onChange` still fires.
    var nonce = UUID()
}

extension View {
    /// Marks the content top as the `scrollToOrigin` target; apply after the padding.
    func scrollOriginAnchor() -> some View {
        overlay(alignment: .top) {
            Color.clear.frame(height: 0).id(ScrollOrigin.id)
        }
    }

    /// Applies top intents once the header inset is usable; screens still own follow behavior.
    func applyTopScrollIntent(_ scroll: ScrollIntent, proxy: ScrollViewProxy) -> some View {
        modifier(TopScrollIntentModifier(scroll: scroll, proxy: proxy))
    }
}

private struct MountScrollGeometry: Equatable {
    let topInset: CGFloat
    let contentOffsetY: CGFloat
}

private struct TopScrollIntentModifier: ViewModifier {
    let scroll: ScrollIntent
    let proxy: ScrollViewProxy
    @State private var pendingTopNonce: UUID?
    @State private var topInset: CGFloat = 0

    private static let geometryTolerance: CGFloat = 0.5

    init(scroll: ScrollIntent, proxy: ScrollViewProxy) {
        self.scroll = scroll
        self.proxy = proxy
        _pendingTopNonce = State(initialValue: scroll.kind == .top ? scroll.nonce : nil)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: scroll.nonce) {
                guard scroll.kind == .top else {
                    pendingTopNonce = nil
                    return
                }
                guard topInset > 0 else {
                    pendingTopNonce = scroll.nonce
                    return
                }
                pendingTopNonce = nil
                proxy.scrollToOrigin()
            }
            .onScrollPhaseChange { _, phase in
                guard phase == .interacting else { return }
                pendingTopNonce = nil
            }
            .onScrollGeometryChange(for: MountScrollGeometry.self) { geometry in
                MountScrollGeometry(
                    topInset: geometry.contentInsets.top,
                    contentOffsetY: geometry.contentOffset.y)
            } action: { oldGeometry, newGeometry in
                let offsetDelta = newGeometry.contentOffsetY - oldGeometry.contentOffsetY
                let insetDelta = newGeometry.topInset - oldGeometry.topInset
                let offsetChanged = abs(offsetDelta) > Self.geometryTolerance
                let followsInset = abs(offsetDelta + insetDelta) <= Self.geometryTolerance
                if oldGeometry.topInset <= 0, offsetChanged, !followsInset {
                    pendingTopNonce = nil
                }
                topInset = newGeometry.topInset
                guard newGeometry.topInset > 0 else { return }
                guard scroll.kind == .top, pendingTopNonce == scroll.nonce else { return }
                pendingTopNonce = nil
                proxy.scrollToOrigin()
            }
    }
}

private enum ScrollOrigin {
    nonisolated static let id = "scroll-origin-anchor"
}

extension ScrollViewProxy {
    /// Restores the exact resting offset; needs `scrollOriginAnchor()` on the content.
    func scrollToOrigin() {
        scrollTo(ScrollOrigin.id, anchor: .top)
    }

    /// Minimal scroll-to-visible, so the list stays put as the selection walks it.
    func reveal(_ id: String) {
        scrollTo(id, anchor: nil)
    }
}
