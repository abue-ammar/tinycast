import Foundation

/// One extension as the store lists it, before anything is downloaded.
struct ExtensionListing: Identifiable, Hashable, Sendable {
    let id: String
    /// The manifest `name`, which is what an install is keyed by.
    let name: String
    let title: String
    let summary: String
    let author: String
    let lightIconURL: URL?
    let darkIconURL: URL?
    let commandCount: Int
    let downloadCount: Int?
    /// A built zip; the store signs these, so the URL is fetched at install, never reused.
    let downloadURL: URL
    /// What an update check compares: it moves with every version the store publishes.
    let commitSHA: String?

    let authorHandle: String?
    let authorAvatarURL: URL?
    let ownerHandle: String?
    let commands: [Command]
    let screenshots: [URL]
    let contributors: [Contributor]
    let categories: [String]
    let readmeURL: URL?
    let storeURL: URL?
    let sourceURL: URL?
    let updatedAt: Date?

    struct Command: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        let title: String
        let summary: String
        let mode: String
    }

    struct Contributor: Identifiable, Hashable, Sendable {
        var id: String { handle }
        let name: String
        let handle: String
        let avatarURL: URL?
    }

    init(
        id: String, name: String, title: String, summary: String, author: String,
        lightIconURL: URL?, darkIconURL: URL?, commandCount: Int, downloadCount: Int?,
        downloadURL: URL, commitSHA: String?, authorHandle: String? = nil,
        authorAvatarURL: URL? = nil, ownerHandle: String? = nil, commands: [Command] = [],
        screenshots: [URL] = [], contributors: [Contributor] = [], categories: [String] = [],
        readmeURL: URL? = nil, storeURL: URL? = nil, sourceURL: URL? = nil, updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.summary = summary
        self.author = author
        self.lightIconURL = lightIconURL
        self.darkIconURL = darkIconURL
        self.commandCount = commandCount
        self.downloadCount = downloadCount
        self.downloadURL = downloadURL
        self.commitSHA = commitSHA
        self.authorHandle = authorHandle
        self.authorAvatarURL = authorAvatarURL
        self.ownerHandle = ownerHandle
        self.commands = commands
        self.screenshots = screenshots
        self.contributors = contributors
        self.categories = categories
        self.readmeURL = readmeURL
        self.storeURL = storeURL
        self.sourceURL = sourceURL
        self.updatedAt = updatedAt
    }

    /// Either side stands in for a missing other, so a one-artwork listing still draws.
    func iconURL(isDark: Bool) -> URL? {
        isDark ? (darkIconURL ?? lightIconURL) : (lightIconURL ?? darkIconURL)
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
