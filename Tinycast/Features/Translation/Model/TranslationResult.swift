import Foundation

struct TranslationResult: Equatable, Sendable {
    let text: String
    let detectedSourceLanguage: String?
}
