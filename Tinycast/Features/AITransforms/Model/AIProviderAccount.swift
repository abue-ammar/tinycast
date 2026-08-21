import Foundation

/// A configured provider account with its own endpoint, default model, reasoning level, and credentials.
struct AIProviderAccount: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var providerPresetID: String
    var baseURL: String
    var defaultModel: String
    var defaultReasoning: AIReasoningEffort
    var isLocal: Bool

    init(
        id: UUID = UUID(),
        name: String,
        providerPresetID: String,
        baseURL: String,
        defaultModel: String = "",
        defaultReasoning: AIReasoningEffort = .none,
        isLocal: Bool = false
    ) {
        self.id = id
        self.name = name
        self.providerPresetID = providerPresetID
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.defaultReasoning = defaultReasoning
        self.isLocal = isLocal
    }

    /// Resolves the provider preset representation (including brand SVG icon and default title).
    var providerPreset: AIProvider? {
        AIProvider.catalog.first { $0.id == providerPresetID } ?? AIProvider.matching(baseURL: baseURL)
    }

    /// Account key used to store this account's API key in `SecretStore`.
    var secretAccountKey: String {
        "ai.api-key.\(id.uuidString.lowercased())"
    }
}
