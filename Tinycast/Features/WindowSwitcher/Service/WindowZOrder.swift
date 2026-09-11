import CoreGraphics

/// How recently each app was in front, read off the window server's own front-to-back list.
@MainActor
enum WindowZOrder {
    /// Layer 0 is the normal window band; anything above it is a menu bar, Dock or overlay panel.
    private static let normalLayer = 0

    /// An app's rank is where its frontmost window sits; `kCGWindowName` is never read, so the
    /// list needs no Screen Recording grant.
    static func appRanks() -> [pid_t: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var ranks: [pid_t: Int] = [:]
        for window in listing {
            guard window[kCGWindowLayer as String] as? Int == normalLayer,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            if ranks[pid] == nil { ranks[pid] = ranks.count }
        }
        return ranks
    }
}
