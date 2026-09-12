import Foundation

/// The vendor behind a model, for the picker's row glyph: a template asset tinted like a symbol.
enum AIBrand: String, CaseIterable, Sendable {
    case openAI, claude, gemini, openRouter, x, deepSeek, qwen, mistral, meta, kimi, miniMax
    case perplexity, zai

    var assetName: String {
        switch self {
        case .openAI: return "AIBrandOpenAI"
        case .claude: return "AIBrandClaude"
        case .gemini: return "AIBrandGemini"
        case .openRouter: return "AIBrandOpenRouter"
        case .x: return "AIBrandX"
        case .deepSeek: return "AIBrandDeepSeek"
        case .qwen: return "AIBrandQwen"
        case .mistral: return "AIBrandMistral"
        case .meta: return "AIBrandMeta"
        case .kimi: return "AIBrandKimi"
        case .miniMax: return "AIBrandMiniMax"
        case .perplexity: return "AIBrandPerplexity"
        case .zai: return "AIBrandZAI"
        }
    }

    /// First hit wins: the `vendor/` prefix of router ids, or the family name of a bare id.
    private static let needles: [(AIBrand, [String])] = [
        (.claude, ["anthropic", "claude"]),
        (.openAI, ["openai", "gpt", "chatgpt", "codex"]),
        (.gemini, ["google", "gemini", "gemma"]),
        (.x, ["x-ai", "xai", "grok"]),
        (.deepSeek, ["deepseek"]),
        (.qwen, ["qwen", "qwq", "alibaba"]),
        (.mistral, ["mistral", "mixtral", "codestral", "magistral", "devstral", "ministral"]),
        (.meta, ["meta-llama", "meta/", "llama"]),
        (.kimi, ["moonshot", "kimi"]),
        (.miniMax, ["minimax"]),
        (.perplexity, ["perplexity", "sonar"]),
        (.zai, ["z-ai", "zai", "zhipu", "glm"]),
        (.openRouter, ["openrouter"])
    ]

    /// A vendor endpoint names the brand; aggregators only know it by the model id.
    static func resolve(provider: AIProviderKind, model: String) -> AIBrand? {
        switch provider {
        case .openAI: return .openAI
        case .anthropic: return .claude
        case .gemini: return .gemini
        case .openRouter, .openAICompatible: return resolve(model: model)
        }
    }

    static func resolve(model: String) -> AIBrand? {
        let id = model.lowercased()
        if let hit = needles.first(where: { _, hits in hits.contains { id.contains($0) } }) {
            return hit.0
        }
        // The o-series (`o3`, `o4-mini`, `openai/o1`) is too short to search for as a substring.
        let family = id.split(separator: "/").last ?? Substring(id)
        return family.wholeMatch(of: #/o[134](-.*)?/#) != nil ? .openAI : nil
    }
}
