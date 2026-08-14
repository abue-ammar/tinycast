import Foundation

/// Searches every enabled registry and merges the results, the store's winning because it is prebuilt.
struct ExtensionStoreClient: Sendable {
    /// Kept small: a GitHub registry reads one manifest per candidate.
    private static let githubCandidateLimit = 12

    /// Cacheless, never `URLSession.shared`, so a registry search leaves no second copy on disk.
    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private let session: URLSession

    init(session: URLSession = ExtensionStoreClient.defaultSession) {
        self.session = session
    }

    // MARK: - Search

    /// The error rather than a throw, so one failing registry can't take the others' results.
    struct RegistryResult: Sendable {
        let registry: ExtensionRegistry
        let listings: [ExtensionListing]
        let failure: String?
    }

    func search(_ query: String, in registries: [ExtensionRegistry]) async -> [RegistryResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return await withTaskGroup(of: RegistryResult.self) { group in
            for registry in registries where registry.isEnabled {
                group.addTask { await search(trimmed, in: registry) }
            }
            var results: [RegistryResult] = []
            for await result in group { results.append(result) }
            // Registry order, not completion order, so the list doesn't reshuffle between searches.
            return registries.compactMap { registry in
                results.first { $0.registry.id == registry.id }
            }
        }
    }

    private func search(_ query: String, in registry: ExtensionRegistry) async -> RegistryResult {
        do {
            let listings =
                switch registry.kind {
                case .raycastStore: try await searchStore(query, registry: registry)
                case .github: try await searchGitHub(query, registry: registry)
                }
            return RegistryResult(registry: registry, listings: listings, failure: nil)
        } catch {
            return RegistryResult(
                registry: registry, listings: [], failure: error.localizedDescription)
        }
    }

    private func searchStore(
        _ query: String, registry: ExtensionRegistry
    ) async throws
        -> [ExtensionListing]
    {
        guard let url = ExtensionStoreResponse.searchURL(query: query, page: 1) else {
            throw ExtensionStoreError.malformedResponse
        }
        let data = try await get(url)
        return try ExtensionStoreResponse.parseStore(data, registry: registry)
    }

    /// A registry has no search, so the listing is ranked here and only the best few are read.
    private func searchGitHub(
        _ query: String, registry: ExtensionRegistry
    ) async throws
        -> [ExtensionListing]
    {
        let folders = try await folderNames(in: registry)
        let ranked =
            folders
            .compactMap { folder -> (String, Int)? in
                guard let score = FuzzyMatch.score(query: query, candidate: folder) else {
                    return nil
                }
                return (folder, score)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(Self.githubCandidateLimit)
            .map(\.0)

        return await withTaskGroup(of: ExtensionListing?.self) { group in
            for folder in ranked {
                group.addTask { await manifestListing(folder: folder, registry: registry) }
            }
            var listings: [ExtensionListing] = []
            for await listing in group {
                if let listing { listings.append(listing) }
            }
            // Back into rank order: the group finishes in whatever order the requests do.
            return ranked.compactMap { folder in
                listings.first { listing in
                    if case .githubFolder(_, _, let path, _) = listing.source {
                        return path.hasSuffix("/" + folder)
                    }
                    return false
                }
            }
        }
    }

    private func manifestListing(
        folder: String, registry: ExtensionRegistry
    ) async
        -> ExtensionListing?
    {
        let raw =
            "https://raw.githubusercontent.com/\(registry.owner)/\(registry.repository)"
            + "/\(registry.ref)/\(registry.path)/\(folder)/package.json"
        guard let url = URL(string: raw), let data = try? await get(url) else { return nil }
        return ExtensionStoreResponse.parseManifestSummary(
            data, folder: folder, registry: registry)
    }

    /// Trees, not contents: contents caps a directory at 1000 silently, and this repo is three times that.
    private func folderNames(in registry: ExtensionRegistry) async throws -> [String] {
        if let cached = await FolderCache.shared.names(for: registry.id) { return cached }

        var sha = registry.ref
        for segment in registry.path.split(separator: "/").map(String.init) {
            guard
                let url = ExtensionStoreResponse.treeURL(
                    owner: registry.owner, repository: registry.repository, sha: sha)
            else { throw ExtensionStoreError.malformedResponse }
            let tree = try ExtensionStoreResponse.parseTree(try await get(url))
            guard let next = tree.directorySHA(named: segment) else {
                throw ExtensionStoreError.registryRejected(
                    "\(registry.owner)/\(registry.repository) has no \(registry.path) directory "
                        + "on \(registry.ref).")
            }
            sha = next
        }

        guard
            let url = ExtensionStoreResponse.treeURL(
                owner: registry.owner, repository: registry.repository, sha: sha)
        else { throw ExtensionStoreError.malformedResponse }
        let tree = try ExtensionStoreResponse.parseTree(try await get(url))
        let names = tree.directoryNames
        await FolderCache.shared.store(names, for: registry.id)
        return names
    }

    // MARK: - Fetching

    /// One folder, walked breadth-first: a registry repository is gigabytes, and cloning it is absurd.
    func downloadFolder(
        owner: String, repository: String, path: String, ref: String, to destination: URL
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        guard
            let url = ExtensionStoreResponse.contentsURL(
                owner: owner, repository: repository, path: path, ref: ref)
        else { throw ExtensionStoreError.malformedResponse }
        let entries = try ExtensionStoreResponse.parseContents(try await get(url))

        for entry in entries {
            // Never needed to build, and the heaviest thing in some extension folders.
            if entry.isDirectory, entry.name == "node_modules" || entry.name == "metadata" {
                continue
            }
            let target = destination.appendingPathComponent(entry.name)
            if entry.isDirectory {
                try await downloadFolder(
                    owner: owner, repository: repository, path: entry.path, ref: ref, to: target)
            } else {
                guard let raw = entry.downloadURL, let fileURL = URL(string: raw) else { continue }
                let data = try await get(fileURL)
                try data.write(to: target, options: .atomic)
            }
        }
    }

    func download(_ url: URL) async throws -> Data {
        try await get(url)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        // GitHub serves the old media type without it, and rejects a request with no user agent.
        request.setValue("Tinycast", forHTTPHeaderField: "User-Agent")
        if url.host?.hasSuffix("api.github.com") == true {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            // GitHub explains a rate limit in the body; surfacing that beats a bare "403".
            struct Message: Decodable { let message: String }
            if let error = try? JSONDecoder().decode(Message.self, from: data) {
                throw ExtensionStoreError.registryRejected(error.message)
            }
            throw ExtensionStoreError.downloadFailed("HTTP \(http.statusCode)")
        }
        return data
    }
}

/// Listings for the session: re-fetching per keystroke spends GitHub's anonymous limit in a few searches.
private actor FolderCache {
    static let shared = FolderCache()

    private var cached: [UUID: [String]] = [:]

    func names(for registry: UUID) -> [String]? { cached[registry] }
    func store(_ names: [String], for registry: UUID) { cached[registry] = names }
}
