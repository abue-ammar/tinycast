import Foundation

struct FSearchRequest: Encodable, Sendable {
    let q: String
    let path: String
    let limit = FileSearchQuery.candidateLimit

    init?(query: String, directories: [URL]) {
        let terms = FileSearchQuery.terms(in: query)
        guard terms.contains(where: { $0.utf8.count >= 3 }), terms.count <= 8, !directories.isEmpty,
            query.utf8.count <= 1_024,
            terms.allSatisfy({ term in
                term.utf8.allSatisfy { byte in
                    (65...90).contains(byte) || (97...122).contains(byte)
                        || (48...57).contains(byte) || byte == 46 || byte == 45 || byte == 95
                }
            })
        else { return nil }
        q = terms.joined(separator: " ")
        let roots = Set(directories.map { $0.standardizedFileURL.path })
        if roots.contains("/") {
            path = "^/"
        } else {
            path =
                "^(?:"
                + roots.sorted().map {
                    NSRegularExpression.escapedPattern(for: $0) + "/"
                }.joined(separator: "|") + ")"
        }
        guard path.utf8.count <= 16_384 else { return nil }
    }
}
