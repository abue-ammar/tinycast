import CoreGraphics
import Foundation

/// Drives the real `PaletteState` arming rules, so the palette can never go back to lighting a row
/// the pointer never chose — a scroll slides rows under a still pointer, and a wheel gesture ends
/// with a mouse-moved event that has not moved anywhere.
@main
@MainActor
struct HoverArmingTests {
    static var failures = 0
    static var passes = 0

    /// Where the pointer rests for most of the cases below; nothing depends on the value.
    static let rest = CGPoint(x: 400, y: 300)

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// A palette shown with the pointer already resting over a row: disarmed, anchored there.
    static func shown() -> PaletteState {
        let state = PaletteState()
        state.disarmHoverHighlight(pointerAt: rest)
        return state
    }

    /// Moves the pointer far enough to count, which is how every armed case below gets armed.
    static func armed() -> PaletteState {
        let state = shown()
        state.notePointerMoved(to: CGPoint(x: rest.x + 40, y: rest.y))
        return state
    }

    static func main() {
        openingDisarmed()
        deliberateMovementArms()
        scrollingDisarms()
        driftDoesNotRearm()
        theDisarmTokenClearsLitRows()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Opening

    static func openingDisarmed() {
        let state = shown()
        expect(!state.hoverHighlightArmed, "a palette just shown is disarmed")
        state.notePointerMoved(to: rest)
        expect(!state.hoverHighlightArmed, "a mouse-moved event that has not moved arms nothing")
        let state2 = armed()
        state2.prepare(mode: .clipboard)
        expect(!state2.hoverHighlightArmed, "switching mode disarms the highlight again")
    }

    // MARK: - Arming

    static func deliberateMovementArms() {
        expect(armed().hoverHighlightArmed, "a pointer moved across the panel arms the highlight")

        let diagonal = shown()
        diagonal.notePointerMoved(to: CGPoint(x: rest.x + 3, y: rest.y + 3))
        expect(diagonal.hoverHighlightArmed, "movement is measured as a distance, not per axis")

        let creeping = shown()
        for step in 1...4 {
            creeping.notePointerMoved(to: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
        }
        expect(creeping.hoverHighlightArmed, "and it accumulates: the anchor holds while it moves")
    }

    // MARK: - Scrolling and keys

    static func scrollingDisarms() {
        let scrolled = armed()
        scrolled.disarmHoverHighlight(pointerAt: rest)
        expect(!scrolled.hoverHighlightArmed, "a scroll drops the highlight")

        let stillScrolling = armed()
        // Every event of the gesture re-anchors, so a hand drifting on the wheel never adds up.
        for step in 1...20 {
            stillScrolling.disarmHoverHighlight(
                pointerAt: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
            stillScrolling.notePointerMoved(to: CGPoint(x: rest.x + CGFloat(step), y: rest.y))
        }
        expect(
            !stillScrolling.hoverHighlightArmed,
            "a wheel nudging the mouse a point per click stays disarmed for the whole gesture")
    }

    static func driftDoesNotRearm() {
        let state = armed()
        state.disarmHoverHighlight(pointerAt: rest)
        // The mouse-moved AppKit delivers as the gesture ends carries the pointer it already had.
        state.notePointerMoved(to: rest)
        expect(!state.hoverHighlightArmed, "the gesture's own trailing mouse-moved re-arms nothing")
        state.notePointerMoved(to: CGPoint(x: rest.x + 2, y: rest.y + 1))
        expect(!state.hoverHighlightArmed, "nor does a hand resting on the mouse jogging it a point")
        state.notePointerMoved(to: CGPoint(x: rest.x + 12, y: rest.y))
        expect(state.hoverHighlightArmed, "a real move afterwards brings the highlight back")
    }

    // MARK: - Clearing what is already lit

    static func theDisarmTokenClearsLitRows() {
        let state = armed()
        let token = state.hoverDisarmToken
        state.disarmHoverHighlight(pointerAt: rest)
        expect(state.hoverDisarmToken != token, "disarming bumps the token that clears lit rows")

        let quiet = state.hoverDisarmToken
        state.disarmHoverHighlight(pointerAt: rest)
        state.notePointerMoved(to: rest)
        expect(
            state.hoverDisarmToken == quiet,
            "an already-disarmed palette bumps nothing, so a scroll re-renders no rows")

        state.notePointerMoved(to: CGPoint(x: rest.x + 40, y: rest.y))
        expect(
            state.hoverDisarmToken == quiet, "and arming is silent: pointer movement never rebuilds")
    }
}
