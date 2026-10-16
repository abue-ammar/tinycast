// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation

/// A project you walk into: its windows, in order, and how they lay out. See window-rooms.md.
struct Room: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "window-room:"
    static let sfSymbol = "door.left.hand.open"

    let id: UUID
    var name: String
    /// The first is the main window: it takes the largest spot and ends frontmost.
    var windows: [RoomWindow]
    var layout: RoomLayoutKind
    /// A layout chosen on one display, keyed by its lowercased UUID; `layout` covers the rest.
    var layoutsByDisplay: [String: RoomLayoutKind]
    var lastEnteredAt: Date?

    init(
        id: UUID = UUID(), name: String, windows: [RoomWindow] = [],
        layout: RoomLayoutKind = .auto, layoutsByDisplay: [String: RoomLayoutKind] = [:],
        lastEnteredAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.windows = windows
        self.layout = layout
        self.layoutsByDisplay = layoutsByDisplay
        self.lastEnteredAt = lastEnteredAt
    }

    func layout(onDisplay uuid: String?) -> RoomLayoutKind {
        uuid.flatMap { layoutsByDisplay[$0.lowercased()] } ?? layout
    }

    /// This room as written elsewhere, keeping what entering `learned` taught this Mac.
    func keepingRuntime(of learned: Room) -> Room {
        var room = self
        room.lastEnteredAt = learned.lastEnteredAt
        // A window's number goes back only to a window of the same app, so an edit can't mismatch.
        for (index, window) in zip(room.windows.indices, learned.windows)
        where window.bundleID == room.windows[index].bundleID {
            room.windows[index].windowID = window.windowID
        }
        return room
    }

    var summary: String { String(localized: "\(windows.count) windows") }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// The one name order, sorted through by both the store and the `AppIndex` slice.
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Most recently entered first, so the room you just left is one row away.
    static func enteredMoreRecently(_ lhs: Self, _ rhs: Self) -> Bool {
        let left = lhs.lastEnteredAt ?? .distantPast
        let right = rhs.lastEnteredAt ?? .distantPast
        return left != right ? left > right : precedes(lhs, rhs)
    }

    // Hand-written, so an added field keeps stored rooms and older backups readable.
    private enum CodingKeys: String, CodingKey {
        case id, name, windows, layout, layoutsByDisplay, lastEnteredAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        windows = try container.decodeIfPresent([RoomWindow].self, forKey: .windows) ?? []
        // A layout this build does not know resets to Auto rather than losing the room.
        layout = (try? container.decodeIfPresent(RoomLayoutKind.self, forKey: .layout)) ?? .auto
        let stored =
            (try? container.decodeIfPresent([String: String].self, forKey: .layoutsByDisplay)) ?? [:]
        layoutsByDisplay = stored.compactMapValues(RoomLayoutKind.init(rawValue:))
        lastEnteredAt = try container.decodeIfPresent(Date.self, forKey: .lastEnteredAt)
    }
}

enum RoomValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case noWindows
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Enter a name for the room.")
        case .duplicateName: return String(localized: "A room with this name already exists.")
        case .noWindows: return String(localized: "Choose at least one window for the room.")
        case .invalidCharacter: return String(localized: "Names cannot contain null characters.")
        }
    }
}
