import Foundation

/// One published release this build could install, reduced to the fields the updater needs.
struct AvailableRelease: Codable, Hashable, Sendable {
    let version: AppVersion
    let tag: String
    let notes: String
    let assetURL: URL
    let assetSize: Int64
    let publishedAt: Date?
}

/// Reads GitHub's releases list. Nothing throws: an unusable body is indistinguishable from
/// "nothing to install", and both mean the pump simply retries later.
enum ReleaseFeed {
    /// Where releases come from, and what every `@handle` and `#304` in their notes points at.
    static let repository = "abue-ammar/tinycast"

    /// The newest release this channel accepts, ignoring drafts and anything without a zip.
    static func newest(from data: Data, channel: ReleaseChannel) -> AvailableRelease? {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        return entries.compactMap { release(from: $0, channel: channel) }.max { $0.version < $1.version }
    }

    /// The release worth offering: strictly newer than what is running, and not one already skipped.
    static func offer(
        _ release: AvailableRelease?, running: AppVersion, skipped: AppVersion?
    ) -> AvailableRelease? {
        guard let release, release.version > running else { return nil }
        if let skipped, release.version <= skipped { return nil }
        return release
    }

    private static func release(from entry: Entry, channel: ReleaseChannel) -> AvailableRelease? {
        guard !entry.draft, channel.accepts(prerelease: entry.prerelease),
            let version = AppVersion(entry.tagName),
            // A tag disagreeing with the prerelease flag is a mis-published release, not an update.
            version.isPrerelease == entry.prerelease,
            // The zip, never the DMG: the updater expands an archive rather than mounting a volume,
            // so a release published without one is not something this app can install.
            let asset = entry.assets.first(where: { $0.name.hasSuffix(".zip") })
        else { return nil }
        return AvailableRelease(
            version: version,
            tag: entry.tagName,
            notes: ReleaseNotes.summary(of: entry.body ?? ""),
            assetURL: asset.browserDownloadURL,
            assetSize: asset.size,
            publishedAt: entry.publishedAt.flatMap { try? Date($0, strategy: .iso8601) })
    }

    private struct Entry: Decodable {
        let tagName: String
        let prerelease: Bool
        let draft: Bool
        let body: String?
        let publishedAt: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease, draft, body, assets
            case publishedAt = "published_at"
        }

        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name, size
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
