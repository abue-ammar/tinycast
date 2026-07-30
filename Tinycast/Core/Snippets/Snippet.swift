import Foundation

struct Snippet: Codable, Sendable, Hashable {
    var name: String
    var text: String
    var keyword: String?
    var isEnabled: Bool
    var showInLauncher: Bool
    var showsConfirmation: Bool

    init(
        name: String,
        text: String,
        keyword: String? = nil,
        isEnabled: Bool = true,
        showInLauncher: Bool = true,
        showsConfirmation: Bool = false
    ) {
        self.name = name
        self.text = text
        self.keyword = keyword
        self.isEnabled = isEnabled
        self.showInLauncher = showInLauncher
        self.showsConfirmation = showsConfirmation
    }

    private enum CodingKeys: String, CodingKey {
        case name, text, keyword, isEnabled, showInLauncher, showsConfirmation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        text = try container.decode(String.self, forKey: .text)
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        showInLauncher = try container.decodeIfPresent(Bool.self, forKey: .showInLauncher) ?? true
        showsConfirmation = try container.decodeIfPresent(Bool.self, forKey: .showsConfirmation) ?? false
    }
}

/// Fingerprint of a snippet file's bytes, used to detect an external edit before a save or delete commits.
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
    let fileURL: URL
    var snippet: Snippet
    let sourceRevision: SnippetSourceRevision

    var id: String { fileURL.standardizedFileURL.path }
}
