import Foundation

/// The JSON interchange format for Import/Export Quicklinks.
enum QuicklinkArchive {
    static let version = 1

    struct Document: Codable, Sendable {
        var version: Int
        var quicklinks: [Quicklink]
    }

    /// What an import did, so the summary can name both halves.
    struct MergeResult: Equatable, Sendable {
        var additions: [Quicklink]
        var skipped: Int
        var imported: Int { additions.count }
    }

    enum ArchiveError: LocalizedError, Equatable {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: return "This file isn't a Tinycast quicklinks export."
            case .empty: return "This file contains no quicklinks."
            }
        }
    }

    static func encode(_ quicklinks: [Quicklink]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Document(version: version, quicklinks: quicklinks))
    }

    /// Accepts the wrapped document and a bare array alike, so a hand-written list still imports.
    static func decode(_ data: Data) throws(ArchiveError) -> [Quicklink] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded =
            (try? decoder.decode(Document.self, from: data))?.quicklinks
            ?? (try? decoder.decode([Quicklink].self, from: data))
        guard let decoded else { throw .unreadable }
        guard !decoded.isEmpty else { throw .empty }
        return decoded
    }

    /// Duplicates are by name or destination. See docs/features/quicklinks.md#import--export.
    static func merge(_ incoming: [Quicklink], into existing: [Quicklink]) -> MergeResult {
        var names = Set(existing.map(normalizedName))
        var links = Set(existing.map(normalizedLink))
        var additions: [Quicklink] = []
        var skipped = 0
        for candidate in incoming {
            let name = normalizedName(candidate)
            let link = normalizedLink(candidate)
            guard !name.isEmpty, !link.isEmpty else {
                skipped += 1
                continue
            }
            guard names.insert(name).inserted, links.insert(link).inserted else {
                skipped += 1
                continue
            }
            // A fresh identity, so an import can't collide with an existing reference.
            additions.append(
                Quicklink(
                    name: candidate.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    link: candidate.link.trimmingCharacters(in: .whitespacesAndNewlines),
                    openWithBundleID: candidate.openWithBundleID,
                    iconSymbol: candidate.iconSymbol,
                    isEnabled: candidate.isEnabled,
                    showsInRootSearch: candidate.showsInRootSearch,
                    pinnedAt: candidate.pinnedAt))
        }
        return MergeResult(additions: additions, skipped: skipped)
    }

    private static func normalizedName(_ quicklink: Quicklink) -> String {
        quicklink.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: .current)
    }

    private static func normalizedLink(_ quicklink: Quicklink) -> String {
        quicklink.link.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
