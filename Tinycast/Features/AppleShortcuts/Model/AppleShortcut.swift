import Foundation

/// A shortcut the Shortcuts app owns; Tinycast holds only what it needs to find and run it.
struct AppleShortcut: Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "apple-shortcut:"
    static let sfSymbol = "square.2.layers.3d"

    let id: UUID
    let name: String

    var entryID: String { Self.entryID(for: id) }

    static func entryID(for id: UUID) -> String { entryIDPrefix + id.uuidString.lowercased() }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// Reads `shortcuts list --show-identifiers`, one `Name (UUID)` per line, sorted by name.
    static func parseList(_ output: String) -> [AppleShortcut] {
        var seen: Set<UUID> = []
        return output.split(whereSeparator: \.isNewline)
            .compactMap(parseLine)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Shortcuts a stored preference or binding still names that the library no longer holds.
    static func staleIDs(
        referencedBy keys: some Sequence<String>, bound: some Sequence<UUID>, live: [AppleShortcut]
    ) -> Set<UUID> {
        // An empty library can't be told apart from one the tool read as empty, so it frees nothing.
        guard !live.isEmpty else { return [] }
        let referenced = Set(keys.lazy.compactMap(id(fromEntryID:))).union(bound)
        return referenced.subtracting(live.map(\.id))
    }

    /// Anchored on the trailing identifier, so a name may carry parentheses of its own.
    private static func parseLine(_ line: Substring) -> AppleShortcut? {
        guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else { return nil }
        let identifier = line[line.index(after: open)..<line.index(before: line.endIndex)]
        let name = line[..<open].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = UUID(uuidString: String(identifier)) else { return nil }
        return AppleShortcut(id: id, name: name)
    }
}
