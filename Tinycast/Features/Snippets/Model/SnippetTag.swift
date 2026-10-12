import Foundation

struct SnippetTag: Codable, Hashable, Identifiable, Sendable {
    enum Color: String, Codable, CaseIterable, Sendable {
        case red, orange, yellow, green, blue, purple, gray
    }

    struct Filter: Equatable, Sendable {
        private(set) var selectedIDs: Set<SnippetTag.ID> = []

        mutating func toggle(_ id: SnippetTag.ID?) {
            if let id {
                selectedIDs.formSymmetricDifference([id])
            } else {
                selectedIDs.removeAll()
            }
        }

        func matches(_ tags: [SnippetTag]) -> Bool {
            selectedIDs.isEmpty || tags.contains { selectedIDs.contains($0.id) }
        }

        mutating func retain(_ tags: [SnippetTag]) {
            selectedIDs.formIntersection(tags.map(\.id))
        }
    }

    let name: String
    let color: Color

    var id: String { name.precomposedStringWithCanonicalMapping.lowercased() }

    init(name: String, color: Color) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.color = color
    }

    static func unique(_ tags: [Self]) -> [Self] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let tag = Self(name: tag.name, color: tag.color)
            return !tag.name.isEmpty && seen.insert(tag.id).inserted ? tag : nil
        }
    }

    static func proposed(name: String, among tags: [Self]) -> Self? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let identity = Self(name: name, color: .gray).id
        if let existing = tags.first(where: { $0.id == identity }) { return existing }
        let used = Set(tags.map(\.color))
        let unused = Color.allCases.filter { !used.contains($0) }
        let choices = unused.isEmpty ? Color.allCases : unused
        let hash = identity.utf8.reduce(UInt64(2_166_136_261)) { ($0 ^ UInt64($1)) &* 16_777_619 }
        return Self(name: name, color: choices[Int(hash % UInt64(choices.count))])
    }
}
