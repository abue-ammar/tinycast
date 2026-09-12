import Foundation

/// The order an empty query shows: most recently used first, minimized windows last.
enum WindowSwitchOrder {
    /// A total order, so the sort is deterministic however the sweep happened to enumerate apps.
    static func sorted(_ entries: [WindowSwitchEntry]) -> [WindowSwitchEntry] {
        entries.sorted { left, right in
            if left.isMinimized != right.isMinimized { return right.isMinimized }
            if left.appRank != right.appRank { return left.appRank < right.appRank }
            if left.appName != right.appName {
                return left.appName.localizedCaseInsensitiveCompare(right.appName)
                    == .orderedAscending
            }
            return left.handle < right.handle
        }
    }
}
