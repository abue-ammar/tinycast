import CoreGraphics
import Foundation

/// Drives `PalettePlacement` against the real `Theme` (compiled in, not copied), so retuning a token
/// can't leave the palette restoring to a position no display still shows.
@main
@MainActor
struct PalettePlacementTests {
    static var failures = 0
    static var passes = 0

    // Exactly what `PaletteWindowController` passes.
    static let width = Theme.Size.panelWidth
    static let graspable = CGSize(width: width, height: Theme.Size.compactHeight)
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

    static func restored(_ stored: CGPoint, screens: [CGRect]) -> CGPoint? {
        PalettePlacement.restored(
            stored, graspable: graspable, visibleFrames: screens, minimumVisible: minimumVisible)
    }

    static func main() {
        theDefaultPlacement()
        restoringAcrossDisplays()
        restoringPartlyOffscreen()
        snapping()
        tokenGrammar()

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
            anchor.y - Theme.Size.panelHeight > laptop.minY,
            "an expanded palette clears the bottom of the screen it opened on")

        // A screen offset from the origin must not shift the panel off it.
        let offset = home(external)
        expect(offset.x, external.midX - width / 2, "a non-origin display centres the same way")
        expect(
            offset.y, external.maxY - external.height * topFraction,
            "and its top edge is measured from its own maxY")
    }

    // MARK: - Restoring a stored position

    static func restoringAcrossDisplays() {
        let onExternal = CGPoint(x: 2700, y: 900)
        expect(
            restored(onExternal, screens: [laptop, external]) == onExternal,
            "a position on a connected display comes back verbatim")
        expect(
            restored(onExternal, screens: [laptop]) == nil,
            "the same position is dropped once that display is unplugged")

        // The fallback has to be reachable, not merely different.
        expect(
            restored(home(laptop), screens: [laptop]) != nil,
            "the default placement is always restorable on its own screen")
        expect(
            restored(CGPoint(x: -4000, y: 9000), screens: [laptop, external]) == nil,
            "a position on no display at all is dropped")
    }

    static func restoringPartlyOffscreen() {
        // Deliberately slid off to the right: still restorable while a grabbable sliver shows.
        let sliver = CGPoint(x: laptop.maxX - minimumVisible, y: 900)
        expect(
            restored(sliver, screens: [laptop]) != nil,
            "exactly the minimum sliver of the compact bar is still grabbable")
        let tooFar = CGPoint(x: laptop.maxX - minimumVisible + 1, y: 900)
        expect(
            restored(tooFar, screens: [laptop]) == nil,
            "one point less than that is not, and falls back to the default")

        // Slid off the top, where the whole grab strip is what goes missing first.
        let peeking = CGPoint(x: 800, y: laptop.maxY + graspable.height - minimumVisible)
        expect(
            restored(peeking, screens: [laptop]) != nil,
            "a bar hanging off the top edge is grabbable while the minimum still shows")
        let gone = CGPoint(x: 800, y: laptop.maxY + graspable.height - minimumVisible + 1)
        expect(
            restored(gone, screens: [laptop]) == nil,
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
}
