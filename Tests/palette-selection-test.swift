import Foundation

@main
@MainActor
struct PaletteRowIndexTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: PaletteRow?, _ expected: PaletteRow?, _ message: String) {
        expect(
            actual == expected,
            "\(message) — got \(String(describing: actual)), want \(String(describing: expected))")
    }

    static func expect(_ actual: Int?, _ expected: Int?, _ message: String) {
        expect(
            actual == expected,
            "\(message) — got \(String(describing: actual)), want \(String(describing: expected))")
    }

    /// Where a flat index lands in the rendered grid: its visual row, and its column of that row.
    static func cell(_ flat: Int, counts: [Int], columns: Int) -> (row: Int, column: Int) {
        var row = 0
        var start = 0
        for count in counts {
            if flat < start + count {
                let local = flat - start
                return (row + local / columns, local % columns)
            }
            row += (count + columns - 1) / columns
            start += count
        }
        return (row, 0)
    }

    /// How many cells a visual row holds — the last row of a section is usually a partial one.
    static func rowLength(_ row: Int, counts: [Int], columns: Int) -> Int {
        var first = 0
        for count in counts {
            let rows = (count + columns - 1) / columns
            if row < first + rows { return min(count - (row - first) * columns, columns) }
            first += rows
        }
        return 0
    }

    /// The emoji screen's contract: a grid move walks one visual row of the same flat row order.
    static func expectGrid(_ counts: [Int], columns: Int, _ label: String) {
        let grid = EmojiGridGeometry(counts: counts, columns: columns)
        let index = PaletteRowIndex(sectionCounts: counts)
        let lastRow = counts.reduce(0) { $0 + ($1 + columns - 1) / columns } - 1
        for flat in 0..<index.count {
            let here = cell(flat, counts: counts, columns: columns)
            let down = grid.down(from: flat)
            let up = grid.up(from: flat)
            expect(index.row(at: down) != nil, "\(label): down from \(flat) stays on a row")
            expect(index.row(at: up) != nil, "\(label): up from \(flat) stays on a row")
            expect(down >= flat, "\(label): down from \(flat) never moves backwards")
            expect(up <= flat, "\(label): up from \(flat) never moves forwards")
            let below = cell(down, counts: counts, columns: columns)
            let above = cell(up, counts: counts, columns: columns)
            // The column is kept, except onto a shorter row, which clamps to its last cell.
            let lastBelow = rowLength(here.row + 1, counts: counts, columns: columns) - 1
            let lastAbove = rowLength(here.row - 1, counts: counts, columns: columns) - 1
            expect(
                down == flat || below.column == min(here.column, lastBelow),
                "\(label): down from \(flat) keeps its column, clamping onto a shorter row")
            expect(
                up == flat || above.column == min(here.column, lastAbove),
                "\(label): up from \(flat) keeps its column, clamping onto a shorter row")
            expect(
                down == flat ? here.row == lastRow : below.row == here.row + 1,
                "\(label): down from \(flat) moves exactly one visual row, or stops at the last")
            expect(
                up == flat ? here.row == 0 : above.row == here.row - 1,
                "\(label): up from \(flat) moves exactly one visual row, or stops at the first")
            // ←/→ are a plain step through the same flat order, clamped at both ends.
            expect(
                index.clamped(flat + 1) == min(flat + 1, index.count - 1),
                "\(label): → steps one cell from \(flat)")
            expect(
                index.clamped(flat - 1) == max(flat - 1, 0), "\(label): ← steps one cell from \(flat)")
        }
    }

    /// Every index resolves, and resolving then inverting returns the index it started from.
    static func expectRoundTrip(_ index: PaletteRowIndex, _ label: String) {
        for flat in 0..<index.count {
            guard let row = index.row(at: flat) else {
                expect(false, "\(label): index \(flat) resolves to a row")
                continue
            }
            switch row {
            case .calculator:
                expect(flat == 0, "\(label): the calculator card only ever sits at index 0")
            case .element(let section, let offset):
                expect(
                    index.index(section: section, offset: offset), flat,
                    "\(label): section \(section) offset \(offset) inverts to \(flat)")
            }
        }
    }

    static func main() {
        // Empty list: nothing resolves and the clamp still yields a usable selection.
        let empty = PaletteRowIndex(sectionCounts: [])
        expect(empty.count == 0, "an empty screen has no rows")
        expect(empty.row(at: 0), nil, "an empty screen resolves no index")
        expect(empty.clamped(0) == 0, "the clamp holds at zero with no rows")
        expect(empty.clamped(7) == 0, "an out-of-range selection clamps to zero with no rows")
        expect(empty.index(section: 0, offset: 0), nil, "an empty screen has no section 0")

        // A screen whose sections are all empty is still an empty screen.
        let allEmptySections = PaletteRowIndex(sectionCounts: [0, 0, 0])
        expect(allEmptySections.count == 0, "empty sections contribute no rows")
        expect(allEmptySections.row(at: 0), nil, "empty sections resolve no index")

        // Single section, no calculator card: the flat index is the section offset.
        let single = PaletteRowIndex(sectionCounts: [3])
        expect(single.count == 3, "one section of 3 is 3 rows")
        expect(single.row(at: 0), .element(section: 0, offset: 0), "index 0 is the first result")
        expect(single.row(at: 1), .element(section: 0, offset: 1), "index 1 is the second result")
        expect(single.row(at: 2), .element(section: 0, offset: 2), "index 2 is the last result")
        expect(single.row(at: 3), nil, "one past the end resolves to nothing")
        expect(single.row(at: -1), nil, "a negative index resolves to nothing")
        expectRoundTrip(single, "single section")

        // The calculator card takes index 0 and shifts every result down by one.
        let withCalc = PaletteRowIndex(hasCalculator: true, sectionCounts: [3])
        expect(withCalc.count == 4, "the calculator card adds one row")
        expect(withCalc.row(at: 0), .calculator, "the calculator card occupies index 0")
        expect(
            withCalc.row(at: 1), .element(section: 0, offset: 0),
            "the first result follows the calculator card")
        expect(
            withCalc.row(at: 3), .element(section: 0, offset: 2),
            "the last result sits at count - 1")
        expect(withCalc.row(at: 4), nil, "one past the end resolves to nothing")
        expect(
            withCalc.index(section: 0, offset: 0), 1,
            "a card present shifts the first result's index to 1")
        expectRoundTrip(withCalc, "single section with calculator")

        // A calculator card with no results is selectable on its own.
        let calcOnly = PaletteRowIndex(hasCalculator: true, sectionCounts: [])
        expect(calcOnly.count == 1, "a lone calculator card is one row")
        expect(calcOnly.row(at: 0), .calculator, "a lone calculator card is the whole list")
        expect(calcOnly.clamped(9) == 0, "the clamp lands on the card")

        // Multiple sections: headers are not selectable, so no index is spent on them.
        let sections = PaletteRowIndex(sectionCounts: [2, 1, 3])
        expect(sections.count == 6, "three sections of 2, 1 and 3 are 6 selectable rows")
        expect(sections.row(at: 1), .element(section: 0, offset: 1), "the first section's last row")
        expect(
            sections.row(at: 2), .element(section: 1, offset: 0),
            "the next index crosses into the second section, skipping its header")
        expect(
            sections.row(at: 3), .element(section: 2, offset: 0),
            "a one-row section is crossed in a single step")
        expect(sections.row(at: 5), .element(section: 2, offset: 2), "the final row of the last section")
        expect(sections.row(at: 6), nil, "one past the last section resolves to nothing")
        expectRoundTrip(sections, "three sections")

        // An empty section in the middle is skipped entirely rather than consuming an index.
        let gapped = PaletteRowIndex(sectionCounts: [2, 0, 2])
        expect(gapped.count == 4, "an empty section contributes no rows")
        expect(
            gapped.row(at: 2), .element(section: 2, offset: 0),
            "an empty section is stepped over, not landed in")
        expect(gapped.index(section: 1, offset: 0), nil, "an empty section has no valid offset")
        expectRoundTrip(gapped, "empty middle section")

        // Sections plus the calculator card — the launcher's real shape.
        let launcher = PaletteRowIndex(hasCalculator: true, sectionCounts: [2, 1, 3])
        expect(launcher.count == 7, "the card plus six results")
        expect(launcher.row(at: 0), .calculator, "the card still leads")
        expect(
            launcher.row(at: 3), .element(section: 1, offset: 0),
            "a section crossing accounts for the card")
        expect(
            launcher.index(section: 2, offset: 2), 6,
            "the last row of the last section is the last index")
        expectRoundTrip(launcher, "launcher shape")

        // The empty-query launcher: favourites, then one section per kind in AppIndex slice order.
        let launcherSections = PaletteRowIndex(sectionCounts: [3, 12, 5, 2, 4, 6, 8, 1, 7])
        expect(launcherSections.sectionCounts.count == 9, "the empty-query launcher has nine sections")
        expect(launcherSections.count == 48, "every section's rows are selectable, its header is not")
        expect(
            launcherSections.row(at: 0), .element(section: 0, offset: 0),
            "a pinned favourite is the first row of the whole list")
        expect(
            launcherSections.row(at: 2), .element(section: 0, offset: 2),
            "the last favourite still precedes Applications")
        expect(
            launcherSections.row(at: 3), .element(section: 1, offset: 0),
            "Applications begins where Favorites ends, with no index spent on the header")
        expect(launcherSections.index(section: 8, offset: 6), 47, "the last command is the last index")
        expect(launcherSections.index(section: 9, offset: 0), nil, "there is no tenth section")
        expectRoundTrip(launcherSections, "launcher nine sections")

        // No favourites set: Applications leads, and every later section shifts up by the same amount.
        let launcherNoFavorites = PaletteRowIndex(sectionCounts: [0, 12, 5, 2, 4, 6, 8, 1, 7])
        expect(
            launcherNoFavorites.row(at: 0), .element(section: 1, offset: 0),
            "an empty Favorites section is stepped over, not landed in")
        expect(
            launcherNoFavorites.index(section: 8, offset: 6), 44,
            "dropping three favourites moves every later row up by three")
        expectRoundTrip(launcherNoFavorites, "launcher without favourites")

        // Hidden categories drop whole sections; the rows that remain keep their order.
        let launcherHidden = PaletteRowIndex(sectionCounts: [3, 12, 0, 2, 0, 6, 0, 1, 7])
        expect(launcherHidden.count == 31, "a hidden category contributes no rows")
        expect(
            launcherHidden.row(at: 15), .element(section: 3, offset: 0),
            "Quicklinks follows Applications directly once System Settings is hidden")
        expectRoundTrip(launcherHidden, "launcher with hidden categories")

        // A typed query collapses the nine sections into one Results list, led by the calculator card.
        let launcherQuery = PaletteRowIndex(hasCalculator: true, sectionCounts: [9])
        expect(launcherQuery.count == 10, "the card plus nine ranked matches")
        expect(launcherQuery.row(at: 0), .calculator, "a typed calculation leads the results")
        expect(
            launcherQuery.row(at: 1), .element(section: 0, offset: 0),
            "the best-ranked match follows the card")
        expect(launcherQuery.index(section: 0, offset: 8), 9, "the last match is the last index")
        expectRoundTrip(launcherQuery, "launcher with a card")

        // ↵, ⌘↵ and ⌃⇧Q resolve through this index, so only index 0 is ever the card.
        for flat in 0..<launcherQuery.count {
            expect(
                (launcherQuery.row(at: flat) == .calculator) == (flat == 0),
                "launcher: index \(flat) is the card only at 0")
        }

        // A calculation matching no app at all: the card is the only selectable row.
        let launcherCardOnly = PaletteRowIndex(hasCalculator: true, sectionCounts: [0])
        expect(launcherCardOnly.count == 1, "a card with no matches is one row")
        expect(launcherCardOnly.row(at: 0), .calculator, "the card is the whole list")
        expect(launcherCardOnly.clamped(6) == 0, "a stale selection clamps back onto the card")

        // Each of the nine sections, alone and absent, with and without the card.
        for hasCalculator in [false, true] {
            for section in 0..<9 {
                var only = [Int](repeating: 0, count: 9)
                only[section] = 3
                let alone = PaletteRowIndex(hasCalculator: hasCalculator, sectionCounts: only)
                expect(
                    alone.index(section: section, offset: 0), hasCalculator ? 1 : 0,
                    "section \(section) alone starts at the head of the list")
                expectRoundTrip(alone, "only section \(section) calc=\(hasCalculator)")
                var missing = [Int](repeating: 2, count: 9)
                missing[section] = 0
                let gapped = PaletteRowIndex(hasCalculator: hasCalculator, sectionCounts: missing)
                expect(
                    gapped.count == (hasCalculator ? 1 : 0) + 16,
                    "hiding section \(section) drops exactly its rows")
                expect(gapped.index(section: section, offset: 0), nil, "section \(section) has no rows")
                expectRoundTrip(gapped, "section \(section) hidden calc=\(hasCalculator)")
            }
        }

        // Clamping at both ends, with and without a card.
        for index in [single, withCalc, sections, launcher, gapped] {
            expect(index.clamped(-1) == 0, "a selection below zero clamps to the first row")
            expect(index.clamped(-99) == 0, "a far-negative selection clamps to the first row")
            expect(
                index.clamped(index.count) == index.count - 1,
                "a selection one past the end clamps to the last row")
            expect(
                index.clamped(index.count + 50) == index.count - 1,
                "a far-past-the-end selection clamps to the last row")
            expect(
                index.row(at: index.clamped(Int.max)) != nil,
                "a clamped selection always resolves to a row")
            expect(
                index.row(at: index.clamped(Int.min)) != nil,
                "a clamped negative selection always resolves to a row")
        }

        // Out-of-bounds inversion never invents an index.
        expect(sections.index(section: 3, offset: 0), nil, "there is no fourth section")
        expect(sections.index(section: -1, offset: 0), nil, "there is no section before the first")
        expect(sections.index(section: 0, offset: 2), nil, "an offset past a section's rows is nothing")
        expect(sections.index(section: 0, offset: -1), nil, "a negative offset is nothing")

        // The uninstall screen: one flat section, no calculator card, a summary header taking no index.
        let uninstall = PaletteRowIndex(sectionCounts: [4])
        expect(uninstall.count == 4, "the uninstall screen indexes its candidates alone")
        expect(uninstall.row(at: 0), .element(section: 0, offset: 0), "the first candidate leads")
        expect(
            uninstall.row(at: 3), .element(section: 0, offset: 3),
            "the summary header consumes no index")
        expect(uninstall.row(at: 4), nil, "one past the last candidate resolves to nothing")
        expectRoundTrip(uninstall, "uninstall shape")

        // Filtering down to a single candidate keeps the highlight on it rather than off the end.
        let uninstallFiltered = PaletteRowIndex(sectionCounts: [1])
        expect(uninstallFiltered.clamped(3) == 0, "a filter that leaves one row pulls selection to it")

        // An options-bearing argument: its choices are the rows, exactly like any other list.
        let argumentOptions = PaletteRowIndex(sectionCounts: [3])
        expect(argumentOptions.count == 3, "the choice list is the argument form's only section")
        expect(
            argumentOptions.row(at: 2), .element(section: 0, offset: 2), "the last choice is selectable")
        expectRoundTrip(argumentOptions, "argument options shape")

        // A free-text argument renders no rows at all, and selection must still hold at zero.
        let argumentFreeText = PaletteRowIndex(sectionCounts: [0])
        expect(argumentFreeText.count == 0, "a free-text argument has nothing to index")
        expect(argumentFreeText.row(at: 0), nil, "a free-text argument resolves no index")
        expect(argumentFreeText.clamped(0) == 0, "selection stays at zero with no choices")
        expect(argumentFreeText.clamped(5) == 0, "a stale selection clamps back to zero")

        // The clipboard screen: a Pinned section above the date buckets, and no calculator card.
        let clipboard = PaletteRowIndex(sectionCounts: [2, 5, 3])
        expect(clipboard.count == 10, "the clipboard indexes pinned and dated entries alike")
        expect(clipboard.row(at: 1), .element(section: 0, offset: 1), "the last pinned entry")
        expect(
            clipboard.row(at: 2), .element(section: 1, offset: 0),
            "the first dated entry follows the Pinned section")
        expect(
            clipboard.index(section: 0, offset: 0), 0,
            "pinning lifts a row to the head of the whole list")
        expectRoundTrip(clipboard, "clipboard shape")

        // Calculator History: the live answer card, then one section per date bucket.
        let historyCard = PaletteRowIndex(hasCalculator: true, sectionCounts: [3, 2])
        expect(historyCard.count == 6, "the card plus five stored entries")
        expect(historyCard.row(at: 0), .calculator, "a typed calculation leads the history")
        expect(
            historyCard.row(at: 1), .element(section: 0, offset: 0),
            "the newest stored entry follows the card")
        expect(
            historyCard.row(at: 4), .element(section: 1, offset: 0),
            "crossing into the next bucket accounts for the card")
        expect(historyCard.index(section: 1, offset: 1), 5, "the oldest entry is the last index")
        expectRoundTrip(historyCard, "history with a card")

        // ⌘⌫ resolves through this index, so only an `.element` is ever a deletion target.
        for flat in 0..<historyCard.count {
            expect(
                (historyCard.row(at: flat) == .calculator) == (flat == 0),
                "history: index \(flat) is the card only at 0")
        }

        // Clearing the field drops the card, and index 0 becomes the newest stored entry.
        let historyNoCard = PaletteRowIndex(sectionCounts: [3, 2])
        expect(historyNoCard.count == 5, "without a card the stored entries are the whole list")
        expect(historyNoCard.row(at: 0), .element(section: 0, offset: 0), "the newest entry leads")
        expectRoundTrip(historyNoCard, "history without a card")

        // A calculation typed with no history yet: the card is the only selectable row.
        let historyCardOnly = PaletteRowIndex(hasCalculator: true, sectionCounts: [0])
        expect(historyCardOnly.count == 1, "a card with no stored entries is one row")
        expect(historyCardOnly.row(at: 0), .calculator, "the card is the whole list")
        expect(historyCardOnly.row(at: 1), nil, "nothing follows a lone card")
        expect(historyCardOnly.clamped(4) == 0, "a stale selection clamps back onto the card")

        // The emoji grid: sections of 8, 20 and 5 cells over 8 columns, as the picker renders them.
        let emoji = PaletteRowIndex(sectionCounts: [8, 20, 5])
        expect(emoji.count == 33, "the grid indexes every cell of every section")
        expect(
            emoji.row(at: 8), .element(section: 1, offset: 0),
            "the flat index crosses into the next section's first cell")
        expectRoundTrip(emoji, "emoji grid shape")
        let emojiGrid = EmojiGridGeometry(counts: [8, 20, 5], columns: 8)
        expect(
            emojiGrid.down(from: 3), 8 + 3,
            "down from the last row of a section lands in the same column of the next")
        expect(
            emojiGrid.up(from: 8 + 3), 3,
            "up from a section's first row lands in the same column of the previous")
        expect(emojiGrid.down(from: 8 + 16 + 3), 28 + 3, "the third section is entered by column")
        expect(emojiGrid.up(from: 28 + 3), 8 + 16 + 3, "and left again by the same column")
        // `EmojiGrid.sections` skips an empty category, so no shape here carries an empty section.
        expectGrid([8, 20, 5], columns: 8, "emoji grid")
        expectGrid([33], columns: 8, "emoji search results")
        expectGrid([1], columns: 8, "a single emoji result")

        // Exhaustive: every grid shape moves by one visual row and stays inside the flat order.
        for a in 1...9 {
            for b in 1...9 {
                for c in 1...9 {
                    expectGrid([a, b, c], columns: 8, "grid [\(a),\(b),\(c)]")
                }
            }
        }

        // Exhaustive: over a spread of shapes, every flat index maps 1:1 onto visible row order.
        for hasCalculator in [false, true] {
            for a in 0...3 {
                for b in 0...3 {
                    for c in 0...3 {
                        let index = PaletteRowIndex(
                            hasCalculator: hasCalculator, sectionCounts: [a, b, c])
                        let label = "shape calc=\(hasCalculator) [\(a),\(b),\(c)]"
                        expect(
                            index.count == (hasCalculator ? 1 : 0) + a + b + c,
                            "\(label): the row count is the card plus every section")
                        expectRoundTrip(index, label)
                        let rows = (0..<index.count).compactMap(index.row(at:))
                        expect(
                            Set(rows.map(String.init(describing:))).count == rows.count,
                            "\(label): no two indices resolve to the same row")
                    }
                }
            }
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
