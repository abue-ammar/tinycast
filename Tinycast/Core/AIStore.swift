import Foundation
import Security

/// Message in the AI conversation history.
struct AIMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// AI provider configuration.
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case anthropic = "Anthropic"

    var id: String { rawValue }
    var apiEndpoint: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        }
    }
}

/// Model selection for each provider.
enum AIModel: String, CaseIterable, Identifiable, Sendable {
    case claude35Sonnet = "claude-3-5-sonnet-20241022"
    case claude35Haiku = "claude-3-5-haiku-20241022"
    case claude3Opus = "claude-3-opus-20240229"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .claude35Sonnet: return "Claude 3.5 Sonnet"
        case .claude35Haiku: return "Claude 3.5 Haiku"
        case .claude3Opus: return "Claude 3 Opus"
        }
    }
}

/// Manages AI chat conversations: network requests, API key storage, conversation history.
/// Follows the CurrencyRateStore pattern: consent-gated, network access requires explicit opt-in.
@MainActor
final class AIStore: ObservableObject {
    static let provider = AIProvider.anthropic
    static let providerURL = URL(string: "https://anthropic.com")!

    /// Explicit user consent, persisted separately from AppSettings so imports can't grant network.
    @Published private(set) var isEnabled: Bool

    /// Current conversation history (empty when disabled).
    @Published private(set) var messages: [AIMessage] = []

    /// Currently streaming response text (partial assistant message).
    @Published private(set) var streamingText: String = ""

    /// True while a request is in flight.
    @Published private(set) var isLoading: Bool = false

    /// Last error message (for UI display).
    @Published private(set) var lastError: String?

    /// Selected model.
    @Published var selectedModel: AIModel {
        didSet {
            defaults.set(selectedModel.rawValue, forKey: Self.modelKey)
        }
    }

    private static let consentKey = "aiChatEnabled"
    private static let modelKey = "aiChatModel"
    private static let historyKey = "aiChatHistory"
    private let defaults = UserDefaults.standard
    private var streamTask: Task<Void, Never>?

    // Keychain keys for API key storage
    private static let keychainService = "com.tinycast.app.ai"
    private static let keychainAccount = "anthropic-api-key"

    init() {
        isEnabled = defaults.bool(forKey: Self.consentKey)
        selectedModel = defaults.string(forKey: Self.modelKey)
            .flatMap(AIModel.init) ?? .claude35Sonnet

        // Load conversation history from UserDefaults
        if isEnabled, let data = defaults.data(forKey: Self.historyKey),
           let loaded = try? JSONDecoder().decode([AIMessage].self, from: data) {
            messages = loaded
        }
    }

    /// Toggle consent (Settings integration point).
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)

        if !enabled {
            // Revoke: clear history and cancel any in-flight requests
            streamTask?.cancel()
            streamTask = nil
            messages = []
            streamingText = ""
            lastError = nil
            defaults.removeObject(forKey: Self.historyKey)
        }
    }

    /// Send a user message and stream the assistant's response.
    func sendMessage(_ text: String) async {
        guard isEnabled else {
            lastError = "AI Chat is disabled. Enable it in Settings."
            return
        }
        guard let apiKey = loadAPIKey(), !apiKey.isEmpty else {
            lastError = "API key not configured. Set it in Settings."
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = AIMessage(role: .user, content: text)
        messages.append(userMessage)
        saveHistory()

        isLoading = true
        lastError = nil
        streamingText = ""

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.streamResponse(apiKey: apiKey)
        }
    }

    /// Send a message in the background (when palette is closed) and notify when done.
    func sendMessageInBackground(_ text: String) async {
        let wasClosed = await !AppCore.shared.windowController.isVisible

        await sendMessage(text)

        // Wait for response to complete
        while await self.isLoading {
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Send notification if palette was closed
        if wasClosed, let lastMessage = await self.messages.last,
           lastMessage.role == .assistant {
            let preview = String(lastMessage.content.prefix(100))
            await AINotificationManager.shared.notifyResponseReceived(preview: preview)
        }
    }

    /// Clear conversation history.
    func clearHistory() {
        messages = []
        streamingText = ""
        lastError = nil
        saveHistory()
    }

    // MARK: - API Key Management (Keychain)

    /// Store API key securely in Keychain.
    func saveAPIKey(_ key: String) -> Bool {
        let data = key.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary) // Remove old
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Load API key from Keychain.
    func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Delete API key from Keychain.
    func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Private

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        defaults.set(data, forKey: Self.historyKey)
    }

    private nonisolated func streamResponse(apiKey: String) async {
        let conversationMessages = await messages.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let requestBody: [String: Any] = [
            "model": await selectedModel.rawValue,
            "max_tokens": 4096,
            "messages": conversationMessages,
            "stream": true
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            await MainActor.run { self.finishWithError("Failed to encode request") }
            return
        }

        var request = URLRequest(url: URL(string: AIProvider.anthropic.apiEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)

        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run { self.finishWithError("Invalid response") }
                return
            }

            guard httpResponse.statusCode == 200 else {
                let errorMsg = "API error: \(httpResponse.statusCode)"
                await MainActor.run { self.finishWithError(errorMsg) }
                return
            }

            var accumulatedText = ""

            for try await line in bytes.lines {
                // Re-check consent after each chunk (can be revoked mid-stream)
                guard await self.isEnabled else { return }

                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                guard jsonString != "[DONE]" else { break }

                guard let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else { continue }

                if type == "content_block_delta",
                   let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    accumulatedText += text
                    await MainActor.run {
                        self.streamingText = accumulatedText
                    }
                }
            }

            await MainActor.run {
                if !accumulatedText.isEmpty {
                    let assistantMessage = AIMessage(role: .assistant, content: accumulatedText)
                    self.messages.append(assistantMessage)
                    self.saveHistory()
                }
                self.streamingText = ""
                self.isLoading = false
            }

        } catch {
            await MainActor.run {
                self.finishWithError(error.localizedDescription)
            }
        }
    }

    private func finishWithError(_ message: String) {
        lastError = message
        streamingText = ""
        isLoading = false
    }
}
