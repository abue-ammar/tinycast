import Foundation

/// An extension's source on GitHub: a repository root, or one folder of it, at one ref.
struct ExtensionGitHubSource: Hashable, Sendable {
    /// Follows the default branch, whatever the repository calls it.
    static let defaultRef = "HEAD"

    let owner: String
    let repository: String
    /// The extension's folder, without leading or trailing slashes; empty for the repository root.
    let path: String
    /// A branch, tag or commit.
    let ref: String

    private static let ownerCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    private static let repositoryCharacters = ownerCharacters.union(CharacterSet(charactersIn: "_."))

    /// `owner/repo`, a clone URL, or the `/tree/<ref>/<path>` link a browser copies.
    init?(_ text: String) {
        var rest = String(
            text.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0 != "?" && $0 != "#" })
        for prefix in ["https://", "http://", "git@github.com:", "www.github.com/", "github.com/"]
        where rest.hasPrefix(prefix) {
            rest.removeFirst(prefix.count)
        }
        if rest.hasSuffix(".git") { rest.removeLast(4) }

        let parts = rest.split(separator: "/").map(String.init)
        // GitHub's own naming rules, so another host's URL is rejected rather than misread.
        guard parts.count >= 2,
            parts[0].unicodeScalars.allSatisfy(Self.ownerCharacters.contains),
            parts[1].unicodeScalars.allSatisfy(Self.repositoryCharacters.contains)
        else { return nil }

        if parts.count == 2 {
            ref = Self.defaultRef
            path = ""
        } else if parts.count >= 4, parts[2] == "tree" {
            ref = parts[3]
            path = parts.dropFirst(4).joined(separator: "/")
        } else {
            return nil
        }
        owner = parts[0]
        repository = parts[1]
    }

    var summary: String {
        let location = [owner, repository, path].filter { !$0.isEmpty }.joined(separator: "/")
        return ref == Self.defaultRef ? "\(location) on its default branch" : "\(location) at \(ref)"
    }

    /// Trees, not contents: contents caps a directory at 1000 and costs a call per level.
    func treeURL(sha: String, recursive: Bool = false) -> URL? {
        var components = URLComponents(
            string: "https://api.github.com/repos/\(owner)/\(repository)/git/trees/\(sha)")
        if recursive { components?.queryItems = [URLQueryItem(name: "recursive", value: "1")] }
        return components?.url
    }

    /// File bodies come from here, which GitHub's anonymous API budget doesn't count.
    func rawURL(for file: String) -> URL? {
        let location = [owner, repository, ref, path, file].filter { !$0.isEmpty }
            .joined(separator: "/")
        guard let escaped = location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(escaped)")
    }

    // MARK: - Trees

    struct Tree: Decodable, Sendable {
        let tree: [Entry]
        /// Set when GitHub gave up listing: what came back is a prefix, not the whole directory.
        let truncated: Bool?

        struct Entry: Decodable, Sendable {
            let path: String
            let type: String
            let sha: String
            let mode: String?

            var isDirectory: Bool { type == "tree" }
            var isFile: Bool { type == "blob" }
            var isExecutable: Bool { isFile && mode == "100755" }
        }

        func directorySHA(named name: String) -> String? {
            tree.first { $0.path == name && $0.isDirectory }?.sha
        }
    }

    static func parseTree(_ data: Data) throws -> Tree {
        if let tree = try? JSONDecoder().decode(Tree.self, from: data) { return tree }
        struct Message: Decodable { let message: String }
        if let error = try? JSONDecoder().decode(Message.self, from: data) {
            throw ExtensionStoreError.rejected(error.message)
        }
        throw ExtensionStoreError.malformedResponse
    }
}
