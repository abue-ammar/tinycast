import SwiftUI

/// Bottom fade for a Settings list: marks content below the edge, and clears once the list rests.
struct OverflowFadeMask: ViewModifier {
    /// Short enough to read as an edge treatment rather than as a dimmed final row.
    var band: CGFloat = 24

    /// Content hidden below the visible area, 0 once the list rests against the bottom.
    @State private var overflow: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentSize.height + geo.contentInsets.bottom - geo.containerSize.height
                    - geo.contentOffset.y
            } action: { _, new in
                overflow = max(0, new)
            }
            .mask(
                GeometryReader { geo in
                    LinearGradient(
                        stops: stops(height: geo.size.height),
                        startPoint: .top, endPoint: .bottom
                    )
                }
            )
    }

    private func stops(height: CGFloat) -> [Gradient.Stop] {
        // Eased over one band, so the last row never snaps between opaque and faded in one step.
        let strength = min(overflow / band, 1)
        guard strength > 0, height > band else { return [.init(color: .black, location: 0)] }
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: 1 - band / height),
            .init(color: .black.opacity(1 - strength), location: 1)
        ]
    }
}

extension View {
    /// Attach before `thinScrollbar`. Not `edgeDissolve`, which is tuned to the palette's bars.
    func overflowFade() -> some View {
        modifier(OverflowFadeMask())
    }
}
