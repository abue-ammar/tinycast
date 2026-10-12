import Foundation

struct Snippet: Sendable, Hashable {
    struct ImportIdentity: Hashable {
        let name: String
        let text: String
        let tags: Set<SnippetTag.ID>

        init(_ snippet: Snippet) {
            name = snippet.name
            text = snippet.text
            tags = Set(snippet.tags.map(\.id))
        }
    }

    var name: String
    var text: String
    var keyword: String?
    var isEnabled: Bool
    var showsConfirmation: Bool
    var tags: [SnippetTag]

    init(
        name: String,
        text: String,
        keyword: String? = nil,
        isEnabled: Bool = true,
        showsConfirmation: Bool = false,
        tags: [SnippetTag] = []
    ) {
        self.name = name
        self.text = text
        self.keyword = keyword
        self.isEnabled = isEnabled
        self.showsConfirmation = showsConfirmation
        self.tags = SnippetTag.unique(tags)
    }
}

/// Fingerprint of a snippet file's bytes, detecting an external edit before a save or delete.
struct SnippetSourceRevision: Sendable, Hashable {
    private let value: String

    init(content: String) {
        var hash: UInt64 = 14_695_981_039_346_656_037
        var byteCount = 0
        for byte in content.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
            byteCount += 1
        }
        value = "\(byteCount):\(String(hash, radix: 16))"
    }
}

struct StoredSnippet: Identifiable, Sendable, Hashable {
    static let entryIDPrefix = "snippet:"

    let fileURL: URL
    var snippet: Snippet
    let sourceRevision: SnippetSourceRevision

    var id: String { fileURL.standardizedFileURL.path }

    var entryID: String { Self.entryIDPrefix + id }

    static func id(fromEntryID entryID: String) -> ID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return String(entryID.dropFirst(entryIDPrefix.count))
    }
}
