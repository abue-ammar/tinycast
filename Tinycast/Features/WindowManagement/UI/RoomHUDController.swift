import AppKit
import SwiftUI

/// Names the room just entered when no preview did: after a shortcut, a launcher row or Settings.
@MainActor
final class RoomHUDController {
    private static let appLimit = 6

    private let settings: AppSettings
    private let presenter: HUDPresenter

    init(settings: AppSettings) {
        self.settings = settings
        presenter = HUDPresenter(
            anchor: .edgeInset(Theme.Size.hudEdgeOffset),
            dwell: Theme.Duration.messageHUD,
            screen: { settings.openOnCursorScreen ? .underCursor : .primary })
    }

    func show(_ room: Room) {
        presenter.show(
            RoomHUDView(name: room.name, appURLs: Self.appURLs(of: room))
                .environment(\.metrics, settings.interfaceSize.metrics))
    }

    private static func appURLs(of room: Room) -> [URL] {
        let bundleIDs = room.windows.map(\.bundleID).reduce(into: [String]()) { ids, id in
            if !ids.contains(id) { ids.append(id) }
        }
        return bundleIDs.prefix(appLimit).compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    }
}
