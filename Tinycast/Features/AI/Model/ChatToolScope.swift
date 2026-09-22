import Foundation

/// Which MCP servers one chat may call; the composer's tools menu edits it.
struct ChatToolScope: Equatable, Sendable {
    var isEnabled = true
    /// Servers switched off for this chat, by slug; one added later arrives switched on.
    var excluded: Set<String> = []

    func allows(_ slug: String) -> Bool {
        isEnabled && !excluded.contains(slug)
    }

    mutating func toggle(_ slug: String) {
        if excluded.contains(slug) {
            excluded.remove(slug)
        } else {
            excluded.insert(slug)
        }
    }
}
