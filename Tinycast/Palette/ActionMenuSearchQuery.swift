import Foundation

/// A folded menu query reused for every row title in one menu rebuild.
struct ActionMenuSearchQuery {
    private let needle: FuzzyMatch.Query?

    var isEmpty: Bool { needle == nil }

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        needle = trimmed.isEmpty ? nil : FuzzyMatch.Query(trimmed)
    }

    func score(_ candidate: String) -> Int? {
        guard let needle else { return 0 }
        return FuzzyMatch.score(needle, candidate: candidate)
    }
}
