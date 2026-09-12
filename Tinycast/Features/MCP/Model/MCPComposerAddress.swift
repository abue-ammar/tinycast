import Foundation

/// A leading `@slug` scopes the turn to one server. An unknown handle is text, not an address.
enum MCPComposerAddress {
    static func parse(_ text: String, slugs: Set<String>) -> (slug: String?, rest: String) {
        let trimmed = text.drop { $0 == " " }
        guard trimmed.first == "@" else { return (nil, text) }
        let handle = trimmed.dropFirst().prefix { !$0.isWhitespace }
        let slug = handle.lowercased()
        guard slugs.contains(slug) else { return (nil, text) }
        let rest = trimmed.dropFirst(handle.count + 1)
        return (slug, String(rest.drop { $0 == " " }))
    }
}
