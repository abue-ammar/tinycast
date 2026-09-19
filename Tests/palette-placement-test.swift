import CoreGraphics
import Foundation

/// Against the real `Theme`, so retuning cannot restore the palette off-display.
@main
@MainActor
struct PalettePlacementTests {
    static var failures = 0
    static var passes = 0

    // Exactly what `PaletteWindowController` passes, at the size the user picked.
    static let metrics = InterfaceMetrics.standard
    static let width = metrics.size.panelWidth
    static let graspable = CGSize(width: width, height: metrics.size.compactHeight)
    static let minimumVisible = Theme.Size.paletteMinimumVisible
    static let snap = Theme.Size.paletteSnapDistance
    static let topFraction = Theme.Size.paletteTopMarginFraction

    /// A 1440p display with the menu bar taken off the top.
    static let laptop = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    /// A second display stacked to the right, as `NSScreen.screens` would report it.
    static let external = CGRect(x: 2560, y: 0, width: 1920, height: 1055)

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(abs(actual - expected) < 0.001, "\(message) — got \(actual), want \(expected)")
    }

    static func home(_ screen: CGRect) -> CGPoint {
        PalettePlacement.defaultAnchor(
            in: screen, width: width, topMarginFraction: topFraction)
    }

    static func restored(_ stored: CGPoint, on screen: CGRect) -> CGPoint? {
        PalettePlacement.restored(
            stored, graspable: graspable, visibleFrame: screen, minimumVisible: minimumVisible)
    }

    static func main() {
        theDefaultPlacement()
        restoringOnItsOwnDisplay()
        offsetsFollowTheirDisplay()
        restoringPartlyOffscreen()
        snapping()
        menuPanelAnchors()
        tokenGrammar()
        everyInterfaceSize()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - The untouched placement

    static func theDefaultPlacement() {
        let anchor = home(laptop)
        expect(anchor.x, laptop.midX - width / 2, "the panel centres horizontally")
        expect(
            anchor.y, laptop.maxY - laptop.height * topFraction,
            "its top edge sits the margin fraction below the top of the visible area")
        expect(anchor.y < laptop.maxY, "the top edge is inside the screen, not on its edge")

        // The panel grows downward from the anchor, so a full-height list must still fit.
        expect(
            anchor.y - metrics.size.panelHeight > laptop.minY,
            "an expanded palette clears the bottom of the screen it opened on")

        // A screen offset from the origin must not shift the panel off it.
        let offset = home(external)
        expect(offset.x, external.midX - width / 2, "a non-origin display centres the same way")
        expect(
            offset.y, external.maxY - external.height * topFraction,
            "and its top edge is measured from its own maxY")
    }

    // MARK: - Restoring a stored position

    static func restoringOnItsOwnDisplay() {
        let onExternal = CGPoint(x: 2700, y: 900)
        expect(
            restored(onExternal, on: external) == onExternal,
            "a drop comes back verbatim on the display it was made on")
        expect(
            restored(onExternal, on: laptop) == nil,
            "and is never read onto the neighbouring display the palette is summoned on")

        // The fallback has to be reachable, not merely different.
        expect(
            restored(home(laptop), on: laptop) != nil,
            "the default placement is always restorable on its own screen")
    }

    /// Stored against the display, so rearranging or rescaling it keeps the drop.
    static func offsetsFollowTheirDisplay() {
        let dropped = CGPoint(x: external.minX + 400, y: external.maxY - 260)
        let offset = PalettePlacement.offset(of: dropped, on: external)
        expect(offset.x, 400, "the offset runs rightward from the display's own left edge")
        expect(offset.y, 260, "and downward from its top edge")
        expect(
            PalettePlacement.anchor(for: offset, on: external) == dropped,
            "reading it back on the unchanged display returns the point that was dropped")

        // Same display, moved to the other side in Displays settings.
        let rearranged = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let moved = PalettePlacement.anchor(for: offset, on: rearranged)
        expect(moved.x, rearranged.minX + 400, "a rearranged display keeps the drop on itself")
        expect(moved.y, rearranged.maxY - 260, "wherever the global origin left it")
        expect(restored(moved, on: rearranged) != nil, "and the bar is grabbable there")

        // A resolution change shortens it from the bottom, so a top offset holds.
        let scaled = CGRect(x: 2560, y: 0, width: 1440, height: 775)
        let resized = PalettePlacement.anchor(for: offset, on: scaled)
        expect(resized.y, scaled.maxY - 260, "a rescaled display keeps the distance from the top")
        expect(restored(resized, on: scaled) != nil, "and still shows enough of the bar to grab")

        let edge = PalettePlacement.offset(
            of: CGPoint(x: external.maxX - 10, y: external.maxY - 260), on: external)
        expect(
            restored(PalettePlacement.anchor(for: edge, on: scaled), on: scaled) == nil,
            "an offset past the edge of a shrunken display falls home instead")
    }

    static func restoringPartlyOffscreen() {
        // Deliberately slid off to the right: still restorable while a grabbable sliver shows.
        let sliver = CGPoint(x: laptop.maxX - minimumVisible, y: 900)
        expect(
            restored(sliver, on: laptop) != nil,
            "exactly the minimum sliver of the compact bar is still grabbable")
        let tooFar = CGPoint(x: laptop.maxX - minimumVisible + 1, y: 900)
        expect(
            restored(tooFar, on: laptop) == nil,
            "one point less than that is not, and falls back to the default")

        // Slid off the top, where the whole grab strip is what goes missing first.
        let peeking = CGPoint(x: 800, y: laptop.maxY + graspable.height - minimumVisible)
        expect(
            restored(peeking, on: laptop) != nil,
            "a bar hanging off the top edge is grabbable while the minimum still shows")
        let gone = CGPoint(x: 800, y: laptop.maxY + graspable.height - minimumVisible + 1)
        expect(
            restored(gone, on: laptop) == nil,
            "pushed one point further up it is dropped")
    }

    // MARK: - Snapping home

    static func snapping() {
        let target = home(laptop)
        expect(
            PalettePlacement.isSnapping(target, to: target, within: snap),
            "sitting exactly on the default placement snaps")

        for offset in [CGPoint(x: snap, y: 0), CGPoint(x: 0, y: -snap), CGPoint(x: snap, y: snap)] {
            let anchor = CGPoint(x: target.x + offset.x, y: target.y + offset.y)
            expect(
                PalettePlacement.isSnapping(anchor, to: target, within: snap),
                "exactly the snap distance away on \(offset) still snaps")
        }

        // Both axes have to be inside: near in x but far in y is not a snap.
        expect(
            !PalettePlacement.isSnapping(
                CGPoint(x: target.x, y: target.y + snap + 1), to: target, within: snap),
            "one point beyond the threshold in y does not snap")
        expect(
            !PalettePlacement.isSnapping(
                CGPoint(x: target.x + snap + 1, y: target.y), to: target, within: snap),
            "nor does one point beyond it in x")
        expect(
            !PalettePlacement.isSnapping(
                CGPoint(x: target.x + 300, y: target.y - 300), to: target, within: snap),
            "and a panel dragged properly aside stays where it was dropped")
    }

    // MARK: - Menu panels

    static func menuPanelAnchors() {
        let parent = CGRect(x: 100, y: 200, width: 750, height: 475)
        let content = CGSize(width: 276, height: 240)
        let inset = metrics.spacing.md
        let headerExtent = metrics.size.headerPadding + metrics.size.headerHeight

        let leading = MenuPanelCorner.bottomLeading.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(leading.minX, parent.minX + inset, "the left menu follows the footer's leading edge")
        expect(leading.minY, parent.minY + inset, "the left menu follows the footer's bottom edge")

        let trailing = MenuPanelCorner.bottomTrailing.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(trailing.maxX, parent.maxX - inset, "the action menu follows the trailing button")
        expect(trailing.minY, parent.minY + inset, "the action menu follows the footer's bottom edge")

        let header = MenuPanelCorner.belowHeaderTrailing.frame(
            contentSize: content, parentFrame: parent, inset: inset,
            headerExtent: headerExtent)
        expect(header.maxX, parent.maxX - inset * 2, "a header menu follows its trailing control")
        expect(header.maxY, parent.maxY - headerExtent, "a header menu opens below the field")

        let scale = Theme.MenuMotion.maximumScale
        let leadingCanvas = MenuPanelCorner.bottomLeading.scaledFrame(leading, by: scale)
        let trailingCanvas = MenuPanelCorner.bottomTrailing.scaledFrame(trailing, by: scale)
        let headerCanvas = MenuPanelCorner.belowHeaderTrailing.scaledFrame(header, by: scale)
        expect(leadingCanvas.minX, leading.minX, "left expansion keeps its leading edge fixed")
        expect(leadingCanvas.minY, leading.minY, "left expansion keeps its bottom edge fixed")
        expect(trailingCanvas.maxX, trailing.maxX, "right expansion keeps its trailing edge fixed")
        expect(trailingCanvas.minY, trailing.minY, "right expansion keeps its bottom edge fixed")
        expect(headerCanvas.maxX, header.maxX, "header expansion keeps its trailing edge fixed")
        expect(headerCanvas.maxY, header.maxY, "header expansion keeps its top edge fixed")
    }

    // MARK: - The tokens these rules depend on

    static func tokenGrammar() {
        // Raise it past the bar's own height and no stored position is ever restorable again.
        expect(
            minimumVisible <= graspable.height,
            "the minimum visible sliver fits inside the compact bar")
        expect(
            snap * 2 < width,
            "the snap zone is narrower than the panel, so it can't swallow every drop")
        expect(topFraction > 0 && topFraction < 1, "the top margin is a real fraction of the screen")
    }

    // MARK: - The same rules at every Interface Size

    /// The largest palette still has to land on the smallest display Tinycast supports.
    static let smallest = CGRect(x: 0, y: 0, width: 1440, height: 875)

    static func everyInterfaceSize() {
        for size in InterfaceSize.allCases {
            let metrics = InterfaceMetrics(scale: size.scale)
            let width = metrics.size.panelWidth
            let label = "at \(size.rawValue)"

            for screen in [laptop, external, smallest] {
                let anchor = PalettePlacement.defaultAnchor(
                    in: screen, width: width, topMarginFraction: topFraction)
                expect(anchor.x, screen.midX - width / 2, "the panel stays centred \(label)")
                expect(
                    anchor.y - metrics.size.panelHeight > screen.minY,
                    "an expanded palette clears the bottom of a \(Int(screen.width))pt display \(label)"
                )
            }

            // The wider bar needs more of itself on screen, so a stored edge position can lapse.
            let graspable = CGSize(width: width, height: metrics.size.compactHeight)
            let sliver = CGPoint(x: laptop.maxX - minimumVisible, y: 900)
            expect(
                PalettePlacement.restored(
                    sliver, graspable: graspable, visibleFrame: laptop,
                    minimumVisible: minimumVisible) != nil,
                "the minimum sliver is still grabbable \(label)")
            expect(
                PalettePlacement.restored(
                    CGPoint(x: laptop.maxX, y: 900), graspable: graspable,
                    visibleFrame: laptop, minimumVisible: minimumVisible) == nil,
                "a bar dragged fully past the right edge is dropped \(label)")
        }
    }
}
