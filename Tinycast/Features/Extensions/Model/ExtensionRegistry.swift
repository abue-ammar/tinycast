import Foundation

/// Where extensions come from: the store serves a built bundle, a GitHub registry serves source.
struct ExtensionRegistry: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Raycast's own store, through the endpoint its website's search uses.
        case raycastStore
        /// A GitHub repository laid out like `raycast/extensions`: one directory per extension.
        case github
    }

    var id: UUID
    var kind: Kind
    var name: String
    /// GitHub only. Empty for the store.
    var owner: String
    var repository: String
    /// The directory the per-extension folders sit in, without leading or trailing slashes.
    var path: String
    /// A branch, tag or commit; a branch means "whatever is there now".
    var ref: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(), kind: Kind, name: String, owner: String = "", repository: String = "",
        path: String = "extensions", ref: String = "main", isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.owner = owner
        self.repository = repository
        self.path = ExtensionRegistry.normalize(path)
        self.ref = ref
        self.isEnabled = isEnabled
    }

    /// Searched first, and the only source that needs no toolchain.
    static let store = ExtensionRegistry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        kind: .raycastStore, name: "Raycast Store")

    /// The fallback if the store's endpoint goes. Off by default: it serves source, so it needs Node.
    static let officialGitHub = ExtensionRegistry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        kind: .github, name: "raycast/extensions", owner: "raycast", repository: "extensions",
        path: "extensions", ref: "main", isEnabled: false)

    static let defaults: [ExtensionRegistry] = [.store, .officialGitHub]

    /// Neither built-in can be edited or deleted; a registry someone added themselves can.
    var isBuiltIn: Bool { id == Self.store.id || id == Self.officialGitHub.id }

    /// Said under a heading that already names the kind, so it carries what differs between rows.
    var subtitle: String {
        switch kind {
        case .raycastStore: return "Installs without Node or a package manager."
        case .github: return "\(owner)/\(repository) at \(ref)"
        }
    }

    /// A pasted GitHub URL: the repository root, or the `/tree/<ref>/<path>` a browser copies.
    static func parse(_ text: String, name: String? = nil) -> ExtensionRegistry? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "github.com/", "www.github.com/"] {
            if trimmed.hasPrefix(prefix) { trimmed = String(trimmed.dropFirst(prefix.count)) }
        }
        if trimmed.hasPrefix("github.com/") { trimmed = String(trimmed.dropFirst(11)) }
        if trimmed.hasSuffix(".git") { trimmed = String(trimmed.dropLast(4)) }

        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        let owner = parts[0]
        let repository = parts[1]

        var ref = "main"
        var path = "extensions"
        if parts.count > 3, parts[2] == "tree" {
            ref = parts[3]
            let rest = parts.dropFirst(4).joined(separator: "/")
            if !rest.isEmpty { path = rest }
        }
        return ExtensionRegistry(
            kind: .github, name: name?.isEmpty == false ? name! : "\(owner)/\(repository)",
            owner: owner, repository: repository, path: path, ref: ref)
    }

    private static func normalize(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespaces)
        while trimmed.hasPrefix("/") { trimmed.removeFirst() }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }
}

/// One extension as a registry describes it, before anything is downloaded.
struct ExtensionListing: Identifiable, Hashable, Sendable {
    /// Where the bytes come from, and therefore what installing has to do.
    enum Source: Hashable, Sendable {
        /// A built zip; the store signs these, so the URL is fetched at install, never reused.
        case prebuiltZip(URL)
        /// A directory of source in a GitHub repository, at one commit or branch.
        case githubFolder(owner: String, repository: String, path: String, ref: String)
    }

    let id: String
    /// The manifest `name`, which is what an install is keyed by.
    let name: String
    let title: String
    let summary: String
    let author: String
    let iconURL: URL?
    let commandCount: Int
    /// Nil where a registry doesn't count downloads, which is every GitHub one.
    let downloadCount: Int?
    let registryID: UUID
    let registryName: String
    let source: Source

    var needsBuild: Bool {
        if case .githubFolder = source { return true }
        return false
    }

    var subtitle: String {
        var parts: [String] = []
        if !author.isEmpty { parts.append(author) }
        parts.append("\(commandCount) command\(commandCount == 1 ? "" : "s")")
        if let downloadCount, downloadCount > 0 {
            parts.append("\(ExtensionListing.abbreviate(downloadCount)) installs")
        }
        return parts.joined(separator: " · ")
    }

    /// 124218 → "124k". Exact counts past a thousand are noise in a row.
    static func abbreviate(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return "\(count / 1_000)k"
        default:
            let millions = Double(count) / 1_000_000
            return String(format: millions < 10 ? "%.1fM" : "%.0fM", millions)
        }
    }
}
