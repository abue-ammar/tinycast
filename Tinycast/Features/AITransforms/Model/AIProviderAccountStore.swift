import Foundation

enum AIProviderAccountValidationError: LocalizedError, Equatable {
    case emptyName
    case invalidBaseURL
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Give the provider account a name."
        case .invalidBaseURL:
            return "Provide a valid base URL for the provider."
        case .duplicateName:
            return "An account with this name already exists."
        }
    }
}

/// Store managing configured AI provider accounts.
@MainActor
@Observable
final class AIProviderAccountStore {
    private static let accountsKey = "aiProviderAccounts"
    private static let defaultAccountIDKey = "aiDefaultProviderAccountID"

    private let defaults: UserDefaults
    private(set) var accounts: [AIProviderAccount]
    var defaultAccountID: UUID? {
        didSet {
            if let defaultAccountID {
                defaults.set(defaultAccountID.uuidString.lowercased(), forKey: Self.defaultAccountIDKey)
            } else {
                defaults.removeObject(forKey: Self.defaultAccountIDKey)
            }
        }
    }

    @ObservationIgnored var onChange: (([AIProviderAccount]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.accountsKey)
        let decoded = data.flatMap { try? JSONDecoder().decode([AIProviderAccount].self, from: $0) }
        self.accounts = decoded ?? []

        self.defaultAccountID =
            defaults.string(forKey: Self.defaultAccountIDKey)
            .flatMap(UUID.init) ?? accounts.first?.id
    }

    var defaultAccount: AIProviderAccount? {
        defaultAccountID.flatMap(account(id:)) ?? accounts.first
    }

    func account(id: UUID) -> AIProviderAccount? {
        accounts.first { $0.id == id }
    }

    @discardableResult
    func add(_ draft: AIProviderAccount) throws -> AIProviderAccount {
        let clean = try validated(draft)
        let isFirst = accounts.isEmpty || defaultAccountID == nil
        commit(accounts + [clean])
        if isFirst {
            defaultAccountID = clean.id
        }
        return clean
    }

    func update(_ draft: AIProviderAccount) throws {
        let clean = try validated(draft)
        guard let index = accounts.firstIndex(where: { $0.id == clean.id }) else { return }
        var updated = accounts
        updated[index] = clean
        commit(updated)
    }
    @discardableResult
    func remove(id: UUID) -> AIProviderAccount? {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = accounts
        let removed = updated.remove(at: index)
        if defaultAccountID == id {
            defaultAccountID = updated.first?.id
        }
        SecretStore.setSecret(nil, account: removed.secretAccountKey)
        commit(updated)
        return removed
    }

    func setDefault(id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        defaultAccountID = id
    }

    /// Seeds from existing single-provider configuration so existing setups upgrade seamlessly.
    func seedIfEmpty(legacyBaseURL: String, legacyModel: String) {
        guard accounts.isEmpty else { return }
        let matched = AIProvider.matching(baseURL: legacyBaseURL)
        let name = matched?.name ?? "Default Provider"
        let presetID = matched?.id ?? AIProvider.customID
        let url = legacyBaseURL.isEmpty ? AIClient.defaultBaseURL : legacyBaseURL
        let model =
            legacyModel.isEmpty
            ? (matched?.id == "Google Gemini" ? "gemini-3.7-flash" : AIClient.defaultModel) : legacyModel

        let primary = AIProviderAccount(
            name: name,
            providerPresetID: presetID,
            baseURL: url,
            defaultModel: model,
            defaultReasoning: .none,
            isLocal: matched?.isLocal ?? false
        )

        // Migrate legacy single API key to this account's key slot
        if let legacyKey = SecretStore.secret(account: SecretStore.aiAPIKeyAccount), !legacyKey.isEmpty {
            SecretStore.setSecret(legacyKey, account: primary.secretAccountKey)
        }

        try? add(primary)
    }

    private func validated(_ draft: AIProviderAccount) throws -> AIProviderAccount {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AIProviderAccountValidationError.emptyName }
        guard let url = AICompletionRequest.endpointURL(fromBase: draft.baseURL, path: "/chat/completions"),
            url.host != nil
        else {
            throw AIProviderAccountValidationError.invalidBaseURL
        }

        let isDuplicate = accounts.contains {
            $0.id != draft.id && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }
        guard !isDuplicate else { throw AIProviderAccountValidationError.duplicateName }

        var clean = draft
        clean.name = trimmedName
        clean.baseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.defaultModel = draft.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean
    }

    private func commit(_ updated: [AIProviderAccount]) {
        guard updated != accounts else { return }
        accounts = updated
        persist()
        onChange?(updated)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: Self.accountsKey)
    }
}
