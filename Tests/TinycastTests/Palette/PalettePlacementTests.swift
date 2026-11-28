import CoreGraphics
import Testing

@testable import Tinycast

/// Against the real `Theme`, so retuning cannot restore the palette off-display.
struct PalettePlacementTests {
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
    /// The largest palette still has to land on the smallest display Tinycast supports.
    static let smallest = CGRect(x: 0, y: 0, width: 1440, height: 875)

    // MARK: The glass window

    @Test(arguments: InterfaceSize.allCases, [CGPoint(x: 250, y: 900), CGPoint(x: -1200, y: -80)])
    func theCompactWindowGivesTheGlassClearance(_ size: InterfaceSize, _ anchor: CGPoint) {
        let glass = Glass(size)
        let compact = glass.compact(at: anchor)
        #expect(abs(compact.width - (glass.compactSize.width + glass.outset * 2)) < 0.001)
        #expect(abs(compact.height - (glass.compactSize.height + glass.outset * 2)) < 0.001)
        #expect(PalettePlacement.anchor(of: compact, outset: glass.outset) == anchor)
    }

    @Test(arguments: InterfaceSize.allCases, [CGPoint(x: 250, y: 900), CGPoint(x: -1200, y: -80)])
    func aDragMovesTheVisibleAnchor(_ size: InterfaceSize, _ anchor: CGPoint) {
        let glass = Glass(size)
        let moved = glass.compact(at: anchor).offsetBy(dx: 137, dy: -53)
        #expect(
            PalettePlacement.anchor(of: moved, outset: glass.outset)
                == CGPoint(x: anchor.x + 137, y: anchor.y - 53))
    }

    @Test(arguments: InterfaceSize.allCases, [CGPoint(x: 250, y: 900), CGPoint(x: -1200, y: -80)])
    func expandingAndCollapsingAfterAMoveKeepTheVisibleEdges(_ size: InterfaceSize, _ anchor: CGPoint) {
        let glass = Glass(size)
        let moved = glass.compact(at: anchor).offsetBy(dx: 137, dy: -53)
        let movedAnchor = PalettePlacement.anchor(of: moved, outset: glass.outset)
        let expanded = PalettePlacement.frame(at: movedAnchor, size: glass.expandedSize, outset: 0)
        #expect(abs(expanded.minX - movedAnchor.x) < 0.001)
        #expect(abs(expanded.maxY - movedAnchor.y) < 0.001)
        #expect(glass.compact(at: PalettePlacement.anchor(of: expanded, outset: 0)) == moved)
    }

    // MARK: The untouched placement

    /// A display offset from the origin centres the same way, measured from its own maxY.
    @Test(arguments: [laptop, external])
    func homeCentresBelowTheTopMargin(_ screen: CGRect) {
        let anchor = Self.home(screen)
        #expect(abs(anchor.x - (screen.midX - Self.width / 2)) < 0.001)
        #expect(abs(anchor.y - (screen.maxY - screen.height * Self.topFraction)) < 0.001)
    }

    /// The panel grows downward from the anchor, so a full-height list must still fit.
    @Test func homeLeavesRoomForTheExpandedPalette() {
        let anchor = Self.home(Self.laptop)
        #expect(anchor.y < Self.laptop.maxY, "inside the screen, not on its edge")
        #expect(anchor.y - Self.metrics.size.panelHeight > Self.laptop.minY)
    }

    // MARK: Restoring a stored position

    @Test func aDropComesBackVerbatimOnItsOwnDisplay() {
        let drop = CGPoint(x: 2700, y: 900)
        #expect(Self.restored(drop, on: Self.external) == drop)
    }

    @Test func aDropIsNeverReadOntoTheNeighbouringDisplay() {
        #expect(Self.restored(CGPoint(x: 2700, y: 900), on: Self.laptop) == nil)
    }

    /// The fallback has to be reachable, not merely different.
    @Test func homeIsAlwaysRestorableOnItsOwnScreen() {
        #expect(Self.restored(Self.home(Self.laptop), on: Self.laptop) != nil)
    }

    @Test func anOffsetRunsFromTheDisplaysTopLeft() {
        let drop = CGPoint(x: Self.external.minX + 400, y: Self.external.maxY - 260)
        let offset = PalettePlacement.offset(of: drop, on: Self.external)
        #expect(abs(offset.x - 400) < 0.001)
        #expect(abs(offset.y - 260) < 0.001)
        #expect(PalettePlacement.anchor(for: offset, on: Self.external) == drop)
    }

    /// Same display, moved to the other side in Displays settings.
    @Test func aRearrangedDisplayKeepsTheDropOnItself() {
        let rearranged = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let moved = PalettePlacement.anchor(for: Self.droppedOffset, on: rearranged)
        #expect(abs(moved.x - (rearranged.minX + 400)) < 0.001)
        #expect(abs(moved.y - (rearranged.maxY - 260)) < 0.001)
        #expect(Self.restored(moved, on: rearranged) != nil)
    }

    /// A resolution change shortens it from the bottom, so a top offset holds.
    @Test func aRescaledDisplayKeepsTheDistanceFromTheTop() {
        let resized = PalettePlacement.anchor(for: Self.droppedOffset, on: Self.rescaled)
        #expect(abs(resized.y - (Self.rescaled.maxY - 260)) < 0.001)
        #expect(Self.restored(resized, on: Self.rescaled) != nil)
    }

    @Test func anOffsetPastAShrunkenDisplaysEdgeFallsHome() {
        let edge = PalettePlacement.offset(
            of: CGPoint(x: Self.external.maxX - 10, y: Self.external.maxY - 260), on: Self.external)
        #expect(
            Self.restored(PalettePlacement.anchor(for: edge, on: Self.rescaled), on: Self.rescaled) == nil)
    }

    @Test func aBarSlidOffTheRightIsRestorableWhileTheMinimumSliverShows() {
        let laptop = Self.laptop
        #expect(Self.restored(CGPoint(x: laptop.maxX - Self.minimumVisible, y: 900), on: laptop) != nil)
        #expect(Self.restored(CGPoint(x: laptop.maxX - Self.minimumVisible + 1, y: 900), on: laptop) == nil)
    }

    /// Off the top, the whole grab strip is what goes missing first.
    @Test func aBarSlidOffTheTopIsRestorableWhileTheMinimumShows() {
        let top = Self.laptop.maxY + Self.graspable.height - Self.minimumVisible
        #expect(Self.restored(CGPoint(x: 800, y: top), on: Self.laptop) != nil)
        #expect(Self.restored(CGPoint(x: 800, y: top + 1), on: Self.laptop) == nil)
    }

    // MARK: Invisible centre line

    @Test(arguments: [laptop, external])
    func theCentreLineCatchesWithinItsEntryRange(_ screen: CGRect) {
        let drag = Drag(on: screen)
        #expect(abs(drag.snapped(x: drag.home.x + Self.snap, y: drag.freeY).anchor.x - drag.home.x) < 0.001)
        #expect(abs(drag.snapped(x: drag.home.x - Self.snap, y: drag.freeY).anchor.x - drag.home.x) < 0.001)
        #expect(!drag.snapped(x: drag.home.x + Self.snap + 1, y: drag.freeY).centeredX)
    }

    @Test(arguments: [laptop, external])
    func aLatchedDragHoldsTheCentreLineTwiceAsFar(_ screen: CGRect) {
        let drag = Drag(on: screen)
        let held = drag.snapped(x: drag.home.x + Self.snap * 2, y: drag.home.y + 1, previous: drag.centered)
        #expect(held.height == .home)
        let released = drag.snapped(
            x: drag.home.x + Self.snap * 2 + 1, y: drag.home.y + 1, previous: drag.centered)
        #expect(!released.centeredX)
    }

    @Test(arguments: [laptop, external])
    func theHeightDetentsDoNotExtendHorizontally(_ screen: CGRect) {
        let drag = Drag(on: screen)
        let offLine = CGPoint(x: drag.home.x + Self.snap + 1, y: drag.home.y + 1)
        #expect(drag.snapped(x: offLine.x, y: offLine.y).anchor == offLine)
        #expect(drag.snapped(x: offLine.x, y: drag.expandedY + 1).height == nil)
    }

    @Test(arguments: [laptop, external])
    func theHomeDetentCatchesOnTheCentreLine(_ screen: CGRect) {
        let drag = Drag(on: screen)
        #expect(drag.snapped(x: drag.home.x + 1, y: drag.home.y + Self.snap).height == .home)
    }

    @Test(arguments: [laptop, external])
    func theExpandedDetentCentresTheFullHeightPalette(_ screen: CGRect) {
        let drag = Drag(on: screen)
        #expect(
            abs(drag.snapped(x: drag.home.x + 1, y: drag.expandedY - Self.snap).anchor.y - drag.expandedY)
                < 0.001)
    }

    @Test(arguments: [laptop, external])
    func heightRemainsFreeBetweenTheDetents(_ screen: CGRect) {
        let drag = Drag(on: screen)
        #expect(abs(drag.snapped(x: drag.home.x + 1, y: drag.freeY).anchor.y - drag.freeY) < 0.001)
    }

    @Test(arguments: [laptop, external])
    func onlyADeliberatePassEntersTheCentreLine(_ screen: CGRect) {
        let drag = Drag(on: screen)
        #expect(!drag.snapped(x: drag.home.x + 1, y: drag.freeY, speed: Drag.fast).centeredX)
        #expect(drag.snapped(x: drag.home.x + 1, y: drag.freeY, speed: Drag.fast - 1).centeredX)
    }

    @Test(arguments: [laptop, external])
    func speedDoesNotReleaseAHeldCentreLine(_ screen: CGRect) {
        let drag = Drag(on: screen)
        let fast = drag.snapped(
            x: drag.home.x + Self.snap * 2, y: drag.freeY, previous: drag.centered, speed: Drag.fast)
        #expect(fast.centeredX)
    }

    @Test(arguments: [laptop, external])
    func aFastPassOnTheCentreLineDoesNotEnterAHeightDetent(_ screen: CGRect) {
        let drag = Drag(on: screen)
        let fast = drag.snapped(
            x: drag.home.x + 1, y: drag.home.y + 1, previous: drag.centered, speed: Drag.fast)
        #expect(fast.height == nil)
    }

    @Test(arguments: [laptop, external])
    func speedDoesNotReleaseAHeldDetent(_ screen: CGRect) {
        let drag = Drag(on: screen)
        let held = PalettePlacement.Snap(anchor: drag.home, centeredX: true, height: .home)
        #expect(
            drag.snapped(x: drag.home.x + 1, y: drag.home.y + 1, previous: held, speed: Drag.fast).height
                == .home)
    }

    @Test(arguments: InterfaceSize.allCases)
    func theExpandedDetentStaysCentredOnAShiftedDisplay(_ size: InterfaceSize) {
        let shifted = CGRect(x: 300, y: 50, width: 1800, height: 1000)
        let panelHeight = size.metrics.size.panelHeight
        let top = PalettePlacement.expandedCenterY(in: shifted, expandedHeight: panelHeight)
        #expect(abs(top - panelHeight / 2 - shifted.midY) < 0.001)
    }

    // MARK: Menu panels

    @Test func theLeftMenuFollowsTheFootersLeadingCorner() {
        let frame = MenuPanel.frame(.bottomLeading)
        #expect(abs(frame.minX - (MenuPanel.parent.minX + MenuPanel.inset)) < 0.001)
        #expect(abs(frame.minY - (MenuPanel.parent.minY + MenuPanel.inset)) < 0.001)
    }

    @Test func theActionMenuFollowsTheTrailingButton() {
        let frame = MenuPanel.frame(.bottomTrailing)
        #expect(abs(frame.maxX - (MenuPanel.parent.maxX - MenuPanel.inset)) < 0.001)
        #expect(abs(frame.minY - (MenuPanel.parent.minY + MenuPanel.inset)) < 0.001)
    }

    @Test func aHeaderMenuOpensBelowTheFieldByItsTrailingControl() {
        let frame = MenuPanel.frame(.belowHeaderTrailing)
        #expect(abs(frame.maxX - (MenuPanel.parent.maxX - MenuPanel.inset * 2)) < 0.001)
        #expect(abs(frame.maxY - (MenuPanel.parent.maxY - MenuPanel.headerExtent)) < 0.001)
    }

    /// The control's frame is flipped, so the menu converts it into the parent's coordinates.
    @Test func anInputMenuFollowsItsControlInEitherAlignment() {
        let control = CGRect(x: 450, y: 100, width: 60, height: 34)
        let trailing = MenuPanel.frame(.belowControl(control))
        #expect(abs(trailing.maxX - (MenuPanel.parent.minX + control.maxX)) < 0.001)
        #expect(abs(trailing.maxY - (MenuPanel.parent.maxY - control.maxY - MenuPanel.inset)) < 0.001)
        let leading = MenuPanel.frame(.belowControl(control, trailing: false))
        #expect(abs(leading.minX - (MenuPanel.parent.minX + control.minX)) < 0.001)
        #expect(abs(leading.maxY - trailing.maxY) < 0.001)
    }

    @Test func aLowInputOpensBelowItsFieldInsideItsDisplay() {
        let frame = MenuPanel.frame(.belowControl(MenuPanel.lowControl))
        #expect(
            abs(frame.maxY - (MenuPanel.parent.maxY - 454 - MenuPanel.inset)) < 0.001,
            "even outside the palette")
        #expect(abs(frame.minX - (MenuPanel.visible.minX + MenuPanel.inset)) < 0.001)
    }

    @Test func aLowInputOpensAboveToClearTheDock() {
        let nearBottom = CGRect(x: 0, y: 0, width: 1440, height: 800)
        let frame = MenuPanel.frame(.belowControl(MenuPanel.lowControl), visibleFrame: nearBottom)
        #expect(abs(frame.minY - (MenuPanel.parent.maxY - 420 + MenuPanel.inset)) < 0.001)
    }

    @Test func aLeadingMenuClearsTheDisplaysRightEdge() {
        let control = CGRect(x: 730, y: 100, width: 100, height: 34)
        let frame = MenuPanel.frame(
            .belowControl(control, trailing: false),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(abs(frame.maxX - (1000 - MenuPanel.inset)) < 0.001)
    }

    // MARK: The tokens these rules depend on

    /// Raise it past the bar's own height and no stored position is ever restorable again.
    @Test func theMinimumVisibleSliverFitsInsideTheCompactBar() {
        #expect(Self.minimumVisible <= Self.graspable.height)
    }

    @Test func theSnapZoneIsNarrowerThanThePanel() {
        #expect(Self.snap * 2 < Self.width, "so it can't swallow every drop")
    }

    @Test func theTopMarginIsARealFractionOfTheScreen() {
        #expect(Self.topFraction > 0)
        #expect(Self.topFraction < 1)
    }

    // MARK: Every Interface Size

    @Test(arguments: InterfaceSize.allCases, [laptop, external, smallest])
    func homeCentresAndClearsTheBottomAtEverySize(_ size: InterfaceSize, _ screen: CGRect) {
        let metrics = size.metrics
        let anchor = PalettePlacement.defaultAnchor(
            in: screen, width: metrics.size.panelWidth, topMarginFraction: Self.topFraction)
        #expect(abs(anchor.x - (screen.midX - metrics.size.panelWidth / 2)) < 0.001)
        #expect(anchor.y - metrics.size.panelHeight > screen.minY)
    }

    /// The wider bar needs more of itself on screen, so a stored edge position can lapse.
    @Test(arguments: InterfaceSize.allCases)
    func theRightEdgeRulesHoldAtEverySize(_ size: InterfaceSize) {
        let graspable = CGSize(width: size.metrics.size.panelWidth, height: size.metrics.size.compactHeight)
        let sliver = CGPoint(x: Self.laptop.maxX - Self.minimumVisible, y: 900)
        let past = CGPoint(x: Self.laptop.maxX, y: 900)
        #expect(
            PalettePlacement.restored(
                sliver, graspable: graspable, visibleFrame: Self.laptop, minimumVisible: Self.minimumVisible)
                != nil)
        #expect(
            PalettePlacement.restored(
                past, graspable: graspable, visibleFrame: Self.laptop, minimumVisible: Self.minimumVisible)
                == nil)
    }

    // MARK: Fixtures

    /// A drop on `external`, 400pt from its left edge and 260pt below its top.
    static let droppedOffset = PalettePlacement.offset(
        of: CGPoint(x: external.minX + 400, y: external.maxY - 260), on: external)
    /// `external` at a lower resolution: the same top-left, shorter and narrower.
    static let rescaled = CGRect(x: 2560, y: 0, width: 1440, height: 775)

    static func home(_ screen: CGRect) -> CGPoint {
        PalettePlacement.defaultAnchor(in: screen, width: width, topMarginFraction: topFraction)
    }

    static func restored(_ stored: CGPoint, on screen: CGRect) -> CGPoint? {
        PalettePlacement.restored(
            stored, graspable: graspable, visibleFrame: screen, minimumVisible: minimumVisible)
    }

    /// The compact and expanded windows at one Interface Size.
    struct Glass {
        let outset = Theme.Size.paletteGlassOutset
        let compactSize: CGSize
        let expandedSize: CGSize

        init(_ size: InterfaceSize) {
            let metrics = size.metrics.size
            compactSize = CGSize(width: metrics.panelWidth, height: metrics.compactHeight)
            expandedSize = CGSize(width: metrics.panelWidth, height: metrics.panelHeight)
        }

        func compact(at anchor: CGPoint) -> CGRect {
            PalettePlacement.frame(at: anchor, size: compactSize, outset: outset)
        }
    }

    /// A drag on one display, with its home, its expanded detent and a height between the two.
    struct Drag {
        static let fast = PalettePlacement.maxSnapEntrySpeedPointsPerSecond + 1

        let screen: CGRect
        let home: CGPoint
        let expandedY: CGFloat
        let freeY: CGFloat
        let centered: PalettePlacement.Snap

        init(on screen: CGRect) {
            self.screen = screen
            home = PalettePlacementTests.home(screen)
            expandedY = screen.midY + PalettePlacementTests.metrics.size.panelHeight / 2
            freeY = (home.y + expandedY) / 2
            centered = PalettePlacement.Snap(
                anchor: CGPoint(x: home.x, y: freeY), centeredX: true, height: nil)
        }

        func snapped(
            x: CGFloat, y: CGFloat, previous: PalettePlacement.Snap? = nil, speed: CGFloat = 0
        ) -> PalettePlacement.Snap {
            PalettePlacement.snapped(
                CGPoint(x: x, y: y), home: home, visibleFrame: screen,
                expandedHeight: PalettePlacementTests.metrics.size.panelHeight,
                within: PalettePlacementTests.snap,
                previous: previous, speed: speed)
        }
    }

    /// A menu opened from a 750 × 475 palette on a display reaching below the origin.
    enum MenuPanel {
        static let parent = CGRect(x: 100, y: 200, width: 750, height: 475)
        static let visible = CGRect(x: 0, y: -400, width: 1440, height: 1200)
        static let content = CGSize(width: 276, height: 240)
        static let inset = PalettePlacementTests.metrics.spacing.md
        static let headerExtent =
            PalettePlacementTests.metrics.size.headerPadding
            + PalettePlacementTests.metrics.size.headerHeight
        static let lowControl = CGRect(x: 5, y: 420, width: 60, height: 34)

        static func frame(_ corner: MenuPanelCorner, visibleFrame: CGRect = visible) -> CGRect {
            corner.frame(
                contentSize: content, parentFrame: parent, visibleFrame: visibleFrame, inset: inset,
                headerExtent: headerExtent)
        }
    }
}
