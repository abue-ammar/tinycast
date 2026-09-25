// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation

/// Which open window fills which of a room's windows. Each open window is used at most once.
enum RoomWindowMatcher {
    /// Room window index → open window index. `claimed` windows go last: other rooms hold them.
    static func assign(
        _ windows: [RoomWindow], to live: [RoomLiveWindow], claimed: Set<UInt32> = []
    ) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var used = Set<Int>()
        func pass(_ accepts: (RoomWindow, RoomLiveWindow) -> Bool) {
            for (index, window) in windows.enumerated() where result[index] == nil {
                guard
                    let match = live.indices.first(where: {
                        !used.contains($0) && live[$0].bundleID == window.bundleID
                            && accepts(window, live[$0])
                    })
                else { continue }
                result[index] = match
                used.insert(match)
            }
        }
        pass { saved, open in saved.windowID != nil && saved.windowID == open.windowID }
        pass { saved, open in !saved.title.isEmpty && saved.title == open.title }
        // A title that only looks alike never takes another room's window.
        pass { saved, open in
            isSimilar(saved.title, open.title) && !isClaimed(open, by: claimed)
        }
        // Titles follow the current tab, so last comes any window of the app, a free one first.
        pass { _, open in !isClaimed(open, by: claimed) }
        pass { _, _ in true }
        return result
    }

    /// Titles sharing a meaningful part: "Report — draft 3" and "Report — draft 4".
    static func isSimilar(_ lhs: String, _ rhs: String) -> Bool {
        let left = folded(lhs)
        let right = folded(rhs)
        guard left.count >= 4, right.count >= 4 else { return false }
        if left.contains(right) || right.contains(left) { return true }
        let common = zip(left, right).prefix { $0 == $1 }.count
        return common >= min(12, min(left.count, right.count) * 2 / 3)
    }

    private static func isClaimed(_ window: RoomLiveWindow, by claimed: Set<UInt32>) -> Bool {
        window.windowID.map(claimed.contains) ?? false
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
