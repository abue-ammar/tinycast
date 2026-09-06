import CoreGraphics
import Foundation

/// One app on one display, sized as a fraction of it. See docs/features/window-layouts.md.
struct WindowLayoutEntry: Codable, Hashable, Identifiable, Sendable {
    /// A stored fraction is only ever a fraction; `WindowLayoutGeometry` owns the 1 pt floor.
    static let fractionRange: ClosedRange<CGFloat> = 0...1
    /// Wider than any display, so a real nudge is never clipped and an absurd stored one is.
    static let offsetLimit: CGFloat = 10_000

    let id: UUID
    var bundleID: String
    /// A file, folder, URL or deeplink to open the app with; nil is a plain launch.
    var argument: String?
    var display: WindowLayoutDisplay
    var widthFraction: CGFloat
    var heightFraction: CGFloat
    var anchor: WindowLayoutAnchor
    /// Points, applied on top of the anchor.
    var offset: CGPoint

    init(
        id: UUID = UUID(), bundleID: String, argument: String? = nil,
        display: WindowLayoutDisplay, widthFraction: CGFloat = 1, heightFraction: CGFloat = 1,
        anchor: WindowLayoutAnchor = .center, offset: CGPoint = .zero
    ) {
        self.id = id
        self.bundleID = bundleID
        self.argument = argument
        self.display = display
        self.widthFraction = widthFraction
        self.heightFraction = heightFraction
        self.anchor = anchor
        self.offset = offset
    }

    // Hand-written, so an added field keeps stored layouts and older backups readable.
    private enum CodingKeys: String, CodingKey {
        case id, bundleID, argument, display, widthFraction, heightFraction, anchor, offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try container.decode(String.self, forKey: .bundleID)
        argument = try container.decodeIfPresent(String.self, forKey: .argument)
        display = try container.decode(WindowLayoutDisplay.self, forKey: .display)
        widthFraction = try container.decodeIfPresent(CGFloat.self, forKey: .widthFraction) ?? 1
        heightFraction = try container.decodeIfPresent(CGFloat.self, forKey: .heightFraction) ?? 1
        anchor = try container.decodeIfPresent(WindowLayoutAnchor.self, forKey: .anchor) ?? .center
        offset = try container.decodeIfPresent(CGPoint.self, forKey: .offset) ?? .zero
    }

    /// The same entry under a fresh identity, for a duplicated layout.
    var copy: WindowLayoutEntry {
        WindowLayoutEntry(
            bundleID: bundleID, argument: argument, display: display,
            widthFraction: widthFraction, heightFraction: heightFraction, anchor: anchor,
            offset: offset)
    }

    /// Clamped rather than rejected: a bad import loses a nudge, never the whole layout.
    static func sanitized(_ entries: [WindowLayoutEntry]) -> [WindowLayoutEntry] {
        entries.compactMap { entry in
            var cleaned = entry
            cleaned.bundleID = entry.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.argument = entry.argument?.cleanedLayoutField
            cleaned.display.uuid = entry.display.uuid.trimmingCharacters(
                in: .whitespacesAndNewlines)
            cleaned.widthFraction = clampFraction(entry.widthFraction)
            cleaned.heightFraction = clampFraction(entry.heightFraction)
            cleaned.offset = CGPoint(
                x: clampOffset(entry.offset.x), y: clampOffset(entry.offset.y))
            guard !cleaned.bundleID.isEmpty, !cleaned.display.uuid.isEmpty else { return nil }
            return cleaned
        }
    }

    private static func clampFraction(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        return min(max(value, fractionRange.lowerBound), fractionRange.upperBound)
    }

    private static func clampOffset(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value, -offsetLimit), offsetLimit)
    }
}

/// A saved arrangement: these apps, at these sizes, at these positions, on these displays.
struct WindowLayout: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "window-layout:"
    /// One glyph for every layout, so every surface reads as the same thing.
    static let sfSymbol = "macwindow.on.rectangle"

    let id: UUID
    var name: String
    var iconSymbol: String?
    /// Opts the layout into the global `windowGap`, the way the tiling commands use it.
    var usesPreferredGap: Bool
    var entries: [WindowLayoutEntry]
    var createdAt: Date

    init(
        id: UUID = UUID(), name: String, iconSymbol: String? = nil,
        usesPreferredGap: Bool = true, entries: [WindowLayoutEntry] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.usesPreferredGap = usesPreferredGap
        self.entries = entries
        self.createdAt = createdAt
    }

    /// The glyph every surface draws for this layout.
    var symbol: String { iconSymbol ?? Self.sfSymbol }

    /// The settings row's subtitle: what this layout actually does, in one line.
    var summary: String {
        let displays = Set(entries.map(\.display.uuid)).count
        let windows = entries.count == 1 ? "1 window" : "\(entries.count) windows"
        return displays > 1 ? "\(windows) · \(displays) displays" : windows
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// The one display order, sorted through by both the store and the `AppIndex` slice.
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    // Hand-written, so an added field keeps stored layouts and older backups readable.
    private enum CodingKeys: String, CodingKey {
        case id, name, iconSymbol, usesPreferredGap, entries, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        usesPreferredGap =
            try container.decodeIfPresent(Bool.self, forKey: .usesPreferredGap) ?? true
        entries = try container.decodeIfPresent([WindowLayoutEntry].self, forKey: .entries) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

extension String {
    /// Trimmed, and nil when that leaves nothing — an empty optional field means "unset", not "".
    fileprivate var cleanedLayoutField: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("\0") ? nil : trimmed
    }
}

enum WindowLayoutValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case noEntries
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the layout."
        case .duplicateName: return "A window layout with this name already exists."
        case .noEntries: return "Add at least one app to the layout."
        case .invalidCharacter: return "Names cannot contain null characters."
        }
    }
}
