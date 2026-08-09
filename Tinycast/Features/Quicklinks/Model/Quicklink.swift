import Foundation

/// A user-authored URL, search, file, folder or deeplink, surfaced as a launcher command.
struct Quicklink: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "quicklink:"
    /// Fallback glyph when there is no icon and the destination can't be detected.
    static let sfSymbol = "link"

    let id: UUID
    var name: String
    /// The raw destination template; may still contain `{argument}`-style placeholders.
    var link: String
    /// Bundle id of the app to open with, or nil for the system default handler.
    var openWithBundleID: String?
    /// SF Symbol override; nil takes the glyph the detected destination suggests.
    var iconSymbol: String?
    var showsInRootSearch: Bool
    /// A stamp rather than a flag, so the pinned block is ordered by *when* you pinned.
    var pinnedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(), name: String, link: String, openWithBundleID: String? = nil,
        iconSymbol: String? = nil, showsInRootSearch: Bool = true, pinnedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.link = link
        self.openWithBundleID = openWithBundleID
        self.iconSymbol = iconSymbol
        self.showsInRootSearch = showsInRootSearch
        self.pinnedAt = pinnedAt
        self.createdAt = createdAt
    }

    var isPinned: Bool { pinnedAt != nil }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// The one display order, sorted through by both the store and the launcher slice.
    static func precedes(_ lhs: Quicklink, _ rhs: Quicklink) -> Bool {
        switch (lhs.pinnedAt, rhs.pinnedAt) {
        case (let left?, let right?):
            return left != right ? left < right : lhs.id.uuidString < rhs.id.uuidString
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none):
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order != .orderedSame
                ? order == .orderedAscending
                : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // Hand-written, so an added field keeps old exports importable and imports stay minimal.
    private enum CodingKeys: String, CodingKey {
        case id, name, link, openWithBundleID, iconSymbol, showsInRootSearch, pinnedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        link = try container.decode(String.self, forKey: .link)
        openWithBundleID = try container.decodeIfPresent(String.self, forKey: .openWithBundleID)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        showsInRootSearch =
            try container.decodeIfPresent(Bool.self, forKey: .showsInRootSearch) ?? true
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// What `{selection}` falls back to when the target app exposes no readable selection.
enum QuicklinkSelectionFallback: String, CaseIterable, Identifiable, Sendable {
    case ask
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask for it"
        case .clipboard: return "Use the clipboard"
        }
    }
}

enum QuicklinkError: LocalizedError, Equatable {
    case emptyName
    case emptyLink
    case duplicateName
    case unresolvableLink
    case invalidCharacter
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the quicklink."
        case .emptyLink: return "Enter a link to open."
        case .duplicateName: return "A quicklink with this name already exists."
        case .unresolvableLink:
            return "This doesn't look like a URL, file path, or deeplink."
        case .invalidCharacter: return "Names and links cannot contain null characters."
        case .storageUnavailable:
            return "The quicklinks database could not be opened, so changes can't be saved."
        }
    }
}
