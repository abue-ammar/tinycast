import Testing

@testable import Tinycast

/// The emoji screen's contract: a grid move walks one visual row of the same flat row order.
extension PaletteSelectionTests {
    /// Sections over columns as the picker renders them: each section starts a fresh visual row.
    struct Grid: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let counts: [Int]
        var columns = 8

        var geometry: EmojiGridGeometry { EmojiGridGeometry(counts: counts, columns: columns) }
        var index: PaletteRowIndex { PaletteRowIndex(sectionCounts: counts) }
        var lastRow: Int { counts.reduce(0) { $0 + rows(in: $1) } - 1 }

        /// Where a flat index lands: its visual row, and its column of that row.
        func cell(_ flat: Int) -> (row: Int, column: Int) {
            var row = 0
            var start = 0
            for count in counts {
                if flat < start + count { return (row + (flat - start) / columns, (flat - start) % columns) }
                row += rows(in: count)
                start += count
            }
            return (row, 0)
        }

        /// How many cells a visual row holds: the last row of a section is usually a partial one.
        func length(ofRow row: Int) -> Int {
            var first = 0
            for count in counts {
                if row < first + rows(in: count) { return min(count - (row - first) * columns, columns) }
                first += rows(in: count)
            }
            return 0
        }

        private func rows(in count: Int) -> Int { (count + columns - 1) / columns }
    }

    /// `EmojiGrid.sections` skips an empty category, so no shape here carries an empty section.
    static let grids =
        [
            Grid(testDescription: "the emoji grid", counts: [8, 20, 5]),
            Grid(testDescription: "emoji search results", counts: [33]),
            Grid(testDescription: "a single emoji result", counts: [1])
        ]
        + (1...9).flatMap { a in
            (1...9).flatMap { b in
                (1...9).map { c in Grid(testDescription: "[\(a), \(b), \(c)]", counts: [a, b, c]) }
            }
        }

    @Test func verticalMovesCrossSectionsByColumn() {
        let grid = EmojiGridGeometry(counts: [8, 20, 5], columns: 8)
        #expect(grid.down(from: 3) == 8 + 3, "from a section's last row into the same column of the next")
        #expect(grid.up(from: 8 + 3) == 3, "from a section's first row into the same column of the previous")
        #expect(grid.down(from: 8 + 16 + 3) == 28 + 3, "the third section is entered by column")
        #expect(grid.up(from: 28 + 3) == 8 + 16 + 3, "and left again by the same column")
    }

    @Test(arguments: grids)
    func aVerticalMoveStaysOnARow(_ grid: Grid) {
        for flat in 0..<grid.index.count {
            #expect(grid.index.row(at: grid.geometry.down(from: flat)) != nil, "down from \(flat)")
            #expect(grid.index.row(at: grid.geometry.up(from: flat)) != nil, "up from \(flat)")
        }
    }

    @Test(arguments: grids)
    func aVerticalMoveNeverReversesTheFlatOrder(_ grid: Grid) {
        for flat in 0..<grid.index.count {
            #expect(grid.geometry.down(from: flat) >= flat, "down from \(flat)")
            #expect(grid.geometry.up(from: flat) <= flat, "up from \(flat)")
        }
    }

    /// The column is kept, except onto a shorter row, which clamps to its last cell.
    @Test(arguments: grids)
    func aVerticalMoveKeepsItsColumn(_ grid: Grid) {
        for flat in 0..<grid.index.count {
            let here = grid.cell(flat)
            let down = grid.geometry.down(from: flat)
            let up = grid.geometry.up(from: flat)
            let lastBelow = grid.length(ofRow: here.row + 1) - 1
            let lastAbove = grid.length(ofRow: here.row - 1) - 1
            #expect(
                down == flat || grid.cell(down).column == min(here.column, lastBelow), "down from \(flat)")
            #expect(up == flat || grid.cell(up).column == min(here.column, lastAbove), "up from \(flat)")
        }
    }

    @Test(arguments: grids)
    func aVerticalMoveStepsExactlyOneVisualRowOrStopsAtTheEnd(_ grid: Grid) {
        for flat in 0..<grid.index.count {
            let here = grid.cell(flat)
            let down = grid.geometry.down(from: flat)
            let up = grid.geometry.up(from: flat)
            #expect(
                down == flat ? here.row == grid.lastRow : grid.cell(down).row == here.row + 1,
                "down from \(flat)")
            #expect(up == flat ? here.row == 0 : grid.cell(up).row == here.row - 1, "up from \(flat)")
        }
    }

    /// ←/→ are a plain step through the same flat order, clamped at both ends.
    @Test(arguments: grids)
    func aHorizontalMoveStepsOneCell(_ grid: Grid) {
        let index = grid.index
        for flat in 0..<index.count {
            #expect(index.clamped(flat + 1) == min(flat + 1, index.count - 1), "→ from \(flat)")
            #expect(index.clamped(flat - 1) == max(flat - 1, 0), "← from \(flat)")
        }
    }
}
