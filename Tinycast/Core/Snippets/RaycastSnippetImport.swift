import Foundation

enum RaycastSnippetImport {
    static func parse(_ value: Any?) -> [Snippet] {
        guard let entries = value as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let name = entry["name"] as? String,
                !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let text = entry["text"] as? String
            else { return nil }

            let rawKeyword = entry["keyword"] as? String
            let keyword = rawKeyword?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Snippet(
                name: name,
                text: text,
                keyword: keyword?.isEmpty == false ? keyword : nil)
        }
    }
}
