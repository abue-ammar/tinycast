// Standalone test for shift-extended clipboard selections, compiling the real source.
import Foundation

@main
@MainActor
struct ClipboardSelectionTests {
    static var failures = 0
    static var passes = 0

    static let pinned = ClipboardItem(text: "pinned", sourceBundleID: nil)
    static let newest = ClipboardItem(text: "newest", sourceBundleID: nil)
    static let middle = ClipboardItem(text: "middle", sourceBundleID: nil)
    static let oldest = ClipboardItem(text: "oldest", sourceBundleID: nil)
    static let rows = [pinned, newest, middle, oldest]

    static func main() {
        firstExtensionAnchorsOnTheHighlightedRow()
        extendsBothWaysFromTheSameAnchor()
        repeatedExtensionKeepsTheAnchor()
        selectedRowsFollowVisibleOrder()
        oneRowIsNotAMultiSelection()
        deletedAnchorFallsBackToTheHighlightedRow()
        clearForgetsEverything()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func firstExtensionAnchorsOnTheHighlightedRow() {
        var selection = ClipboardSelection()
        selection.extend(to: 3, from: 1, rows: rows)
        expect(
            selected(selection, in: rows) == ids([newest, middle, oldest]),
            "the first ⇧ extends from the highlighted row to the clicked one")
        expect(selection.isMultiple, "three rows are a multi-selection")
    }

    static func extendsBothWaysFromTheSameAnchor() {
        var selection = ClipboardSelection()
        selection.extend(to: 3, from: 1, rows: rows)
        selection.extend(to: 0, from: 3, rows: rows)
        expect(
            selected(selection, in: rows) == ids([pinned, newest]),
            "a second ⇧ extends from the original anchor, not the row last reached")
    }

    static func repeatedExtensionKeepsTheAnchor() {
        var selection = ClipboardSelection()
        selection.extend(to: 3, from: 1, rows: rows)
        selection.extend(to: 2, from: 3, rows: rows)
        expect(
            selected(selection, in: rows) == ids([newest, middle]),
            "⇧↑ narrows the same range back towards the anchor")
    }

    static func selectedRowsFollowVisibleOrder() {
        var selection = ClipboardSelection()
        selection.extend(to: 3, from: 0, rows: rows)
        expect(
            selected(selection, in: rows) == ids(rows),
            "a paste follows the list top to bottom, pinned rows included")
    }

    static func oneRowIsNotAMultiSelection() {
        var selection = ClipboardSelection()
        selection.extend(to: 2, from: 2, rows: rows)
        expect(
            selected(selection, in: rows).isEmpty,
            "a ⇧ on the anchor row leaves the normal single action")
        expect(!selection.isMultiple, "one row is never a multi-selection")
    }

    static func deletedAnchorFallsBackToTheHighlightedRow() {
        let remaining = rows.filter { $0.id != newest.id }
        var selection = ClipboardSelection()
        selection.extend(to: 1, from: 1, rows: rows)
        selection.extend(to: 2, from: 0, rows: remaining)
        expect(
            selected(selection, in: remaining) == ids(remaining),
            "an anchor deleted mid-selection re-anchors on the highlighted row")
    }

    static func clearForgetsEverything() {
        var selection = ClipboardSelection()
        selection.extend(to: 3, from: 1, rows: rows)
        selection.clear()
        expect(selected(selection, in: rows).isEmpty, "clearing drops every selected row")
        selection.extend(to: 2, from: 0, rows: rows)
        expect(
            selected(selection, in: rows) == ids([pinned, newest, middle]),
            "after clearing, the next ⇧ anchors on the highlighted row again")
    }

    static func selected(_ selection: ClipboardSelection, in rows: [ClipboardItem]) -> [UUID] {
        selection.items(in: rows).map(\.id)
    }

    static func ids(_ items: [ClipboardItem]) -> [UUID] { items.map(\.id) }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(label)")
        }
    }
}
