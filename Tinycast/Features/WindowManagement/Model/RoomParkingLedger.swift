// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics
import Foundation

/// Where each parked window belongs, on disk before it moves, so none is ever lost.
@MainActor
final class RoomParkingLedger {
    struct Entry: Codable, Equatable, Sendable {
        var windowID: UInt32
        var bundleID: String
        var title: String
        var frame: CGRect
    }

    private let fileURL: URL
    private(set) var entries: [UInt32: Entry]

    init(fileURL: URL) {
        self.fileURL = fileURL
        entries = Self.load(from: fileURL)
    }

    var isEmpty: Bool { entries.isEmpty }

    func entry(for windowID: UInt32) -> Entry? {
        entries[windowID]
    }

    /// False when the way back is not on disk, and then the window must not move.
    func record(_ entry: Entry) -> Bool {
        // Parking a parked window again must keep its first way back, not the parked frame.
        if entries[entry.windowID] == nil { entries[entry.windowID] = entry }
        return save()
    }

    func forget(_ windowIDs: some Sequence<UInt32>) {
        let before = entries.count
        for id in windowIDs { entries[id] = nil }
        if entries.count != before { save() }
    }

    /// Drops entries whose app is gone: its windows went with it.
    func keepOnly(bundleIDs: Set<String>) {
        let kept = entries.filter { bundleIDs.contains($0.value.bundleID) }
        guard kept.count != entries.count else { return }
        entries = kept
        save()
    }

    // Synchronous on purpose: the write must land before the window it protects moves.
    @discardableResult
    private func save() -> Bool {
        do {
            let list = entries.values.sorted { $0.windowID < $1.windowID }
            try JSONEncoder().encode(list).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// An unreadable ledger is the only record of where its windows belong, so it moves aside.
    private static func load(from url: URL) -> [UInt32: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let list = try? JSONDecoder().decode([Entry].self, from: data) else {
            let name = url.deletingPathExtension().lastPathComponent
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(name).unreadable-\(UUID().uuidString).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return [:]
        }
        return Dictionary(list.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
