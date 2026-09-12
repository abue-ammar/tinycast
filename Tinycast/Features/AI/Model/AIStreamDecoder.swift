import Foundation

struct SSEParser: Sendable {
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var payloads: [String] = []
        while let boundary = nextBoundary() {
            let frame = buffer[..<boundary.lowerBound]
            buffer.removeSubrange(buffer.startIndex..<boundary.upperBound)
            if let payload = Self.payload(in: frame) { payloads.append(payload) }
        }
        return payloads
    }

    mutating func finish() -> [String] {
        guard !buffer.isEmpty else { return [] }
        defer { buffer.removeAll() }
        return Self.payload(in: buffer).map { [$0] } ?? []
    }

    private func nextBoundary() -> Range<Data.Index>? {
        let lf = buffer.range(of: Data([0x0A, 0x0A]))
        let crlf = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
        switch (lf, crlf) {
        case (let lhs?, let rhs?): return lhs.lowerBound < rhs.lowerBound ? lhs : rhs
        case (let range?, nil), (nil, let range?): return range
        case (nil, nil): return nil
        }
    }

    private static func payload(in frame: some DataProtocol) -> String? {
        let text = String(decoding: frame, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
        var dataLines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue }
            if line == "data" {
                dataLines.append("")
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst(5)
                if value.first == " " { value = value.dropFirst() }
                dataLines.append(String(value))
            }
        }
        return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
    }
}

struct AIStreamDecoder: Sendable {
    /// A call arrives in fragments keyed by index, with its id and name only on the first one.
    private struct PartialToolCall {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private let shape: AIHTTPConfiguration.APIShape
    private var parser = SSEParser()
    private var usage = AIUsage()
    private var partialToolCalls: [Int: PartialToolCall] = [:]
    private(set) var isTerminal = false

    init(shape: AIHTTPConfiguration.APIShape) {
        self.shape = shape
    }

    /// Assembled in index order, so a turn's calls reach the loop as the model listed them.
    private mutating func flushToolCalls() -> [AIStreamEvent] {
        guard !partialToolCalls.isEmpty else { return [] }
        let calls = partialToolCalls.sorted { $0.key < $1.key }.map(\.value)
        partialToolCalls.removeAll()
        return calls.compactMap { call in
            guard !call.name.isEmpty else { return nil }
            return .toolCallRequested(
                AIToolCall(id: call.id, name: call.name, arguments: call.arguments))
        }
    }

    mutating func feed(_ data: Data) throws -> [AIStreamEvent] {
        try decode(parser.feed(data))
    }

    mutating func finish() throws -> [AIStreamEvent] {
        try decode(parser.finish())
    }

    private mutating func decode(_ payloads: [String]) throws -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for payload in payloads where !isTerminal {
            if payload == "[DONE]" {
                isTerminal = true
                events.append(contentsOf: flushToolCalls())
                events.append(.finished)
                continue
            }
            switch shape {
            case .openAICompatible:
                events.append(contentsOf: try decodeOpenAI(payload))
            case .anthropic:
                events.append(contentsOf: try decodeAnthropic(payload))
            }
        }
        return events
    }

    private mutating func decodeOpenAI(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8),
            let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data)
        else {
            isTerminal = true
            throw AIProviderError.malformedResponse
        }

        // OpenRouter reports a mid-stream failure as a 200 payload, so it's an event, not a status.
        if let message = chunk.error?.message {
            isTerminal = true
            throw AIProviderError.responseFailed(message)
        }
        var events: [AIStreamEvent] = []
        if let choice = chunk.choices?.first {
            if let content = choice.delta?.content, !content.isEmpty {
                events.append(.text(content))
            } else if choice.delta?.hasReasoning == true {
                events.append(.thinking)
            }
            for fragment in choice.delta?.toolCalls ?? [] { absorb(fragment) }
            if choice.finishReason == "tool_calls" { events.append(contentsOf: flushToolCalls()) }
        }
        if let reported = chunk.usage {
            usage.inputTokens = reported.promptTokens ?? usage.inputTokens
            usage.outputTokens = reported.completionTokens ?? usage.outputTokens
            events.append(.usage(usage))
        }
        return events
    }

    /// A fragment's index is the only stable handle; a gateway may omit it when there is one call.
    private mutating func absorb(_ fragment: OpenAIChunk.Choice.Delta.ToolCall) {
        var partial = partialToolCalls[fragment.index ?? 0] ?? PartialToolCall()
        if let id = fragment.id, !id.isEmpty { partial.id = id }
        if let name = fragment.function?.name, !name.isEmpty { partial.name = name }
        partial.arguments += fragment.function?.arguments ?? ""
        partialToolCalls[fragment.index ?? 0] = partial
    }

    private mutating func decodeAnthropic(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8),
            let event = try? JSONDecoder().decode(AnthropicEvent.self, from: data)
        else {
            isTerminal = true
            throw AIProviderError.malformedResponse
        }

        switch event.type {
        case "content_block_start":
            guard event.contentBlock?.type == "tool_use" else { return [] }
            partialToolCalls[event.index ?? 0] = PartialToolCall(
                id: event.contentBlock?.id ?? "", name: event.contentBlock?.name ?? "",
                arguments: "")
            return []
        case "content_block_delta":
            if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                return [.text(text)]
            }
            if event.delta?.type == "input_json_delta" {
                partialToolCalls[event.index ?? 0]?.arguments += event.delta?.partialJSON ?? ""
                return []
            }
            return event.delta?.type == "thinking_delta" ? [.thinking] : []
        case "message_start":
            usage.inputTokens = event.message?.usage?.inputTokens ?? usage.inputTokens
            return [.usage(usage)]
        case "message_delta":
            usage.outputTokens = event.usage?.outputTokens ?? usage.outputTokens
            // The calls are complete here, and `message_stop` may never arrive on a tool turn.
            guard event.delta?.stopReason == "tool_use" else { return [.usage(usage)] }
            return [.usage(usage)] + flushToolCalls()
        case "message_stop":
            isTerminal = true
            return flushToolCalls() + [.finished]
        case "error":
            isTerminal = true
            throw AIProviderError.responseFailed(Self.anthropicErrorMessage(event.error?.type))
        default:
            return []
        }
    }

    private static func anthropicErrorMessage(_ type: String?) -> String {
        switch type {
        case "authentication_error": return "API key rejected — check it in Settings."
        case "rate_limit_error": return "Rate limit reached — try again later."
        default: return "The provider stopped the response with an error."
        }
    }
}

private struct OpenAIChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct ReasoningDetail: Decodable { let text: String? }

            struct ToolCall: Decodable {
                struct Function: Decodable {
                    let name: String?
                    let arguments: String?
                }

                let index: Int?
                let id: String?
                let function: Function?
            }

            let content: String?
            let reasoning: String?
            let reasoningDetails: [ReasoningDetail]?
            let toolCalls: [ToolCall]?

            var hasReasoning: Bool {
                reasoning?.isEmpty == false
                    || reasoningDetails?.contains(where: { $0.text?.isEmpty == false }) == true
            }

            enum CodingKeys: String, CodingKey {
                case content, reasoning
                case reasoningDetails = "reasoning_details"
                case toolCalls = "tool_calls"
            }
        }

        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    struct ErrorBody: Decodable { let message: String? }

    let choices: [Choice]?
    let usage: Usage?
    let error: ErrorBody?
}

private struct AnthropicEvent: Decodable {
    struct Delta: Decodable {
        let type: String?
        let text: String?
        let partialJSON: String?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJSON = "partial_json"
            case stopReason = "stop_reason"
        }
    }

    struct ContentBlock: Decodable {
        let type: String?
        let id: String?
        let name: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    struct Message: Decodable { let usage: Usage? }
    struct ErrorBody: Decodable { let type: String? }

    let type: String
    let index: Int?
    let delta: Delta?
    let contentBlock: ContentBlock?
    let usage: Usage?
    let message: Message?
    let error: ErrorBody?

    enum CodingKeys: String, CodingKey {
        case type, index, delta, usage, message, error
        case contentBlock = "content_block"
    }
}
