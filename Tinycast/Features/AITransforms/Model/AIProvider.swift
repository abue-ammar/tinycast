import Foundation

/// Providers whose OpenAI-compatible roots Tinycast knows, so the settings pane can fill the
/// base URL instead of making the user look one up. Every URL ends before
/// `/chat/completions` — that suffix belongs to `AICompletionRequest`, never to this list.
struct AIProvider: Hashable, Identifiable, Sendable {
    /// Stable identifier the picker selection keys on; also the display name.
    var id: String { name }
    let name: String
    let baseURL: String
    /// Local servers ignore the key entirely; saying so spares the user hunting for one.
    let isLocal: Bool

    init(name: String, baseURL: String, isLocal: Bool = false) {
        self.name = name
        self.baseURL = baseURL
        self.isLocal = isLocal
    }

    /// The picker's escape hatch: any other OpenAI-compatible root, typed by hand.
    static let customID = "custom"

    /// Verified against each provider's own documentation. Groq mounts under `/openai/v1`,
    /// Gemini's compatibility layer lives at `/v1beta/openai`, and Anthropic's OpenAI SDK
    /// surface is `/v1` — none of them are bare `/v1` by accident.
    static let catalog: [AIProvider] = [
        AIProvider(name: "OpenAI", baseURL: "https://api.openai.com/v1"),
        AIProvider(name: "Anthropic", baseURL: "https://api.anthropic.com/v1"),
        AIProvider(name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai"),
        AIProvider(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1"),
        AIProvider(name: "Groq", baseURL: "https://api.groq.com/openai/v1"),
        AIProvider(name: "Mistral", baseURL: "https://api.mistral.ai/v1"),
        AIProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1"),
        AIProvider(name: "xAI (Grok)", baseURL: "https://api.x.ai/v1"),
        AIProvider(name: "Together", baseURL: "https://api.together.xyz/v1"),
        AIProvider(name: "Fireworks", baseURL: "https://api.fireworks.ai/inference/v1"),
        AIProvider(name: "Cerebras", baseURL: "https://api.cerebras.ai/v1"),
        AIProvider(name: "Ollama", baseURL: "http://localhost:11434/v1", isLocal: true),
        AIProvider(name: "LM Studio", baseURL: "http://localhost:1234/v1", isLocal: true),
        AIProvider(name: "vLLM", baseURL: "http://localhost:8000/v1", isLocal: true)
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
