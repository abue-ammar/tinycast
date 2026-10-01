import Foundation

enum TranslationProvider: String, CaseIterable, Codable, Sendable {
    case ai
    case deepl

    var title: String {
        switch self {
        case .ai: "AI (BYOK)"
        case .deepl: "DeepL"
        }
    }
}
