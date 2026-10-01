import Foundation

struct TranslationRequest: Equatable, Sendable {
    let text: String
    let sourceLanguage: String?
    let targetLanguage: String
}
