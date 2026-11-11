import Foundation

struct Snippet: Sendable, Hashable {
    var name: String
    var text: String
    var keyword: String?
    var isEnabled: Bool
    var showsConfirmation: Bool
    var isPinned: Bool

    init(
        name: String,
        text: String,
        keyword: String? = nil,
        isEnabled: Bool = true,
        showsConfirmation: Bool = false,
        isPinned: Bool = false
    ) {
        self.name = name
        self.text = text
        self.keyword = keyword
        self.isEnabled = isEnabled
        self.showsConfirmation = showsConfirmation
        self.isPinned = isPinned
    }
}

enum SnippetDefaultAction: String, CaseIterable, Identifiable, Sendable {
    case paste
    case copy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: String(localized: "Paste")
        case .copy: String(localized: "Copy to Clipboard")
        }
    }

    var alternate: Self { self == .paste ? .copy : .paste }
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
