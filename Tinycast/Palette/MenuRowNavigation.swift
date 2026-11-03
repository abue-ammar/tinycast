import Foundation

/// Where a menu arrow lands: past either end it wraps to the other, skipping unselectable rows.
enum MenuRowNavigation {
    static func next(
        from selection: Int, by delta: Int, count: Int, isSelectable: (Int) -> Bool
    ) -> Int? {
        guard count > 0, delta != 0 else { return nil }
        let direction = delta > 0 ? 1 : -1
        var row = min(max(selection, 0), count - 1)
        for _ in 0..<count {
            row = (row + direction + count) % count
            if isSelectable(row) { return row }
        }
        return nil
    }
}
