import Foundation

/// The size a Detail markdown image asks for with `?raycast-width=` / `?raycast-height=`.
struct ExtensionImageSize: Equatable {
    let width: Double?
    let height: Double?

    /// Nil when the URL names neither size, so an image without hints keeps its default frame.
    init?(url: URL) {
        let text = url.absoluteString
        // An inline payload may hold a `?` of its own, so its query starts after the comma.
        let start = url.scheme == "data" ? text.firstIndex(of: ",") ?? text.endIndex : text.startIndex
        guard let mark = text[start...].firstIndex(of: "?") else { return nil }
        var values: [String: Double] = [:]
        for pair in text[text.index(after: mark)...].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Double(parts[1]), value.isFinite, value > 0
            else { continue }
            values[String(parts[0])] = value
        }
        self.init(width: values["raycast-width"], height: values["raycast-height"])
        if width == nil && height == nil { return nil }
    }

    /// Hints only shrink an image, so this cap still stops a large asset pushing the layout around.
    static let heightCap = 220.0

    static func maxHeight(for size: ExtensionImageSize?) -> Double {
        min(size?.height ?? heightCap, heightCap)
    }

    init(width: Double?, height: Double?) {
        self.width = width
        self.height = height
    }
}
