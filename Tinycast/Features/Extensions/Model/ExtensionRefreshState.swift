import Foundation

enum ExtensionRefreshState: Sendable, Hashable {
    case active
    /// Scheduled but switched off — the dimmed twin of `active`, and the affordance's advert.
    case idle
    case failed(String)
}
