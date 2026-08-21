import Foundation

struct AIProviderAccount: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var providerPresetID: String
    var baseURL: String
    var defaultModel: String = ""
    var defaultReasoning: AIReasoningEffort = .none
    var isLocal: Bool = false
    var isOAuth: Bool = false

    /// Resolves the provider preset representation (including brand SVG icon and default title).
    var providerPreset: AIProvider? {
        AIProvider.catalog.first { $0.id == providerPresetID } ?? AIProvider.matching(baseURL: baseURL)
    }

    /// Account key used to store this account's API key in `SecretStore`.
    var secretAccountKey: String {
        "ai.api-key.\(id.uuidString.lowercased())"
    }
}
