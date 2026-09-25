// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics

/// Every frame a room layout produces, in AX space. See docs/features/window-rooms.md#layouts.
enum RoomLayoutEngine {
    /// Below this a tiled window stops being pleasant to work in.
    static let comfortable = CGSize(width: 480, height: 360)
    /// The least a tidy layout gives a window, so an unknown minimum is never squeezed to nothing.
    static let usable = CGSize(width: 320, height: 240)
    /// How much of each stacked window's title bar stays in view.
    static let peek: CGFloat = 32

    /// The box windows tile inside, and the one gap every layout uses, both sanitized once.
    struct Area {
        let canvas: CGRect
        let gap: CGFloat

        init(visible: CGRect, gap: CGFloat) {
            self.gap = WindowPlacementEngine.sanitizedGap(gap, in: visible)
            canvas = WindowPlacementEngine.canvas(visible, gap: self.gap)
        }
    }

    /// `minimums` holds one size per window, or none; no app is asked to go below its own.
    static func frames(
        count: Int, kind: RoomLayoutKind, in visible: CGRect, gap: CGFloat,
        minimums: [CGSize] = []
    ) -> [CGRect] {
        guard count > 0 else { return [] }
        let area = Area(visible: visible, gap: gap)
        let minimums = padded(minimums, to: count)
        switch kind {
        // The room's own record resolves `.custom` and `.saved`; here they mean Auto.
        case .auto, .custom, .saved:
            let tidy = autoKind(count: count, in: visible, gap: gap, minimums: minimums)
            return frames(count: count, kind: tidy, in: visible, gap: gap, minimums: minimums)
        case .stack:
            return stack(count, in: area, minimums: minimums).map {
                WindowPlacementEngine.clamped($0, into: area.canvas)
            }
        case .focus, .columns, .grid:
            let candidates = arrangements(count, kind: kind, in: area, minimums: minimums)
            // Overlap beats off-screen: the least spilling candidate is pulled back on screen.
            let best =
                candidates.first { works($0, in: area.canvas) }
                ?? candidates.min { overflow($0, in: area.canvas) < overflow($1, in: area.canvas) }
                ?? []
            return best.map { WindowPlacementEngine.clamped($0, into: area.canvas) }
        }
    }

    /// Whether `kind` places every window without overlap. Stack overlaps on purpose, so it fits.
    static func fits(
        count: Int, kind: RoomLayoutKind, in visible: CGRect, gap: CGFloat,
        minimums: [CGSize] = []
    ) -> Bool {
        guard count > 0 else { return false }
        switch kind {
        case .auto, .stack, .custom, .saved:
            return true
        case .focus, .columns, .grid:
            let area = Area(visible: visible, gap: gap)
            return arrangements(
                count, kind: kind, in: area, minimums: padded(minimums, to: count)
            ).contains { works($0, in: area.canvas) }
        }
    }

    /// What Auto means here: the first tidy layout where every side window is comfortable.
    static func autoKind(
        count: Int, in visible: CGRect, gap: CGFloat, minimums: [CGSize] = []
    ) -> RoomLayoutKind {
        guard count > 1 else { return .focus }
        let area = Area(visible: visible, gap: gap)
        let minimums = padded(minimums, to: count)
        let order: [RoomLayoutKind] = count <= 4 ? [.focus, .columns, .grid] : [.grid, .columns, .focus]
        for kind in order {
            // Judged before any clamp, and Columns means one row: wrapping is what Grid is for.
            let options = arrangements(count, kind: kind, in: area, minimums: minimums).filter {
                kind != .columns || Set($0.map(\.minY)).count == 1
            }
            guard let fit = options.first(where: { works($0, in: area.canvas) }) else { continue }
            let roomy = fit.dropFirst().allSatisfy {
                $0.width >= comfortable.width - 1 && $0.height >= comfortable.height - 1
            }
            if roomy { return kind }
        }
        return .stack
    }

    /// Inside the box and overlapping nothing: a layout that can be used as it is.
    static func isClean(_ rects: [CGRect], in box: CGRect) -> Bool {
        guard overflow(rects, in: box) < 1 else { return false }
        for i in rects.indices {
            for j in rects.indices where i < j {
                let shared = rects[i].intersection(rects[j])
                if !shared.isNull, shared.width > 1, shared.height > 1 { return false }
            }
        }
        return true
    }

    /// Splits `total` by `weights` in whole points, never below `minimums`, which may overflow.
    static func distribute(
        _ total: CGFloat, gap: CGFloat, minimums: [CGFloat], weights: [CGFloat]
    ) -> [CGFloat] {
        let count = minimums.count
        guard count > 0 else { return [] }
        let available = total - gap * CGFloat(count - 1)
        var fixed = Array(repeating: false, count: count)
        var sizes = Array(repeating: CGFloat(0), count: count)
        while true {
            let flexibleWeight = (0..<count).filter { !fixed[$0] }.map { weights[$0] }.reduce(0, +)
            let fixedSpace = (0..<count).filter { fixed[$0] }.map { sizes[$0] }.reduce(0, +)
            guard flexibleWeight > 0 else { break }
            var changed = false
            for index in 0..<count where !fixed[index] {
                sizes[index] = max(0, available - fixedSpace) * weights[index] / flexibleWeight
            }
            for index in 0..<count where !fixed[index] && sizes[index] < minimums[index] {
                sizes[index] = minimums[index]
                fixed[index] = true
                changed = true
            }
            if !changed { break }
        }
        // Rounding each piece alone can make a row a point too wide, overlapping its last window.
        var rounded = sizes.map { $0.rounded(.down) }
        var spare = Int((available - rounded.reduce(0, +)).rounded(.down))
        let byRemainder = sizes.indices.sorted {
            sizes[$0] - rounded[$0] > sizes[$1] - rounded[$1]
        }
        for index in byRemainder where spare > 0 {
            rounded[index] += 1
            spare -= 1
        }
        return rounded
    }

    /// Rows of `columns` inside `rect`; a short last row stretches to the full width.
    static func grid(
        _ count: Int, columns: Int, in rect: CGRect, gap: CGFloat, minimums: [CGSize]
    ) -> [CGRect] {
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let rowItems = (0..<rows).map { row in
            Array(row * columns..<min(count, (row + 1) * columns))
        }
        let heights = distribute(
            rect.height, gap: gap,
            minimums: rowItems.map { $0.map { minimums[$0].height }.max() ?? 0 },
            weights: Array(repeating: 1, count: rows))
        var frames: [CGRect] = []
        var y = rect.minY
        for (row, items) in rowItems.enumerated() {
            let widths = distribute(
                rect.width, gap: gap, minimums: items.map { minimums[$0].width },
                weights: Array(repeating: 1, count: items.count))
            var x = rect.minX
            for width in widths {
                frames.append(
                    CGRect(x: x.rounded(), y: y.rounded(), width: width, height: heights[row]))
                x += width + gap
            }
            y += heights[row] + gap
        }
        return frames
    }

    // MARK: - Arrangements

    private static let heroShares: [CGFloat] = [0.6, 0.5]
    private static let stackShares: [CGFloat] = [0.6, 0.4]

    private struct FocusOption {
        var rects: [CGRect]
        var heroWidth: CGFloat
        var isPreferred: Bool
        var isReordered: Bool
        var rank: Int
    }

    /// Candidates in order of preference, each judged by `works` before anything is clamped.
    private static func arrangements(
        _ count: Int, kind: RoomLayoutKind, in area: Area, minimums given: [CGSize]
    ) -> [[CGRect]] {
        let minimums = given.map {
            CGSize(width: max($0.width, usable.width), height: max($0.height, usable.height))
        }
        switch kind {
        case .focus:
            return focusArrangements(count, in: area, minimums: minimums)
        case .columns:
            let preferred = min(count, 4)
            return ([preferred] + (1..<preferred).reversed()).map {
                grid(count, columns: $0, in: area.canvas, gap: area.gap, minimums: minimums)
            }
        default:
            let preferred = Int(Double(count).squareRoot().rounded(.up))
            return [preferred, preferred + 1, max(1, preferred - 1)].filter { $0 <= count }.map {
                grid(count, columns: $0, in: area.canvas, gap: area.gap, minimums: minimums)
            }
        }
    }

    /// The main window left, the rest in the right column; the widest may move to the last row.
    private static func focusArrangements(
        _ count: Int, in area: Area, minimums: [CGSize]
    ) -> [[CGRect]] {
        let canvas = area.canvas
        let gap = area.gap
        guard count > 1 else { return [[canvas]] }
        let side = Array(1..<count)
        let preferredColumns = side.count > 3 ? 2 : 1
        var orders = [side]
        if let widest = side.max(by: { minimums[$0].width < minimums[$1].width }),
            widest != side.last, minimums[widest].width > 0
        {
            orders.append(side.filter { $0 != widest } + [widest])
        }
        var options: [FocusOption] = []
        for share in heroShares {
            for columns in 1...min(3, side.count) {
                for (orderIndex, order) in orders.enumerated() {
                    let sideWidth = rowMinimumWidth(
                        order, columns: columns, minimums: minimums, gap: gap)
                    let widths = distribute(
                        canvas.width, gap: gap, minimums: [minimums[0].width, sideWidth],
                        weights: [share, 1 - share])
                    let hero = CGRect(
                        x: canvas.minX, y: canvas.minY, width: widths[0], height: canvas.height)
                    let column = CGRect(
                        x: hero.maxX + gap, y: canvas.minY, width: widths[1], height: canvas.height)
                    let cells = grid(
                        order.count, columns: columns, in: column, gap: gap,
                        minimums: order.map { minimums[$0] })
                    var rects = Array(repeating: CGRect.zero, count: count)
                    rects[0] = hero
                    for (cell, window) in order.enumerated() { rects[window] = cells[cell] }
                    options.append(
                        FocusOption(
                            rects: rects, heroWidth: widths[0],
                            isPreferred: columns == preferredColumns && share == heroShares[0]
                                && orderIndex == 0,
                            isReordered: orderIndex > 0, rank: options.count))
                }
            }
        }
        // The usual layout first; after it, whatever keeps the main window largest.
        return options.sorted { lhs, rhs in
            if lhs.isPreferred != rhs.isPreferred { return lhs.isPreferred }
            if abs(lhs.heroWidth - rhs.heroWidth) > 1 { return lhs.heroWidth > rhs.heroWidth }
            if lhs.isReordered != rhs.isReordered { return !lhs.isReordered }
            return lhs.rank < rhs.rank
        }.map(\.rects)
    }

    /// Focus with the side windows overlapping: the second is frontmost, every title bar in view.
    private static func stack(_ count: Int, in area: Area, minimums: [CGSize]) -> [CGRect] {
        let canvas = area.canvas
        guard count > 1 else { return [canvas] }
        let side = Array(minimums.dropFirst())
        let sideMinimum = CGSize(
            width: side.map(\.width).max() ?? 0, height: side.map(\.height).max() ?? 0)
        let widths = distribute(
            canvas.width, gap: area.gap, minimums: [minimums[0].width, sideMinimum.width],
            weights: stackShares)
        let hero = CGRect(x: canvas.minX, y: canvas.minY, width: widths[0], height: canvas.height)
        let behind = CGFloat(side.count - 1)
        let peek = min(
            Self.peek, max(0, ((canvas.height - sideMinimum.height) / max(1, behind)).rounded(.down)))
        let height = canvas.height - peek * behind
        let x = hero.maxX + area.gap
        return [hero]
            + side.indices.map { index in
                CGRect(
                    x: x, y: canvas.minY + peek * (behind - CGFloat(index)), width: widths[1],
                    height: height)
            }
    }

    /// The narrowest a column of rows can be: its widest row of minimum widths.
    private static func rowMinimumWidth(
        _ order: [Int], columns: Int, minimums: [CGSize], gap: CGFloat
    ) -> CGFloat {
        stride(from: 0, to: order.count, by: columns).map { start in
            let row = order[start..<min(order.count, start + columns)]
            return row.map { minimums[$0].width }.reduce(0, +) + gap * CGFloat(row.count - 1)
        }.max() ?? 0
    }

    /// On screen, and every window at least `usable`.
    private static func works(_ rects: [CGRect], in box: CGRect) -> Bool {
        overflow(rects, in: box) < 1
            && rects.allSatisfy {
                $0.width >= usable.width - 1 && $0.height >= usable.height - 1
            }
    }

    /// How far, in points, the rects spill outside the box, summed.
    private static func overflow(_ rects: [CGRect], in box: CGRect) -> CGFloat {
        rects.reduce(0) { sum, rect in
            sum + max(0, box.minX - rect.minX) + max(0, rect.maxX - box.maxX)
                + max(0, box.minY - rect.minY) + max(0, rect.maxY - box.maxY)
        }
    }

    private static func padded(_ minimums: [CGSize], to count: Int) -> [CGSize] {
        minimums.count == count ? minimums : Array(repeating: .zero, count: count)
    }
}
