import Foundation

enum BuiltInQuickAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case fixGrammar
    case rewrite
    case translate
    case summarize

    var id: String { rawValue }

    var title: String { titleResource.resolved() }

    /// A resource, so a launcher command named after it keeps the English name searchable.
    var titleResource: LocalizedStringResource {
        switch self {
        case .fixGrammar: return "Fix Grammar"
        case .rewrite: return "Rewrite"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        }
    }

    var symbol: String {
        switch self {
        case .fixGrammar: return "textformat"
        case .rewrite: return "wand.and.sparkles"
        case .translate: return "translate"
        case .summarize: return "text.line.3.summary"
        }
    }

    var progressTitle: String {
        switch self {
        case .fixGrammar: return String(localized: "Fixing Grammar…")
        case .rewrite: return String(localized: "Rewriting…")
        case .translate: return String(localized: "Translating…")
        case .summarize: return String(localized: "Summarizing…")
        }
    }

    var alwaysPreviews: Bool { self == .summarize }

    var replacesDirectlyByDefault: Bool { self == .fixGrammar }

    var showsDiff: Bool { self == .fixGrammar || self == .rewrite }

    var usesTranslationFramework: Bool { self == .translate }
}
