import SwiftUI

/// Scroll-driven edge dissolve for a scroll view underlapping the palette's floating bars, a port of Raycast's scroll-area mask (see `docs/ui.md` → The edge dissolve).
struct EdgeDissolveMask: ViewModifier {
    /// Band lengths: the bar's occupied height plus Raycast's overshoot into the list (32px below the header, 28px above the footer).
    var topFade: CGFloat = Theme.Size.headerHeight + Theme.Size.headerPadding + 32
    var bottomFade: CGFloat = Theme.Size.bottomBarHeight + 28
    private static let topMinAlpha: CGFloat = 0.15
    private static let bottomMinAlpha: CGFloat = 0.25

    /// How much content is hidden beyond each edge, 0 when the list rests against it.
    @State private var topDistance: CGFloat = 0
    @State private var bottomDistance: CGFloat = 0
    @State private var canScroll = false

    private struct ScrollState: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var canScroll: Bool
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollState.self) { geo in
                let visible =
                    geo.containerSize.height - geo.contentInsets.top
                    - geo.contentInsets.bottom
                return ScrollState(
                    top: geo.contentOffset.y + geo.contentInsets.top,
                    bottom: geo.contentSize.height + geo.contentInsets.bottom
                        - geo.containerSize.height - geo.contentOffset.y,
                    canScroll: geo.contentSize.height > visible
                )
            } action: { _, new in
                topDistance = max(0, new.top)
                bottomDistance = max(0, new.bottom)
                canScroll = new.canScroll
            }
            .mask(
                // Must span the scroll view's *full* frame — the bars' safe-area insets would otherwise shift the gradient inward, clipping the underlap regions to black.
                GeometryReader { geo in
                    LinearGradient(
                        stops: stops(height: geo.size.height),
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            )
    }

    private func stops(height: CGFloat) -> [Gradient.Stop] {
        guard canScroll, height > 0 else { return [.init(color: .black, location: 0)] }
        // Midpoint alpha eases from 1 toward the floor as a full band of content scrolls past (Raycast: opacity = 1 − (1 − min) · clamp(scrollDistance / fadeHeight, 0, 1)).
        let topAlpha = 1 - (1 - Self.topMinAlpha) * min(topDistance / topFade, 1)
        let bottomAlpha = 1 - (1 - Self.bottomMinAlpha) * min(bottomDistance / bottomFade, 1)
        return [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(topAlpha), location: topFade / 2 / height),
            .init(color: .black, location: topFade / height),
            .init(color: .black, location: 1 - bottomFade / height),
            .init(color: .black.opacity(bottomAlpha), location: 1 - bottomFade / 2 / height),
            .init(color: .black.opacity(0), location: 1),
        ]
    }
}

extension View {
    /// Attach to a `ScrollView` that underlaps the palette's floating bars (before `thinScrollbar`, so the scrollbar overlay stays unmasked).
    func edgeDissolve() -> some View {
        modifier(EdgeDissolveMask())
    }
}
