import Foundation

/// How Tinycast reaches a server. Secrets are never here — only the names that address them.
enum MCPTransportKind: Codable, Equatable, Hashable, Sendable {
    case http(url: String, headerName: String)
    case stdio(command: String, arguments: [String], environmentKeys: [String])

    static let defaultHeaderName = "Authorization"

    var summary: String {
        switch self {
        case .http(let url, _): return url
        case .stdio(let command, let arguments, _):
            return ([command] + arguments).joined(separator: " ")
        }
    }
}

/// Whether a server's tools may run: `.ask` puts the first call of a chat through a dialog.
enum MCPTrust: String, CaseIterable, Codable, Identifiable, Sendable {
    case ask
    case always
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask Each Chat"
        case .always: return "Always Allow"
        case .never: return "Never Allow"
        }
    }
}

struct MCPServer: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var slug: String
    var transport: MCPTransportKind
    var isEnabled: Bool
    var trust: MCPTrust

    init(
        id: UUID = UUID(), name: String = "", slug: String = "",
        transport: MCPTransportKind = .http(
            url: "", headerName: MCPTransportKind.defaultHeaderName),
        isEnabled: Bool = true, trust: MCPTrust = .ask
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.transport = transport
        self.isEnabled = isEnabled
        self.trust = trust
    }

    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? slug : trimmed
    }
}

/// The handle `@slug` addresses, derived from the name so nobody has to invent a second one.
enum MCPSlug {
    static let maxLength = 24

    static func make(from name: String, existing: Set<String>) -> String {
        let base = normalize(name)
        guard existing.contains(base) else { return base }
        // A suffix rather than a refusal: two servers may honestly want the same name.
        for suffix in 2...99 {
            let candidate = "\(base.prefix(maxLength - 3))-\(suffix)"
            if !existing.contains(candidate) { return candidate }
        }
        return UUID().uuidString.prefix(8).lowercased()
    }

    static func normalize(_ name: String) -> String {
        var slug = ""
        var pendingSeparator = false
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSeparator, !slug.isEmpty { slug.append("-") }
                pendingSeparator = false
                slug.append(character)
            } else {
                pendingSeparator = true
            }
            if slug.count >= maxLength { break }
        }
        return slug.isEmpty ? "server" : slug
    }
}
