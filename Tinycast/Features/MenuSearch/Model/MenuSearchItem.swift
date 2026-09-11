import Foundation

struct MenuSearchItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let parentComponents: [String]
    let shortcut: MenuSearchShortcut?

    init(title: String, parentComponents: [String], shortcut: MenuSearchShortcut? = nil) {
        self.title = title
        self.parentComponents = parentComponents
        self.shortcut = shortcut
        id = Self.joined(title: title, parents: parentComponents, separator: "\u{1F}")
    }

    var displayPath: String {
        Self.joined(title: title, parents: parentComponents, separator: " > ")
    }

    private static func joined(title: String, parents: [String], separator: String) -> String {
        (parents + [title]).joined(separator: separator)
    }

    static func isEligible(
        title: String, isEnabled: Bool, isHidden: Bool, isSeparator: Bool, canPress: Bool
    ) -> Bool {
        guard isEnabled, !isHidden, !isSeparator, canPress else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // The path rides as owner, not translation: a shared hierarchy string must stay literal-only.
    func searchFields() -> SearchFields {
        [SearchAlias.name(title), SearchAlias(displayPath, .owner)]
    }
}
