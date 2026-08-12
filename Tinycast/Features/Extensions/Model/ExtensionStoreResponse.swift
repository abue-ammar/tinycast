import Foundation

/// Decoding for the two registry APIs, kept apart from the networking so a harness can feed it
/// recorded payloads. Both are other people's endpoints: every field beyond the few an install
/// actually needs is optional, so a response that grows or loses a key still parses.
enum ExtensionStoreResponse {

    // MARK: - Raycast's store

    /// The endpoint the store's own website searches with. Unofficial, hence the GitHub fallback.
    static func searchURL(query: String, page: Int) -> URL? {
        var components = URLComponents(string: "https://www.raycast.com/frontend_api/extensions/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            // Tinycast is macOS-only, so windows-only extensions are noise in the results.
            URLQueryItem(name: "platform", value: "macos")
        ]
        return components?.url
    }

    private struct StorePayload: Decodable {
        let data: [StoreEntry]
    }

    private struct StoreEntry: Decodable {
        let id: String
        let name: String
        let title: String?
        let description: String?
        let author: Author?
        let icons: Icons?
        let commands: [Command]?
        let downloadCount: Int?
        let downloadURL: String?
        let commitSha: String?
        let relativePath: String?
        let status: String?

        struct Author: Decodable {
            let name: String?
            let handle: String?
        }
        struct Icons: Decodable {
            let light: String?
            let dark: String?
        }
        struct Command: Decodable {
            let name: String?
        }

        enum CodingKeys: String, CodingKey {
            case id, name, title, description, author, icons, commands, status
            case downloadCount = "download_count"
            case downloadURL = "download_url"
            case commitSha = "commit_sha"
            case relativePath = "relative_path"
        }
    }

    /// Parses a store search into listings. An entry without a usable download is dropped rather than
    /// listed as something that can't be installed.
    static func parseStore(_ data: Data, registry: ExtensionRegistry) throws -> [ExtensionListing] {
        let payload = try JSONDecoder().decode(StorePayload.self, from: data)
        return payload.data.compactMap { entry -> ExtensionListing? in
            // A de-listed extension is still returned by search; it can't be downloaded any more.
            guard entry.status == nil || entry.status == "active" else { return nil }
            guard let raw = entry.downloadURL, let url = URL(string: raw) else { return nil }
            return ExtensionListing(
                id: entry.id,
                name: entry.name,
                title: entry.title ?? entry.name,
                summary: entry.description ?? "",
                author: entry.author?.name ?? entry.author?.handle ?? "",
                iconURL: (entry.icons?.light ?? entry.icons?.dark).flatMap(URL.init(string:)),
                commandCount: entry.commands?.count ?? 0,
                downloadCount: entry.downloadCount,
                registryID: registry.id,
                registryName: registry.name,
                source: .prebuiltZip(url))
        }
    }

    // MARK: - A GitHub registry

    static func contentsURL(
        owner: String, repository: String, path: String, ref: String
    ) -> URL? {
        var components = URLComponents(
            string: "https://api.github.com/repos/\(owner)/\(repository)/contents/\(path)")
        components?.queryItems = [URLQueryItem(name: "ref", value: ref)]
        return components?.url
    }

    static func treeURL(owner: String, repository: String, sha: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/git/trees/\(sha)")
    }

    /// A Git tree: what a directory holds, by sha rather than by path.
    struct GitTree: Decodable, Sendable {
        let tree: [Entry]
        /// Set when GitHub gave up listing: what came back is a prefix, not the whole directory.
        let truncated: Bool?

        struct Entry: Decodable, Sendable {
            let path: String
            let type: String
            let sha: String

            var isDirectory: Bool { type == "tree" }
        }

        func directorySHA(named name: String) -> String? {
            tree.first { $0.path == name && $0.isDirectory }?.sha
        }

        var directoryNames: [String] { tree.filter(\.isDirectory).map(\.path) }
    }

    /// A tree listing, or a thrown message when GitHub answered with an error instead.
    static func parseTree(_ data: Data) throws -> GitTree {
        if let tree = try? JSONDecoder().decode(GitTree.self, from: data) { return tree }
        struct Message: Decodable { let message: String }
        if let error = try? JSONDecoder().decode(Message.self, from: data) {
            throw ExtensionStoreError.registryRejected(error.message)
        }
        throw ExtensionStoreError.malformedResponse
    }

    /// One entry of a GitHub directory listing.
    struct GitHubEntry: Decodable, Hashable, Sendable {
        let name: String
        let path: String
        let type: String
        let size: Int?
        let downloadURL: String?

        var isDirectory: Bool { type == "dir" }

        enum CodingKeys: String, CodingKey {
            case name, path, type, size
            case downloadURL = "download_url"
        }
    }

    /// A directory listing, or a thrown message when GitHub answered with one instead — a bad ref and
    /// a rate limit both arrive as a JSON object where an array was expected.
    static func parseContents(_ data: Data) throws -> [GitHubEntry] {
        if let entries = try? JSONDecoder().decode([GitHubEntry].self, from: data) { return entries }
        struct Message: Decodable { let message: String }
        if let error = try? JSONDecoder().decode(Message.self, from: data) {
            throw ExtensionStoreError.registryRejected(error.message)
        }
        throw ExtensionStoreError.malformedResponse
    }

    /// The parts of an extension's `package.json` a listing shows, read straight from the repository.
    static func parseManifestSummary(
        _ data: Data, folder: String, registry: ExtensionRegistry
    ) -> ExtensionListing? {
        struct Manifest: Decodable {
            let name: String?
            let title: String?
            let description: String?
            let author: String?
            let icon: String?
            let commands: [Command]?
            struct Command: Decodable { let name: String? }
        }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            let name = manifest.name ?? manifest.title
        else { return nil }
        return ExtensionListing(
            id: "\(registry.id.uuidString)/\(folder)",
            name: name,
            title: manifest.title ?? name,
            summary: manifest.description ?? "",
            author: manifest.author ?? "",
            iconURL: manifest.icon.flatMap {
                URL(
                    string:
                        "https://raw.githubusercontent.com/\(registry.owner)/\(registry.repository)"
                        + "/\(registry.ref)/\(registry.path)/\(folder)/assets/\($0)")
            },
            commandCount: manifest.commands?.count ?? 0,
            downloadCount: nil,
            registryID: registry.id,
            registryName: registry.name,
            source: .githubFolder(
                owner: registry.owner, repository: registry.repository,
                path: "\(registry.path)/\(folder)", ref: registry.ref))
    }
}

enum ExtensionStoreError: LocalizedError {
    case malformedResponse
    case registryRejected(String)
    case downloadFailed(String)
    case noPackageManager
    case noNode
    case buildFailed(String)
    case notAnExtension

    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return "The registry answered with something this version doesn't understand."
        case .registryRejected(let message):
            return message
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .noPackageManager:
            return
                "This extension is source that has to be built, and no package manager was found. "
                + "Install pnpm, npm, Yarn or Bun, or pick one in Advanced."
        case .noNode:
            return
                "This extension is source that has to be built, and Node wasn't found. Install "
                + "Node.js, or install this extension from the Raycast Store instead."
        case .buildFailed(let output):
            return "The extension didn't build: \(output)"
        case .notAnExtension:
            return "That download didn't contain a Raycast extension."
        }
    }
}
