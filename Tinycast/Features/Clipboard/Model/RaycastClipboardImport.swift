import Foundation

enum RaycastClipboardImport {
    static func parse(
        _ value: Any?, now: () -> Date, fileExists: (String) -> Bool
    ) -> (items: [ClipboardItem], missing: Int) {
        guard let entries = (value as? [String: Any])?["clipboardEntries"] as? [[String: Any]]
        else { return ([], 0) }

        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var items: [ClipboardItem] = []
        var missing = 0
        for entry in entries {
            let createdAt = parseDate(entry["createdAt"] as? String, using: dateParser) ?? now()
            let pinnedAt = isPinned(entry["pinned"]) ? createdAt : nil
            let reps = (entry["items"] as? [[String: Any]] ?? [])
                .flatMap { ($0["representations"] as? [[String: Any]]) ?? [] }

            if let text = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("text/plain") == true
            })?["content"] as? String, !text.isEmpty {
                items.append(
                    ClipboardItem(
                        id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: createdAt,
                        sourceBundleID: nil, pinnedAt: pinnedAt))
                continue
            }

            if let path = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("image/") == true
                    && ($0["contentType"] as? String) == "url"
            })?["content"] as? String {
                guard fileExists(path) else {
                    missing += 1
                    continue
                }
                items.append(
                    ClipboardItem(
                        id: UUID(), kind: .image, text: nil, imagePath: path, createdAt: createdAt,
                        sourceBundleID: nil, pinnedAt: pinnedAt))
            }
        }
        return (items, missing)
    }

    private static func parseDate(_ string: String?, using parser: ISO8601DateFormatter) -> Date? {
        guard let string else { return nil }
        return parser.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func isPinned(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return false }
        return number.boolValue
    }
}
