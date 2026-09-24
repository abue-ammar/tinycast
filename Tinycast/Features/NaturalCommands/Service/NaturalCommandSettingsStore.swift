import Foundation

/// Owns the single TypeSafe credential's presence; its bytes stay in Keychain until a request starts.
@MainActor
@Observable
final class NaturalCommandSettingsStore {
    enum StoreError: LocalizedError {
        case missingKey
        case keychain

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Enter a TypeSafe API key."
            case .keychain: return "The TypeSafe API key could not be read from Keychain."
            }
        }
    }

    private static let account = UUID(uuidString: "12DB9BEB-7030-4D48-9D42-5641B2ED6364")!
    private let keyStore: KeychainSecretStore
    private(set) var hasAPIKey: Bool
    @ObservationIgnored var onKeyRemoved: (() -> Void)?

    init(keyStore: KeychainSecretStore = .naturalCommandAPIKey) {
        self.keyStore = keyStore
        hasAPIKey = (try? keyStore.hasSecret(for: Self.account)) ?? false
    }

    func saveAPIKey(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw StoreError.missingKey }
        do {
            try keyStore.setSecret(key, for: Self.account)
            hasAPIKey = true
        } catch {
            throw StoreError.keychain
        }
    }

    func removeAPIKey() throws {
        do {
            try keyStore.removeSecret(for: Self.account)
            hasAPIKey = false
            onKeyRemoved?()
        } catch {
            throw StoreError.keychain
        }
    }

    func apiKey() throws -> String {
        do {
            guard let key = try keyStore.secret(for: Self.account), !key.isEmpty else {
                hasAPIKey = false
                onKeyRemoved?()
                throw StoreError.missingKey
            }
            return key
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.keychain
        }
    }
}
