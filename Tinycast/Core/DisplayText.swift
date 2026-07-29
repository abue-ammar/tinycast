import SwiftUI

/// User-facing text with an explicit boundary between catalog keys and runtime/user content.
enum DisplayText: ExpressibleByStringLiteral {
    case localized(String)
    case verbatim(String)

    init(stringLiteral value: String) {
        self = .localized(value)
    }

    var rawValue: String {
        switch self {
        case .localized(let value), .verbatim(let value): return value
        }
    }
}

extension Text {
    init(_ value: DisplayText) {
        switch value {
        case .localized(let key): self.init(LocalizedStringKey(key))
        case .verbatim(let value): self.init(verbatim: value)
        }
    }
}
