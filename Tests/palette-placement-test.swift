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
        expandedDetentFollowsGeometry()
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

    // MARK: - Invisible centre line

    static func snapping() {
        for screen in [laptop, external] {
            let origin = home(screen)
            let expandedY = screen.midY + metrics.size.panelHeight / 2
            func snapped(
                _ point: CGPoint, previous: PalettePlacement.Snap? = nil, speed: CGFloat = 0
            ) -> PalettePlacement.Snap {
                PalettePlacement.snapped(
                    point, home: origin, visibleFrame: screen,
                    expandedHeight: metrics.size.panelHeight, within: snap,
                    previous: previous, speed: speed)
            }
            let freeY = (origin.y + expandedY) / 2
            let centered = PalettePlacement.Snap(
                anchor: CGPoint(x: origin.x, y: freeY), centeredX: true, height: nil)
            expect(
                snapped(CGPoint(x: origin.x + snap, y: freeY)).anchor.x, origin.x,
                "the centre line catches at the right boundary")
            expect(
                snapped(CGPoint(x: origin.x - snap, y: freeY)).anchor.x, origin.x,
                "the centre line catches at the left boundary")
            expect(
                !snapped(CGPoint(x: origin.x + snap + 1, y: freeY)).centeredX,
                "an unlatched drag does not catch beyond the entry range")
            expect(
                snapped(CGPoint(x: origin.x + snap * 2, y: origin.y + 1), previous: centered)
                    .height == .home,
                "a latched drag holds the centre line and its height detent twice as far")
            expect(
                !snapped(
                    CGPoint(x: origin.x + snap * 2 + 1, y: origin.y + 1),
                    previous: centered
                ).centeredX,
                "a latched drag releases beyond twice the entry range")
            expect(
                snapped(CGPoint(x: origin.x + snap + 1, y: origin.y + 1)).anchor
                    == CGPoint(x: origin.x + snap + 1, y: origin.y + 1),
                "the home detent does not extend horizontally")
            expect(
                snapped(CGPoint(x: origin.x + snap + 1, y: expandedY + 1)).height == nil,
                "the expanded detent does not extend horizontally")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: origin.y + snap)).height == .home,
                "the home detent catches on the centre line")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: expandedY - snap)).anchor.y,
                expandedY, "the expanded detent centres the full-height palette")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: freeY)).anchor.y, freeY,
                "height remains free between the two detents")
            let fast = PalettePlacement.maxSnapEntrySpeedPointsPerSecond + 1
            expect(
                !snapped(CGPoint(x: origin.x + 1, y: freeY), speed: fast).centeredX,
                "a fast pass does not enter the centre line")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: freeY), speed: fast - 1).centeredX,
                "a deliberate pass can still enter the centre line")
            expect(
                snapped(CGPoint(x: origin.x + snap * 2, y: freeY), previous: centered, speed: fast)
                    .centeredX,
                "speed does not release an already held centre line")
            expect(
                snapped(CGPoint(x: origin.x + 1, y: origin.y + 1), previous: centered, speed: fast)
                    .height == nil,
                "a fast pass on the centre line does not enter a height detent")
            let held = PalettePlacement.Snap(anchor: origin, centeredX: true, height: .home)
            expect(
                snapped(CGPoint(x: origin.x + 1, y: origin.y + 1), previous: held, speed: fast)
                    .height == .home,
                "speed does not release an already held detent")
        }
    }

    static func expandedDetentFollowsGeometry() {
        let shifted = CGRect(x: 300, y: 50, width: 1800, height: 1000)
        for size in InterfaceSize.allCases {
            let panelHeight = size.metrics.size.panelHeight
            let top = PalettePlacement.expandedCenterY(
                in: shifted, expandedHeight: panelHeight)
            expect(
                top - panelHeight / 2, shifted.midY,
                "the expanded detent stays centred after display or Interface Size changes")
        }
    }

    // MARK: - Menu panels

    static func menuPanelAnchors() {
        let parent = CGRect(x: 100, y: 200, width: 750, height: 475)
        let visible = CGRect(x: 0, y: -400, width: 1440, height: 1200)
        let content = CGSize(width: 276, height: 240)
        let inset = metrics.spacing.md
        let headerExtent = metrics.size.headerPadding + metrics.size.headerHeight

        let leading = MenuPanelCorner.bottomLeading.frame(
            contentSize: content, parentFrame: parent, visibleFrame: visible, inset: inset,
            headerExtent: headerExtent)
        expect(leading.minX, parent.minX + inset, "the left menu follows the footer's leading edge")
        expect(leading.minY, parent.minY + inset, "the left menu follows the footer's bottom edge")

        let trailing = MenuPanelCorner.bottomTrailing.frame(
            contentSize: content, parentFrame: parent, visibleFrame: visible, inset: inset,
            headerExtent: headerExtent)
        expect(trailing.maxX, parent.maxX - inset, "the action menu follows the trailing button")
        expect(trailing.minY, parent.minY + inset, "the action menu follows the footer's bottom edge")

        let header = MenuPanelCorner.belowHeaderTrailing.frame(
            contentSize: content, parentFrame: parent, visibleFrame: visible, inset: inset,
            headerExtent: headerExtent)
        expect(header.maxX, parent.maxX - inset * 2, "a header menu follows its trailing control")
        expect(header.maxY, parent.maxY - headerExtent, "a header menu opens below the field")

        let control = CGRect(x: 450, y: 100, width: 60, height: 34)
        let controlCorner = MenuPanelCorner.belowControl(control)
        let input = controlCorner.frame(
            contentSize: content, parentFrame: parent, visibleFrame: visible,
            inset: inset, headerExtent: headerExtent)
        expect(input.maxX, parent.minX + control.maxX, "an input menu follows its control's trailing edge")
        expect(
            input.maxY, parent.maxY - control.maxY - inset, "an input menu converts the flipped control frame"
        )
        let inputLeadingCorner = MenuPanelCorner.belowControl(control, trailing: false)
        let inputLeading = inputLeadingCorner.frame(
            contentSize: content, parentFrame: parent, visibleFrame: visible,
            inset: inset, headerExtent: headerExtent)
        expect(inputLeading.minX, parent.minX + control.minX, "a leading input follows its control")
        expect(inputLeading.maxY, input.maxY, "both input alignments open at the same height")

        let bottomControl = MenuPanelCorner.belowControl(CGRect(x: 5, y: 420, width: 60, height: 34))
        let constrained = bottomControl.frame(
            contentSize: content, parentFrame: parent, visibleFrame: visible,
            inset: inset, headerExtent: headerExtent)
        expect(
            constrained.maxY, parent.maxY - 454 - inset,
            "a low input opens below its field even outside the palette")
        expect(
            constrained.minX, visible.minX + inset, "an input menu stays inside its display"
        )
        let nearBottom = CGRect(x: 0, y: 0, width: 1440, height: 800)
        let flipped = bottomControl.frame(
            contentSize: content, parentFrame: parent, visibleFrame: nearBottom,
            inset: inset, headerExtent: headerExtent)
        expect(flipped.minY, parent.maxY - 420 + inset, "a low input opens above to clear the Dock")
        let rightControl = MenuPanelCorner.belowControl(
            CGRect(x: 730, y: 100, width: 100, height: 34), trailing: false)
        let clamped = rightControl.frame(
            contentSize: content, parentFrame: parent,
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            inset: inset, headerExtent: headerExtent)
        expect(clamped.maxX, 1000 - inset, "a leading menu clears the display's right edge")

        let scale = Theme.MenuMotion.maximumScale
        let leadingCanvas = MenuPanelCorner.bottomLeading.scaledFrame(leading, by: scale, parentFrame: parent)
        let trailingCanvas = MenuPanelCorner.bottomTrailing.scaledFrame(
            trailing, by: scale, parentFrame: parent)
        let headerCanvas = MenuPanelCorner.belowHeaderTrailing.scaledFrame(
            header, by: scale, parentFrame: parent)
        let inputCanvas = controlCorner.scaledFrame(input, by: scale, parentFrame: parent)
        let inputLeadingCanvas = inputLeadingCorner.scaledFrame(inputLeading, by: scale, parentFrame: parent)
        let flippedCanvas = bottomControl.scaledFrame(flipped, by: scale, parentFrame: parent)
        expect(leadingCanvas.minX, leading.minX, "left expansion keeps its leading edge fixed")
        expect(leadingCanvas.minY, leading.minY, "left expansion keeps its bottom edge fixed")
        expect(trailingCanvas.maxX, trailing.maxX, "right expansion keeps its trailing edge fixed")
        expect(trailingCanvas.minY, trailing.minY, "right expansion keeps its bottom edge fixed")
        expect(headerCanvas.maxX, header.maxX, "header expansion keeps its trailing edge fixed")
        expect(headerCanvas.maxY, header.maxY, "header expansion keeps its top edge fixed")
        expect(inputCanvas.maxX, input.maxX, "input expansion keeps its trailing edge fixed")
        expect(inputCanvas.maxY, input.maxY, "input expansion keeps its top edge fixed")
        expect(inputLeadingCanvas.minX, inputLeading.minX, "leading input expansion keeps its left edge")
        expect(inputLeadingCanvas.maxY, inputLeading.maxY, "leading input expansion keeps its top edge")
        expect(flippedCanvas.minY, flipped.minY, "a flipped input expansion grows away from its field")
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
            let metrics = size.metrics
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
