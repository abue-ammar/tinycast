import Foundation

/// The store's search, and the two places an install's bytes come from.
struct ExtensionStoreClient: Sendable {
    /// Cacheless, never `URLSession.shared`, so a search or a download leaves no second copy on disk.
    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private let session: URLSession

    init(session: URLSession = ExtensionStoreClient.defaultSession) {
        self.session = session
    }

    func search(_ query: String) async throws -> [ExtensionListing] {
        try await search(query, page: 1).listings
    }

    func search(
        _ query: String, page: Int, category: String? = nil
    ) async throws
        -> ExtensionStoreResponse.Page
    {
        guard let url = ExtensionStoreResponse.searchURL(query: query, page: page, category: category) else {
            throw ExtensionStoreError.malformedResponse
        }
        return try ExtensionStoreResponse.parsePage(try await get(url), page: page)
    }

    /// Nil when the store has it but can't serve it, such as a de-listed extension.
    func lookup(handle: String, name: String) async throws -> ExtensionListing? {
        guard let url = ExtensionStoreResponse.lookupURL(handle: handle, name: name) else {
            throw ExtensionStoreError.malformedResponse
        }
        return try ExtensionStoreResponse.parseEntry(try await get(url))
    }

    func download(_ url: URL) async throws -> Data {
        try await get(url)
    }

    // MARK: - GitHub

    /// Never needed to build, and the heaviest thing in some extension folders.
    private static let skippedDirectories: Set<String> = ["node_modules", "metadata"]

    /// One recursive tree, then raw blobs: `contents` costs an API call per directory, and the
    /// anonymous budget is 60 an hour — an extension with 17 of them used to spend a third of it.
    func downloadFolder(_ source: ExtensionGitHubSource, to destination: URL) async throws {
        guard let url = source.treeURL(sha: try await treeSHA(of: source), recursive: true) else {
            throw ExtensionStoreError.malformedResponse
        }
        let tree = try ExtensionGitHubSource.parseTree(try await get(url))
        guard tree.truncated != true else {
            throw ExtensionStoreError.downloadFailed("\(source.summary) is too large to download.")
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in tree.tree where entry.isFile {
            let components = entry.path.split(separator: "/").map(String.init)
            guard !components.contains(where: Self.skippedDirectories.contains),
                let raw = source.rawURL(for: entry.path)
            else { continue }
            let target = components.reduce(destination) { $0.appendingPathComponent($1) }
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await get(raw).write(to: target, options: .atomic)
            if entry.isExecutable {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            }
        }
    }

    /// Walks a path to the tree it names: the trees API takes a sha, and a ref only for the root.
    private func treeSHA(of source: ExtensionGitHubSource) async throws -> String {
        var sha = source.ref
        for segment in source.path.split(separator: "/").map(String.init) {
            guard let url = source.treeURL(sha: sha) else {
                throw ExtensionStoreError.malformedResponse
            }
            guard
                let next = try ExtensionGitHubSource.parseTree(try await get(url))
                    .directorySHA(named: segment)
            else {
                throw ExtensionStoreError.rejected(
                    "\(source.owner)/\(source.repository) has no \(source.path) folder at \(source.ref).")
            }
            sha = next
        }
        return sha
    }

    // MARK: - Fetching

    private func get(_ url: URL) async throws -> Data {
        let isGitHubAPI = url.host == "api.github.com"
        var request = URLRequest(url: url)
        // GitHub serves the old media type without it, and rejects a request with no user agent.
        request.setValue("OpenAI File Downloader, XaiImageApiFetch/1.0", forHTTPHeaderField: "User-Agent")
        if isGitHubAPI {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            // Anonymous, so a private repository answers exactly like a missing one.
            if isGitHubAPI, http.statusCode == 404 {
                throw ExtensionStoreError.rejected(
                    "That repository or branch wasn't found. A private repository can't be read.")
            }
            // GitHub explains a rate limit in the body; surfacing that beats a bare "403".
            struct Message: Decodable { let message: String }
            if let error = try? JSONDecoder().decode(Message.self, from: data) {
                throw ExtensionStoreError.rejected(error.message)
            }
            throw ExtensionStoreError.downloadFailed("HTTP \(http.statusCode)")
        }
        return data
    }
}
