import Foundation

struct AIResponsesDecoder: Sendable {
    private let secrets: [String]
    private var citations = AICitationLinker()
    private(set) var isTerminal = false

    init(secrets: [String]) {
        self.secrets = secrets
    }

    mutating func decode(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8),
            let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = event["type"] as? String
        else {
            throw AIProviderError.malformedResponse
        }
        switch type {
        case "response.output_text.delta", "response.refusal.delta":
            guard let delta = event["delta"] as? String else {
                throw AIProviderError.malformedResponse
            }
            guard !delta.isEmpty else { return [] }
            citations.record(delta)
            return [.text(delta)]
        case "response.output_item.added":
            let item = event["item"] as? [String: Any]
            switch item?["type"] as? String {
            case "reasoning": return [.thinking]
            case "web_search_call": return [.searching(nil)]
            default: return []
            }
        case "response.output_item.done":
            guard let item = event["item"] as? [String: Any],
                item["type"] as? String == "web_search_call"
            else { return [] }
            return [.searched(Self.query(of: item))]
        case "response.output_text.annotation.added":
            guard let annotation = event["annotation"] as? [String: Any],
                annotation["type"] as? String == "url_citation",
                let url = annotation["url"] as? String,
                let link = citations.link(to: url)
            else { return [] }
            return [.text(link)]
        case "response.completed":
            guard let response = event["response"] as? [String: Any],
                let output = response["output"] as? [[String: Any]]
            else { throw AIProviderError.malformedResponse }
            var events: [AIStreamEvent] = []
            for item in output where item["type"] as? String == "function_call" {
                guard let id = item["call_id"] as? String, !id.isEmpty,
                    let name = item["name"] as? String, !name.isEmpty,
                    let arguments = item["arguments"] as? String
                else { throw AIProviderError.malformedResponse }
                events.append(.toolCallRequested(AIToolCall(id: id, name: name, arguments: arguments)))
            }
            if !events.isEmpty { events.insert(.responseOutput(output.map(JSONValue.init)), at: 0) }
            if let usage = response["usage"] as? [String: Any] {
                events.append(.usage(Self.usage(usage)))
            }
            isTerminal = true
            return events + [.finished]
        case "response.failed", "response.incomplete", "error":
            let response = event["response"] as? [String: Any] ?? event
            let error = response["error"] as? [String: Any]
            let details = response["incomplete_details"] as? [String: Any]
            throw AIProviderError.responseFailed(
                AIProviderFailure.described(
                    AIProviderFailure.stopped,
                    said: error?["message"] as? String ?? response["message"] as? String
                        ?? details?["reason"] as? String,
                    secrets: secrets))
        default:
            return []
        }
    }

    private static func query(of item: [String: Any]) -> String? {
        let action = item["action"] as? [String: Any]
        return action?["query"] as? String ?? (action?["queries"] as? [String])?.first
    }

    private static func usage(_ value: [String: Any]) -> AIUsage {
        let outputDetails = value["output_tokens_details"] as? [String: Any]
        return AIUsage(
            inputTokens: value["input_tokens"] as? Int,
            outputTokens: value["output_tokens"] as? Int,
            reasoningTokens: outputDetails?["reasoning_tokens"] as? Int)
    }
}
