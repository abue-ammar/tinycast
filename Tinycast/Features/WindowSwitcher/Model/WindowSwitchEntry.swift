import Foundation

/// One open window the switcher offers. A handle, not an `AXUIElement`: this layer stays pure.
struct WindowSwitchEntry: Identifiable, Hashable, Sendable {
    /// The app's own front-to-back order, flattened across apps; also indexes the live elements.
    let handle: Int
    let appName: String
    let bundleID: String
    let iconURL: URL?
    let iconStamp: Int
    let title: String
    let isMinimized: Bool
    /// Lower is nearer the front; `.max` when the app has no on-screen window to rank it by.
    let appRank: Int

    /// A string, because every palette list identifies its rows by one.
    var id: String { String(handle) }

    /// A document window with no title yet reads as its app rather than as a blank row.
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? appName : title
    }

    // The app name rides as owner, not as a name: every window of one app shares it.
    func searchFields() -> SearchFields {
        [SearchAlias.name(displayTitle), SearchAlias.owner(appName)]
    }
}
