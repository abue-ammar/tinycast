import SwiftUI

/// Edge fade for bounded lists: marks hidden content and clears once the list reaches that edge.
struct OverflowFadeMask: ViewModifier {
    /// Short enough to read as an edge treatment rather than as a dimmed final row.
    var band: CGFloat = 24
    var includesTop = false

    /// Content hidden beyond each visible edge, 0 while the list rests against it.
    @State private var overflow = Overflow()

    private struct Overflow: Equatable {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Overflow.self) { geo in
                Overflow(
                    top: geo.contentOffset.y + geo.contentInsets.top,
                    bottom: geo.contentSize.height + geo.contentInsets.bottom
                        - geo.containerSize.height - geo.contentOffset.y)
            } action: { _, new in
                overflow = Overflow(top: max(0, new.top), bottom: max(0, new.bottom))
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
        guard includesTop else { return bottomStops(height: height) }
        // Popup edges use several stops so neither end cuts abruptly through a row.
        let topStrength = Double(min(overflow.top / band, 1))
        let bottomStrength = Double(min(overflow.bottom / band, 1))
        guard max(topStrength, bottomStrength) > 0, height > 0 else {
            return [.init(color: .black, location: 0)]
        }
        let extent = min(band / height, 0.5)
        return [
            .init(color: .black.opacity(1 - topStrength), location: 0),
            .init(
                color: .black.opacity(1 - topStrength * 0.75),
                location: extent * 0.35),
            .init(
                color: .black.opacity(1 - topStrength * 0.25),
                location: extent * 0.7),
            .init(color: .black, location: extent),
            .init(color: .black, location: 1 - extent),
            .init(
                color: .black.opacity(1 - bottomStrength * 0.25),
                location: 1 - extent * 0.7),
            .init(
                color: .black.opacity(1 - bottomStrength * 0.75),
                location: 1 - extent * 0.35),
            .init(color: .black.opacity(1 - bottomStrength), location: 1)
        ]
    }

    /// The original Settings and Notes curve stays unchanged when no popup opts into its top edge.
    private func bottomStops(height: CGFloat) -> [Gradient.Stop] {
        let strength = min(overflow.bottom / band, 1)
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
    func overflowFade(band: CGFloat = 24, includingTop: Bool = false) -> some View {
        modifier(OverflowFadeMask(band: band, includesTop: includingTop))
    }
}
