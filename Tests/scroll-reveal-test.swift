import CoreGraphics
import Foundation

/// Drives `SelectionReveal`, the rule that decides whether keyboard nav still has to move the list.
/// Both halves matter: a row inside the band must not provoke a scroll (the list has to stay put as
/// the selection walks it), and a row in the strip behind the floating bottom bar must, because
/// SwiftUI's own scroll-to-visible reads that strip as visible and leaves the highlight under it.
@main
@MainActor
struct SelectionRevealTests {
    static var failures = 0
    static var passes = 0

    /// The palette's real proportions: a 369pt band between the bars, 36pt rows.
    static let band: CGFloat = 369
    static let rowHeight: CGFloat = 36

    static func expect(
        _ actual: SelectionReveal.Edge?, _ expected: SelectionReveal.Edge?, _ message: String
    ) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(String(describing: actual)), want \(expected as Any)")
        }
    }

    /// A row `rowHeight` tall whose top sits at `top`, the way a list row reports itself.
    static func edge(rowTop top: CGFloat, height: CGFloat = rowHeight) -> SelectionReveal.Edge? {
        SelectionReveal.edge(rowTop: top, rowBottom: top + height, band: band)
    }

    static func main() {
        rowsInsideTheBandStayPut()
        rowsPastAnEdgeAlignToIt()
        theStripBehindTheBottomBar()
        aRowTallerThanTheBand()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Leaving a visible row alone

    static func rowsInsideTheBandStayPut() {
        expect(edge(rowTop: 0), nil, "the first row at the band's top edge needs no scroll")
        expect(edge(rowTop: 180), nil, "nor does a row in the middle")
        expect(edge(rowTop: band - rowHeight), nil, "nor one flush with the bottom edge")
        // Rounding must not churn: geometry arrives in fractional points.
        expect(edge(rowTop: -0.3), nil, "a third of a point over the top edge is still inside")
        expect(edge(rowTop: band - rowHeight + 0.3), nil, "and so is a third of a point under")
    }

    // MARK: - Moving a row that has left the band

    static func rowsPastAnEdgeAlignToIt() {
        expect(edge(rowTop: -1), .top, "a row a point above the band aligns to the top")
        expect(edge(rowTop: -rowHeight), .top, "so does one scrolled a full row above it")
        expect(edge(rowTop: -4000), .top, "and one far above, after a jump to the list's start")
        expect(edge(rowTop: band - rowHeight + 1), .bottom, "a row a point below aligns to the bottom")
        expect(edge(rowTop: band + 4000), .bottom, "and so does one far below it")
    }

    // MARK: - The strip the bug lived in

    static func theStripBehindTheBottomBar() {
        // Measured from the running app: the band ends at 369, and the row that walked into the
        // strip behind the pill reported 369…405 — visible to SwiftUI, hidden to the eye.
        expect(edge(rowTop: 369), .bottom, "the row that lands in the strip is moved into the band")
        expect(edge(rowTop: 333), nil, "while the row flush above the strip is left alone")
    }

    // MARK: - Rows that cannot fit

    static func aRowTallerThanTheBand() {
        // Only its start can show, so aligning the top is the end state, not the start of a loop.
        expect(edge(rowTop: 0, height: band + 100), nil, "a too-tall row pinned at the top is settled")
        expect(edge(rowTop: -50, height: band + 100), .top, "one scrolled past its top is pulled back")
        expect(edge(rowTop: 20, height: band + 100), .top, "and one hanging below the top is too")
    }
}
