import Foundation

/// The store version of each store-sourced extension; a folder or GitHub install has no entry.
@MainActor
final class ExtensionVersionStore {
    private struct Entry: Codable, Equatable {
        /// Nil until a check adopts the store's, which is where an import starts.
        var commitSHA: String?
    }

    private let fileURL: URL
    private var entries: [String: Entry]

    init(fileURL: URL) {
        self.fileURL = fileURL
        entries =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    var tracked: Set<String> { Set(entries.keys) }

    func record(_ commitSHA: String?, for name: String) {
        update { $0[name] = Entry(commitSHA: commitSHA) }
    }

    func forget(_ name: String) {
        update { $0[name] = nil }
    }

    /// What installs are behind. An unknown version adopts the store's: Raycast kept it current.
    func reconcile(with latest: [ExtensionListing]) -> [ExtensionListing] {
        var behind: [ExtensionListing] = []
        update { entries in
            for listing in latest {
                guard let entry = entries[listing.name], let latestSHA = listing.commitSHA else {
                    continue
                }
                if let installedSHA = entry.commitSHA {
                    if installedSHA != latestSHA { behind.append(listing) }
                } else {
                    entries[listing.name] = Entry(commitSHA: latestSHA)
                }
            }
        }
        return behind
    }

    private func update(_ body: (inout [String: Entry]) -> Void) {
        var next = entries
        body(&next)
        guard next != entries else { return }
        entries = next
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
