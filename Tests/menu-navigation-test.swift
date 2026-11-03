import Foundation

/// ↑/↓ walk the menu's selectable rows and wrap at either end.
@main
@MainActor
struct MenuNavigationTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        let all = { (_: Int) in true }

        expect(
            MenuRowNavigation.next(from: 0, by: 1, count: 3, isSelectable: all) == 1,
            "down steps to the next row")
        expect(
            MenuRowNavigation.next(from: 2, by: 1, count: 3, isSelectable: all) == 0,
            "down on the last row wraps to the first")
        expect(
            MenuRowNavigation.next(from: 0, by: -1, count: 3, isSelectable: all) == 2,
            "up on the first row wraps to the last")
        expect(
            MenuRowNavigation.next(from: 1, by: -1, count: 3, isSelectable: all) == 0,
            "up steps to the row above")

        let firstDisabled = { (row: Int) in row != 0 }
        expect(
            MenuRowNavigation.next(from: 1, by: -1, count: 3, isSelectable: firstDisabled) == 2,
            "wrapping skips an unselectable row at the other end")
        expect(
            MenuRowNavigation.next(from: 2, by: 1, count: 3, isSelectable: firstDisabled) == 1,
            "wrapping past the last row skips back over an unselectable first")

        let onlyMiddle = { (row: Int) in row == 1 }
        expect(
            MenuRowNavigation.next(from: 1, by: 1, count: 3, isSelectable: onlyMiddle) == 1,
            "a lone selectable row is its own neighbour")
        expect(
            MenuRowNavigation.next(from: 0, by: 1, count: 3, isSelectable: { _ in false }) == nil,
            "a menu with nothing selectable moves nowhere")

        expect(
            MenuRowNavigation.next(from: 9, by: 1, count: 3, isSelectable: all) == 0,
            "an out-of-range highlight clamps before wrapping")
        expect(
            MenuRowNavigation.next(from: 0, by: 1, count: 0, isSelectable: all) == nil,
            "an empty menu has no row to land on")
        expect(
            MenuRowNavigation.next(from: 0, by: 0, count: 3, isSelectable: all) == nil,
            "a zero step is not a move")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
