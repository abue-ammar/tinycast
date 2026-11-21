import Foundation

/// One extension as the store lists it, before anything is downloaded.
struct ExtensionListing: Codable, Identifiable, Hashable, Sendable {
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
