import Foundation

/// Providers whose OpenAI-compatible roots Tinycast knows, so the settings pane can fill the
/// base URL instead of making the user look one up. Every URL ends before
/// `/chat/completions` — that suffix belongs to `AICompletionRequest`, never to this list.
struct AIProvider: Hashable, Identifiable, Sendable {
    /// Stable identifier the picker selection keys on; also the display name.
    var id: String { name }
    let name: String
    let baseURL: String
    var defaultModel: String = "gpt-4o-mini"
    /// Vector asset icon name in `Assets.xcassets`, if available.
    var iconName: String? = nil
    /// SF Symbol fallback when no vector asset exists.
    var symbolFallback: String = "sparkles"
    /// Local servers ignore the key entirely; saying so spares the user hunting for one.
    var isLocal: Bool = false
    /// True when authenticated via OAuth 2.0 PKCE with a user subscription (ChatGPT Plus/Pro/Team).
    var isOAuth: Bool = false
    /// The picker's escape hatch: any other OpenAI-compatible root, typed by hand.
    static let customID = "custom"

    /// Verified against each provider's own documentation and models.dev SVG assets.
    static let catalog: [AIProvider] = [
        AIProvider(
            name: "ChatGPT (Subscription)",
            baseURL: "https://chatgpt.com/backend-api/codex",
            defaultModel: "gpt-4o",
            iconName: "ProviderOpenAI",
            isOAuth: true
        ),
        AIProvider(
            name: "OpenAI (API Key)", baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini",
            iconName: "ProviderOpenAI"),
        AIProvider(
            name: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            defaultModel: "gemini-3.7-flash",
            iconName: "ProviderGoogle"
        ),
        AIProvider(
            name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini",
            iconName: "ProviderOpenRouter"),
        AIProvider(
            name: "Groq", baseURL: "https://api.groq.com/openai/v1",
            defaultModel: "llama-3.3-70b-versatile", iconName: "ProviderGroq"),
        AIProvider(
            name: "Mistral", baseURL: "https://api.mistral.ai/v1",
            defaultModel: "mistral-small-latest", iconName: "ProviderMistral"),
        AIProvider(
            name: "DeepSeek", baseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-chat", iconName: "ProviderDeepSeek"),
        AIProvider(
            name: "xAI (Grok)", baseURL: "https://api.x.ai/v1", defaultModel: "grok-2-latest",
            iconName: "ProviderXAI"),
        AIProvider(
            name: "Perplexity", baseURL: "https://api.perplexity.ai", defaultModel: "sonar",
            iconName: "ProviderPerplexity"),
        AIProvider(
            name: "Cohere", baseURL: "https://api.cohere.ai/v1", defaultModel: "command-r-plus",
            iconName: "ProviderCohere"),
        AIProvider(
            name: "Together", baseURL: "https://api.together.xyz/v1",
            defaultModel: "meta-llama/Llama-3.3-70B-Instruct-Turbo", iconName: "ProviderTogether"),
        AIProvider(
            name: "Fireworks", baseURL: "https://api.fireworks.ai/inference/v1",
            defaultModel: "accounts/fireworks/models/llama-v3p3-70b-instruct", iconName: "ProviderFireworks"
        ),
        AIProvider(
            name: "Cerebras", baseURL: "https://api.cerebras.ai/v1",
            defaultModel: "llama-3.3-70b", iconName: "ProviderCerebras"),
        AIProvider(
            name: "Hugging Face",
            baseURL: "https://api-inference.huggingface.co/v1",
            defaultModel: "meta-llama/Llama-3.3-70B-Instruct",
            iconName: "ProviderHuggingFace"
        ),
        AIProvider(
            name: "Ollama",
            baseURL: "http://localhost:11434/v1",
            defaultModel: "llama3.2",
            iconName: "ProviderOllama",
            symbolFallback: "server.rack",
            isLocal: true
        ),
        AIProvider(
            name: "LM Studio",
            baseURL: "http://localhost:1234/v1",
            defaultModel: "local-model",
            symbolFallback: "desktopcomputer",
            isLocal: true
        ),
        AIProvider(
            name: "vLLM",
            baseURL: "http://localhost:8000/v1",
            defaultModel: "local-model",
            symbolFallback: "server.rack",
            isLocal: true
        )
    ]

    /// Matches a configured base URL back to its provider, tolerating a trailing slash so a
    /// hand-edited field still reads as the provider it came from.
    static func matching(baseURL: String) -> AIProvider? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var normalized = trimmed
        while normalized.hasSuffix("/") { normalized.removeLast() }
        return catalog.first { $0.baseURL == normalized }
    }
}
