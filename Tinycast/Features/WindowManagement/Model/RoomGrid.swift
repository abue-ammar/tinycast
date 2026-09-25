// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics

/// A room's own arrangement as proportions of a 12 × 12 grid, drawn with the layouts' even gaps.
enum RoomGrid {
    static let units = 12

    struct Cell: Codable, Hashable, Sendable {
        var column: Int
        var columns: Int
        var row: Int
        var rows: Int
    }

    /// Nil when windows overlap or one is too small to place: a cascade is not a grid.
    static func cells(for frames: [CGRect], in visible: CGRect, gap: CGFloat) -> [Cell]? {
        guard !visible.isNull, !visible.isInfinite else { return nil }
        let box = RoomLayoutEngine.Area(visible: visible, gap: gap).canvas
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else {
            return nil
        }
        func snap(_ value: CGFloat, _ origin: CGFloat, _ length: CGFloat) -> Int {
            Int(max(0, min(CGFloat(units), ((value - origin) / length * CGFloat(units)).rounded())))
        }
        var cells: [Cell] = []
        for frame in frames {
            guard !frame.isNull, !frame.isInfinite, frame.minX.isFinite, frame.maxX.isFinite,
                frame.minY.isFinite, frame.maxY.isFinite
            else { return nil }
            let column = snap(frame.minX, box.minX, box.width)
            let end = snap(frame.maxX, box.minX, box.width)
            let row = snap(frame.minY, box.minY, box.height)
            let bottom = snap(frame.maxY, box.minY, box.height)
            guard end > column, bottom > row else { return nil }
            cells.append(Cell(column: column, columns: end - column, row: row, rows: bottom - row))
        }
        for i in cells.indices {
            for j in cells.indices where i < j && overlaps(cells[i], cells[j]) { return nil }
        }
        return fillingHoles(cells)
    }

    /// Grows each window into empty grid space beside it, so no hole survives loose dragging.
    static func fillingHoles(_ cells: [Cell]) -> [Cell] {
        guard isValid(cells) else { return cells }
        var cells = cells
        func isFree(_ column: Int, _ row: Int, except index: Int) -> Bool {
            guard (0..<units).contains(column), (0..<units).contains(row) else { return false }
            return !cells.indices.contains { other in
                other != index && column >= cells[other].column
                    && column < cells[other].column + cells[other].columns
                    && row >= cells[other].row && row < cells[other].row + cells[other].rows
            }
        }
        var grew = true
        while grew {
            grew = false
            for index in cells.indices {
                let cell = cells[index]
                let rows = cell.row..<(cell.row + cell.rows)
                if rows.allSatisfy({ isFree(cell.column - 1, $0, except: index) }) {
                    cells[index].column -= 1
                    cells[index].columns += 1
                    grew = true
                }
                if rows.allSatisfy({ isFree(cell.column + cell.columns, $0, except: index) }) {
                    cells[index].columns += 1
                    grew = true
                }
                // The columns just grown count too, or a corner could be taken twice.
                let columns = cells[index].column..<(cells[index].column + cells[index].columns)
                if columns.allSatisfy({ isFree($0, cell.row - 1, except: index) }) {
                    cells[index].row -= 1
                    cells[index].rows += 1
                    grew = true
                }
                if columns.allSatisfy({ isFree($0, cell.row + cell.rows, except: index) }) {
                    cells[index].rows += 1
                    grew = true
                }
            }
        }
        return cells
    }

    /// Nil for cells that are not a grid. A window that will not shrink widens its columns.
    static func frames(
        _ cells: [Cell], in visible: CGRect, gap: CGFloat, minimums: [CGSize] = []
    ) -> [CGRect]? {
        guard isValid(cells) else { return nil }
        let area = RoomLayoutEngine.Area(visible: visible, gap: gap)
        let box = area.canvas
        let gap = area.gap
        let minimums =
            minimums.count == cells.count ? minimums : Array(repeating: .zero, count: cells.count)
        let cells = fillingHoles(cells)
        var columnMinimums = [CGFloat](repeating: 0, count: units)
        var rowMinimums = columnMinimums
        for (cell, minimum) in zip(cells, minimums) {
            let perColumn = (minimum.width - gap * CGFloat(cell.columns - 1)) / CGFloat(cell.columns)
            for column in cell.column..<(cell.column + cell.columns) {
                columnMinimums[column] = max(columnMinimums[column], perColumn)
            }
            let perRow = (minimum.height - gap * CGFloat(cell.rows - 1)) / CGFloat(cell.rows)
            for row in cell.row..<(cell.row + cell.rows) {
                rowMinimums[row] = max(rowMinimums[row], perRow)
            }
        }
        let even = Array(repeating: CGFloat(1), count: units)
        let widths = RoomLayoutEngine.distribute(
            box.width, gap: gap, minimums: columnMinimums, weights: even)
        let heights = RoomLayoutEngine.distribute(
            box.height, gap: gap, minimums: rowMinimums, weights: even)
        func edge(_ sizes: [CGFloat], from start: CGFloat, at index: Int) -> CGFloat {
            start + sizes.prefix(index).reduce(0, +) + gap * CGFloat(index)
        }
        return cells.map { cell in
            let left = edge(widths, from: box.minX, at: cell.column)
            let right = edge(widths, from: box.minX, at: cell.column + cell.columns) - gap
            let top = edge(heights, from: box.minY, at: cell.row)
            let bottom = edge(heights, from: box.minY, at: cell.row + cell.rows) - gap
            return WindowPlacementEngine.rounded(
                CGRect(x: left, y: top, width: right - left, height: bottom - top))
        }
    }

    /// Inside the grid and non-empty, checked without overflow for any stored value.
    static func isValid(_ cells: [Cell]) -> Bool {
        cells.allSatisfy { cell in
            (0..<units).contains(cell.column) && (0..<units).contains(cell.row)
                && cell.columns > 0 && cell.columns <= units - cell.column
                && cell.rows > 0 && cell.rows <= units - cell.row
        }
    }

    private static func overlaps(_ lhs: Cell, _ rhs: Cell) -> Bool {
        lhs.column < rhs.column + rhs.columns && rhs.column < lhs.column + lhs.columns
            && lhs.row < rhs.row + rhs.rows && rhs.row < lhs.row + lhs.rows
    }
}
