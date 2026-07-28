import Foundation

struct Snippet: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var text: String
    var keyword: String?
    var category: String?
    var shortcut: KeyShortcut?
    var isEnabled: Bool
    var showInLauncher: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        text: String,
        keyword: String? = nil,
        category: String? = nil,
        shortcut: KeyShortcut? = nil,
        isEnabled: Bool = true,
        showInLauncher: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.keyword = keyword
        self.category = category
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.showInLauncher = showInLauncher
        self.updatedAt = updatedAt
    }
}
