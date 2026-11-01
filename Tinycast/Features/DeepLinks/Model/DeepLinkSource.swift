import Foundation

/// Where a link came from. One Tinycast opened itself, from a quicklink, was chosen here.
enum DeepLinkSource: Sendable {
    case outside
    case tinycast

    /// A quicklink reaching a quicklink could reach itself, and that loop never unwinds.
    func mayRun(_ action: HotKeyAction) -> Bool {
        guard self == .tinycast, case .quicklink = action else { return true }
        return false
    }
}
