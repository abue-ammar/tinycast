import Foundation

/// Which enabled dictionaries a lookup asks; `.dictionary` is every one, as the fallback always has.
enum DictionaryScope: CaseIterable, Sendable {
    case dictionary
    case thesaurus

    var title: String {
        switch self {
        case .dictionary: String(localized: "Dictionary")
        case .thesaurus: String(localized: "Thesaurus")
        }
    }

    var systemImage: String {
        switch self {
        case .dictionary: "book.closed"
        case .thesaurus: "text.book.closed"
        }
    }
}
