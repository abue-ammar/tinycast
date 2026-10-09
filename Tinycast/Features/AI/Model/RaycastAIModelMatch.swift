import Foundation

/// Raycast names hosted models; the reader's closest route of that vendor answers, or the default.
enum RaycastAIModelMatch {
    enum Vendor: String, Sendable, CaseIterable {
        case openAI, anthropic, google, xAI, mistral, perplexity
        case deepSeek, zhipu, moonshot, alibaba, meta
    }

    struct Candidate: Equatable, Sendable {
        let selection: AIModelSelection
        let vendor: Vendor?
    }

    static func choose(
        requested: String?, candidates: [Candidate], fallback: AIModelSelection?
    ) -> AIModelSelection? {
        let fallback = fallback.flatMap { selection in
            candidates.contains { $0.selection == selection } ? selection : nil
        } ?? candidates.first?.selection
        guard let requested = requested?.trimmingCharacters(in: .whitespaces).lowercased(),
            !requested.isEmpty
        else { return fallback }
        // `{ id }` names a model of the reader's own, which beats any vendor guess.
        if let exact = candidates.first(where: { $0.selection.model.lowercased() == requested }) {
            return exact.selection
        }
        guard let vendor = vendor(ofRaycastModel: requested) else { return fallback }
        let wanted = tokens(of: modelPart(ofRaycastModel: requested))
        var best: AIModelSelection?
        var bestScore = -Double.infinity
        for candidate in candidates where candidate.vendor == vendor {
            let have = tokens(of: candidate.selection.model)
            var score = wanted.intersection(have).reduce(0) { $0 + weight(of: $1) }
                - 0.1 * Double(have.subtracting(wanted).count)
            if candidate.selection == fallback { score += 0.05 }
            if score > bestScore {
                best = candidate.selection
                bestScore = score
            }
        }
        return best ?? fallback
    }

    /// A gateway (`groq-openai/…`, `gateway-deepseek/…`) is a host, so the maker after it decides.
    static func vendor(ofRaycastModel id: String) -> Vendor? {
        let id = id.lowercased()
        for gateway in ["gateway-", "groq-", "together-", "fireworks-"] where id.hasPrefix(gateway) {
            let rest = String(id.dropFirst(gateway.count))
            return vendor(ofPrefix: leadingWord(rest)) ?? vendor(ofModel: rest)
        }
        return vendor(ofPrefix: leadingWord(id)) ?? vendor(ofModel: id)
    }

    /// The vendor behind a model id a route reports: `claude-sonnet-4`, `anthropic/claude…`, `o3`.
    static func vendor(ofModel id: String) -> Vendor? {
        let id = id.lowercased()
        if let slash = id.firstIndex(of: "/"), let vendor = vendor(ofPrefix: String(id[..<slash])) {
            return vendor
        }
        let keywords: [(String, Vendor)] = [
            ("claude", .anthropic), ("gpt", .openAI), ("chatgpt", .openAI), ("codex", .openAI),
            ("gemini", .google), ("gemma", .google), ("grok", .xAI), ("mistral", .mistral),
            ("codestral", .mistral), ("magistral", .mistral), ("devstral", .mistral),
            ("sonar", .perplexity), ("deepseek", .deepSeek), ("glm", .zhipu), ("kimi", .moonshot),
            ("qwen", .alibaba), ("llama", .meta)
        ]
        for (keyword, vendor) in keywords where id.contains(keyword) { return vendor }
        let reasoning = ["o1", "o3", "o4"]
        if reasoning.contains(where: { id == $0 || id.hasPrefix($0 + "-") }) { return .openAI }
        return nil
    }

    /// Settings already says who serves a vendor's own API; a gateway's model id has to say it.
    static func vendor(of selection: AIModelSelection, provider: AIProviderKind?) -> Vendor? {
        switch selection {
        case .appleIntelligence: return nil
        case .codex: return .openAI
        case .claude: return .anthropic
        case .grok: return .xAI
        case .openCode(let model, _), .cursor(let model, _): return vendor(ofModel: model)
        case .api(_, let model, _):
            switch provider {
            case .openAI: return .openAI
            case .anthropic: return .anthropic
            case .gemini: return .google
            case .openRouter, .openAICompatible, nil: return vendor(ofModel: model)
            }
        }
    }

    /// GPT-5 and the o-series refuse any temperature but their own; such a reply is retried bare.
    static func rejectsTemperature(_ message: String) -> Bool {
        let message = message.lowercased()
        return message.contains("temperature")
            && (message.contains("unsupported") || message.contains("not support")
                || message.contains("does not support") || message.contains("invalid")
                || message.contains("only the default"))
    }

    private static func vendor(ofPrefix prefix: String) -> Vendor? {
        switch prefix {
        case "openai": return .openAI
        case "anthropic": return .anthropic
        case "google", "gemini": return .google
        case "xai", "x-ai", "grok": return .xAI
        case "mistral", "mistralai": return .mistral
        case "perplexity": return .perplexity
        case "deepseek": return .deepSeek
        case "zai", "z-ai", "zhipu", "zhipuai": return .zhipu
        case "moonshot", "moonshotai": return .moonshot
        case "alibaba", "qwen": return .alibaba
        case "meta", "meta-llama": return .meta
        default: return nil
        }
    }

    private static func leadingWord(_ id: String) -> String {
        String(id.prefix { $0.isLetter || $0.isNumber })
    }

    /// The model half of a Raycast id, so `openai-gpt-4o-mini` compares as `gpt-4o-mini`.
    private static func modelPart(ofRaycastModel id: String) -> String {
        var id = id
        for gateway in ["gateway-", "groq-", "together-", "fireworks-"] where id.hasPrefix(gateway) {
            id = String(id.dropFirst(gateway.count))
        }
        if let slash = id.firstIndex(of: "/") { return String(id[id.index(after: slash)...]) }
        let word = leadingWord(id)
        guard vendor(ofPrefix: word) != nil else { return id }
        return String(id.dropFirst(word.count).drop { !($0.isLetter || $0.isNumber) })
    }

    /// A tier (`haiku`, `mini`, `flash`) says more than a version, and a family name says nothing.
    private static func weight(of token: String) -> Double {
        if familyNames.contains(token) { return 0 }
        return token.first?.isNumber == true ? 0.3 : 1
    }

    private static let familyNames: Set<String> = [
        "claude", "gpt", "chatgpt", "gemini", "gemma", "grok", "mistral", "deepseek", "llama",
        "qwen", "glm", "kimi", "sonar"
    ]

    /// `claude-4-5-haiku` and `claude-haiku-4.5` share every token, whatever the order or dots.
    private static func tokens(of id: String) -> Set<String> {
        let parts = id.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
        var tokens = Set<String>()
        for part in parts {
            // `gpt4o` and `4o` both read as their letter and digit runs.
            var run = ""
            for character in part {
                if let last = run.last, last.isNumber != character.isNumber {
                    tokens.insert(run)
                    run = ""
                }
                run.append(character)
            }
            if !run.isEmpty { tokens.insert(run) }
        }
        return tokens
    }
}
