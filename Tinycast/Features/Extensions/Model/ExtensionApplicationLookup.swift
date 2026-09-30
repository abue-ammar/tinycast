import Foundation

/// Raycast's `open(target, application)` also takes an app by name, as the Cursor extension does.
enum ExtensionApplicationLookup {
    /// The app whose file name or display name is `name`, ignoring case and a trailing ".app".
    static func url(
        named name: String, in applications: [URL], displayName: (URL) -> String?
    ) -> URL? {
        let wanted = normalized(name)
        guard !wanted.isEmpty else { return nil }
        // The file name needs no bundle read, so it is tried across every app before any plist.
        return applications.first { normalized($0.lastPathComponent) == wanted }
            ?? applications.first { displayName($0).map(normalized) == wanted }
    }

    private static func normalized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = trimmed.lowercased().hasSuffix(".app") ? String(trimmed.dropLast(4)) : trimmed
        return stem.lowercased()
    }
}
