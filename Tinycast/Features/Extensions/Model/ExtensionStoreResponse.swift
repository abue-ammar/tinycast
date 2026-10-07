import Foundation

/// Someone else's endpoint, so every field an install doesn't need is optional.
enum ExtensionStoreResponse {
    static let categories = [
        "AI Extensions", "Applications", "Communication", "Data", "Documentation",
        "Design Tools", "Developer Tools", "Finance", "Fun", "Media", "News", "Productivity",
        "Security", "System", "Web", "Other"
    ]
    static let pageSize = 50

    struct Page: Sendable {
        let listings: [ExtensionListing]
        let totalResults: Int?
        let hasMore: Bool
    }

    static func searchURL(query: String, page: Int, category: String? = nil) -> URL? {
        guard page > 0 else { return nil }
        let category = category.flatMap { $0.isEmpty ? nil : $0 }
        let search = ([query] + (category.map { ["category:\"\($0)\""] } ?? []))
            .filter { !$0.isEmpty }.joined(separator: " ")
        let path = search.isEmpty ? "store_listings" : "store_listings/search"
        var components = URLComponents(string: "https://backend.raycast.com/api/v1/\(path)")
        components?.queryItems = [
            URLQueryItem(name: "q", value: search),
            URLQueryItem(name: "page", value: String(page)),
            // Case-sensitive: any other spelling returns only extensions listing no platforms.
            URLQueryItem(name: "per_page", value: String(pageSize)),
            URLQueryItem(name: "explicit_platform", value: "macOS")
        ]
        return components?.url
    }

    /// One extension by the handle and name its manifest carries.
    static func lookupURL(handle: String, name: String) -> URL? {
        guard !handle.isEmpty, !name.isEmpty else { return nil }
        return URL(string: "https://www.raycast.com/api/v1/extensions")?
            .appending(path: handle)
            .appending(path: name)
    }

    private struct StorePayload: Decodable {
        let data: [StoreEntry]
        let totalResults: Int?

        enum CodingKeys: String, CodingKey {
            case data
            case totalResults = "total_results"
        }
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
        let commitSHA: String?
        let status: String?
        let owner: Author?
        let contributors: [Author]?
        let categories: [String]?
        let metadata: [String]?
        let readmeURL: String?
        let storeURL: String?
        let sourceURL: String?
        let updatedAt: Double?

        struct Author: Decodable {
            let name: String?
            let handle: String?
            let avatar: String?
        }
        struct Icons: Decodable {
            let light: String?
            let dark: String?
        }
        struct Command: Decodable {
            let name: String?
            let title: String?
            let description: String?
            let mode: String?
        }

        enum CodingKeys: String, CodingKey {
            case id, name, title, description, author, icons, commands, status
            case owner, contributors, categories, metadata
            case readmeURL = "readme_url"
            case storeURL = "store_url"
            case sourceURL = "source_url"
            case updatedAt = "updated_at"
            case downloadCount = "download_count"
            case downloadURL = "download_url"
            case commitSHA = "commit_sha"
        }
    }

    static func parseStore(_ data: Data) throws -> [ExtensionListing] {
        try parsePage(data, page: 1).listings
    }

    static func parsePage(_ data: Data, page: Int) throws -> Page {
        let payload = try JSONDecoder().decode(StorePayload.self, from: data)
        let hasMore =
            !payload.data.isEmpty
            && (payload.totalResults.map {
                page * pageSize < $0
            } ?? (payload.data.count == pageSize))
        return Page(
            listings: payload.data.compactMap(listing(from:)),
            totalResults: payload.totalResults, hasMore: hasMore)
    }

    /// A lookup answers with the entry itself, not a page of them.
    static func parseEntry(_ data: Data) throws -> ExtensionListing? {
        listing(from: try JSONDecoder().decode(StoreEntry.self, from: data))
    }

    /// An entry without a usable download is dropped, not listed as uninstallable.
    private static func listing(from entry: StoreEntry) -> ExtensionListing? {
        // A de-listed extension is still returned by search; it can't be downloaded any more.
        guard entry.status == nil || entry.status == "active" else { return nil }
        guard let raw = entry.downloadURL, let url = URL(string: raw) else { return nil }
        return ExtensionListing(
            id: entry.id,
            name: entry.name,
            title: entry.title ?? entry.name,
            summary: entry.description ?? "",
            author: entry.author?.name ?? entry.author?.handle ?? "",
            lightIconURL: entry.icons?.light.flatMap(URL.init(string:)),
            darkIconURL: entry.icons?.dark.flatMap(URL.init(string:)),
            commandCount: entry.commands?.count ?? 0,
            downloadCount: entry.downloadCount,
            downloadURL: url,
            commitSHA: entry.commitSHA,
            authorHandle: entry.author?.handle,
            authorAvatarURL: entry.author?.avatar.flatMap(URL.init(string:)),
            ownerHandle: entry.owner?.handle ?? entry.author?.handle,
            commands: (entry.commands ?? []).compactMap { command in
                guard let name = command.name else { return nil }
                return ExtensionListing.Command(
                    name: name, title: command.title ?? name,
                    summary: command.description ?? "", mode: command.mode ?? "view")
            },
            screenshots: (entry.metadata ?? []).compactMap(URL.init(string:)),
            contributors: (entry.contributors ?? []).compactMap { contributor in
                guard let handle = contributor.handle else { return nil }
                return ExtensionListing.Contributor(
                    name: contributor.name ?? handle, handle: handle,
                    avatarURL: contributor.avatar.flatMap(URL.init(string:)))
            },
            categories: entry.categories ?? [],
            readmeURL: entry.readmeURL.flatMap(URL.init(string:)),
            storeURL: entry.storeURL.flatMap(URL.init(string:)),
            sourceURL: entry.sourceURL.flatMap(URL.init(string:)),
            updatedAt: entry.updatedAt.map(Date.init(timeIntervalSince1970:)))
    }
}

enum ExtensionStoreError: LocalizedError {
    case malformedResponse
    case rejected(String)
    case downloadFailed(String)
    case noPackageManager
    case noNode
    case buildFailed(String)
    case notAnExtension

    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return "The server answered with something this version doesn't understand."
        case .rejected(let message):
            return message
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .noPackageManager:
            return
                "No package manager was found. Install pnpm, npm, Yarn or Bun, or add the folder "
                + "it lives in to Custom search paths."
        case .noNode:
            return
                "Node wasn't found. Install Node.js, add the folder it lives in to Custom search "
                + "paths, or install this extension from the Raycast Store instead."
        case .buildFailed(let output):
            return "The extension didn't build: \(output)"
        case .notAnExtension:
            return "That download didn't contain a Raycast extension."
        }
    }
}
