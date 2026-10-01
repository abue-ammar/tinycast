import Foundation

struct TranslationLanguage: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let usableAsSource: Bool
    let usableAsTarget: Bool
}
