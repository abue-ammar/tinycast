import Foundation

enum BuiltInQuickAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case fixGrammar
    case rewrite
    case translate
    case summarize

    var id: String { rawValue }

    var title: String {
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
        case .fixGrammar: return "Fixing Grammar…"
        case .rewrite: return "Rewriting…"
        case .translate: return "Translating…"
        case .summarize: return "Summarizing…"
        }
    }

    var alwaysPreviews: Bool { self == .summarize }

    var replacesDirectlyByDefault: Bool { self == .fixGrammar }

    var showsDiff: Bool { self == .fixGrammar || self == .rewrite }

    var usesTranslationFramework: Bool { self == .translate }
}
