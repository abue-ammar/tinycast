// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// The smallest size each app has refused to go below, learned by trying and kept across launches.
@MainActor
final class RoomMinimumSizeStore {
    private static let defaultsKey = "roomMinimumWindowSizes"

    private let defaults: UserDefaults
    private(set) var sizes: [String: CGSize]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sizes =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: CGSize].self, from: $0) } ?? [:]
    }

    func size(for bundleID: String) -> CGSize {
        sizes[bundleID] ?? .zero
    }

    /// True when `size` raised what was known: only then is laying the room out again worth it.
    @discardableResult
    func learn(_ size: CGSize, for bundleID: String) -> Bool {
        guard size.width.isFinite, size.height.isFinite else { return false }
        let known = self.size(for: bundleID)
        let raised = CGSize(width: max(known.width, size.width), height: max(known.height, size.height))
        guard raised != known else { return false }
        sizes[bundleID] = raised
        if let data = try? JSONEncoder().encode(sizes) { defaults.set(data, forKey: Self.defaultsKey) }
        return true
    }
}
