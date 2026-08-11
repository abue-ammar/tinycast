import Foundation

enum NoteLinkDestination: Sendable, Equatable {
    case external(URL)
    case file(URL)

    static func resolve(_ raw: String, relativeTo directory: URL) -> NoteLinkDestination? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("#") else { return nil }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased() {
            guard ["http", "https", "mailto"].contains(scheme) else { return nil }
            return .external(url)
        }
        let decoded = value.removingPercentEncoding ?? value
        let url = decoded.hasPrefix("/")
            ? URL(fileURLWithPath: decoded)
            : directory.appendingPathComponent(decoded)
        return .file(url.standardizedFileURL)
    }

    var url: URL {
        switch self {
        case .external(let url), .file(let url): url
        }
    }
}
