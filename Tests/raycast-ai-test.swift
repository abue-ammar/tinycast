import Foundation

/// Which route a Raycast extension's `AI.ask` lands on, and what its creativity becomes on the wire.
@main
struct RaycastAITests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static let openAI = UUID()
    static let anthropic = UUID()
    static let router = UUID()

    static var candidates: [RaycastAIModelMatch.Candidate] {
        let selections: [(AIModelSelection, AIProviderKind?)] = [
            (.appleIntelligence, nil),
            (.api(connection: openAI, model: "gpt-4.1", effort: nil), .openAI),
            (.api(connection: openAI, model: "gpt-4o-mini", effort: nil), .openAI),
            (.api(connection: anthropic, model: "claude-sonnet-4-5", effort: nil), .anthropic),
            (.api(connection: anthropic, model: "claude-haiku-4-5", effort: nil), .anthropic),
            (.api(connection: router, model: "deepseek/deepseek-chat", effort: nil), .openRouter),
            (.api(connection: router, model: "google/gemini-2.5-flash", effort: nil), .openRouter),
            (.claude(model: "opus", effort: nil), nil)
        ]
        return selections.map {
            RaycastAIModelMatch.Candidate(
                selection: $0.0, vendor: RaycastAIModelMatch.vendor(of: $0.0, provider: $0.1))
        }
    }

    static func picks(_ requested: String?, fallback: AIModelSelection? = .appleIntelligence)
        -> String?
    {
        RaycastAIModelMatch.choose(requested: requested, candidates: candidates, fallback: fallback)?
            .model
    }

    static func matching() {
        expect(picks(nil) == AppleIntelligence.modelID, "no model asks for the reader's default")
        expect(picks("openai-gpt-4o-mini") == "gpt-4o-mini", "an exact OpenAI model wins")
        expect(picks("openai-gpt-4.1") == "gpt-4.1", "the closest OpenAI name wins")
        expect(picks("openai-gpt-4.1-mini") == "gpt-4o-mini", "the same tier beats the same version")
        expect(
            picks("anthropic-claude-4-5-haiku") == "claude-haiku-4-5",
            "token order and dots do not matter")
        expect(
            picks("anthropic-claude-sonnet-5") == "claude-sonnet-4-5",
            "a newer Raycast model still lands on the reader's same-tier route")
        expect(
            picks("google-gemini-3-flash") == "google/gemini-2.5-flash",
            "a gateway's model id says its vendor")
        expect(
            picks("gateway-deepseek/deepseek-v4-flash") == "deepseek/deepseek-chat",
            "a Raycast gateway prefix names the maker after it")
        expect(picks("perplexity-sonar") == AppleIntelligence.modelID, "an unserved vendor falls back")
        expect(picks("deepseek/deepseek-chat") == "deepseek/deepseek-chat", "{ id } is exact")
        expect(
            picks("anthropic-claude-opus-4-7", fallback: .claude(model: "opus", effort: nil))
                == "opus",
            "the default breaks a tie within its vendor")
        expect(
            picks("openai-gpt-4o", fallback: nil) == "gpt-4o-mini",
            "with no default stored, the vendor's closest route still answers")
        expect(
            RaycastAIModelMatch.choose(requested: "openai-gpt-4o", candidates: [], fallback: nil)
                == nil,
            "no route at all is no answer, which AI.ask reports")
        expect(RaycastAIModelMatch.vendor(ofRaycastModel: "openai_o1-o4-mini") == .openAI, "o-series")
        expect(RaycastAIModelMatch.vendor(ofRaycastModel: "groq-openai/gpt-oss-20b") == .openAI, "groq")
        expect(RaycastAIModelMatch.vendor(ofRaycastModel: "xai-grok-4.5") == .xAI, "xAI")
        expect(RaycastAIModelMatch.vendor(ofModel: "o3") == .openAI, "a bare o3")
        expect(RaycastAIModelMatch.vendor(ofModel: "solar-pro") == nil, "an unknown model has none")
    }

    static func temperature() {
        let configuration = { (provider: AIProviderKind) in
            AIHTTPConfiguration(
                provider: provider, baseURL: URL(string: "https://example.com")!, model: "m")
        }
        let turn = AIRequest(messages: [AIMessage(role: .user, text: "hi")], temperature: 1.5)
        let openAI = AIRequestBody.make(turn, configuration: configuration(.openAI))
        expect(openAI["temperature"] as? Double == 1.5, "OpenAI takes the 0–2 scale as-is")
        let anthropic = AIRequestBody.make(turn, configuration: configuration(.anthropic))
        expect(anthropic["temperature"] as? Double == 0.75, "Anthropic's 0–1 range halves it")
        let plain = AIRequest(messages: [AIMessage(role: .user, text: "hi")])
        expect(
            AIRequestBody.make(plain, configuration: configuration(.openAI))["temperature"] == nil,
            "chat never sends a temperature")
        expect(
            plain.continuing(with: [], tools: []).temperature == nil
                && turn.continuing(with: [], tools: []).temperature == 1.5,
            "a tool round keeps the turn's temperature")
        expect(
            RaycastAIModelMatch.rejectsTemperature(
                "Unsupported value: 'temperature' does not support 0 with this model."),
            "OpenAI's refusal is recognised")
        expect(
            !RaycastAIModelMatch.rejectsTemperature("Invalid API key"),
            "an unrelated failure is not retried")
    }

    static func main() {
        matching()
        temperature()
        print("raycast-ai-test: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
