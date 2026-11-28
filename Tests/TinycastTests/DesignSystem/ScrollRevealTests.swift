import CoreGraphics
import Testing

@testable import Tinycast

struct ScrollRevealTests {
    /// The palette's real proportions: a 369pt band between the bars, 36pt rows.
    static let band: CGFloat = 369
    static let rowHeight: CGFloat = 36

    @Test(arguments: [0, 180, band - rowHeight] as [CGFloat])
    func aRowInsideTheBandNeedsNoScroll(top: CGFloat) {
        #expect(Self.edge(rowTop: top) == nil)
    }

    /// Geometry arrives in fractional points, so rounding must not churn.
    @Test(arguments: [-0.3, band - rowHeight + 0.3] as [CGFloat])
    func aFractionOfAPointPastAnEdgeIsStillInside(top: CGFloat) {
        #expect(Self.edge(rowTop: top) == nil)
    }

    @Test(arguments: [-1, -rowHeight, -4000] as [CGFloat])
    func aRowAboveTheBandAlignsToTheTop(top: CGFloat) {
        #expect(Self.edge(rowTop: top) == .top)
    }

    @Test(arguments: [band - rowHeight + 1, band + 4000] as [CGFloat])
    func aRowBelowTheBandAlignsToTheBottom(top: CGFloat) {
        #expect(Self.edge(rowTop: top) == .bottom)
    }

    /// Measured from the app: the band ends at 369, and 369…405 is visible but hidden.
    @Test func aRowInTheStripBehindTheBottomBarMovesIntoTheBand() {
        #expect(Self.edge(rowTop: 369) == .bottom)
        #expect(Self.edge(rowTop: 333) == nil)
    }

    /// Only its start can show, so aligning the top is the end state, not the start of a loop.
    @Test func aRowTallerThanTheBandPinnedAtTheTopIsSettled() {
        #expect(Self.edge(rowTop: 0, height: Self.band + 100) == nil)
    }

    @Test(arguments: [-50, 20] as [CGFloat])
    func aRowTallerThanTheBandOffItsTopIsPulledBack(top: CGFloat) {
        #expect(Self.edge(rowTop: top, height: Self.band + 100) == .top)
    }

    private static func edge(rowTop top: CGFloat, height: CGFloat = rowHeight) -> SelectionReveal.Edge? {
        SelectionReveal.edge(rowTop: top, rowBottom: top + height, band: band)
    }
}
