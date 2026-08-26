import Foundation

struct SSEParser: Sendable {
    private var buffer = ""

    mutating func feed(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        buffer += text
        var events: [String] = []

        while true {
            let rangeLF = buffer.range(of: "\n\n")
            let rangeCRLF = buffer.range(of: "\r\n\r\n")

            let range: Range<String.Index>
            switch (rangeLF, rangeCRLF) {
            case (.some(let lf), .some(let crlf)):
                range = lf.lowerBound < crlf.lowerBound ? lf : crlf
            case (.some(let lf), .none):
                range = lf
            case (.none, .some(let crlf)):
                range = crlf
            case (.none, .none):
                return events
            }

            let frame = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            if let payload = parseFrame(frame) {
                events.append(payload)
            }
        }
    }

    mutating func finish() -> [String] {
        let remaining = buffer
        buffer = ""
        if let payload = parseFrame(remaining) {
            return [payload]
        }
        return []
    }

    private func parseFrame(_ frame: String) -> String? {
        let lines = frame.components(separatedBy: .newlines)
        var dataLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("data:") {
                let after = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                dataLines.append(after)
            }
        }
        guard !dataLines.isEmpty else { return nil }
        return dataLines.joined(separator: "\n")
    }
}

struct AIStreamDecoder: Sendable {
    private let shape: AIHTTPConfiguration.APIShape
    private var parser = SSEParser()
    private(set) var isTerminal = false
    private var usage = AIUsage()

    private struct InFlightToolCall {
        var id: String
        var name: String
        var arguments: String
    }
    private var openAIToolCalls: [Int: InFlightToolCall] = [:]
    private var anthropicToolCalls: [Int: InFlightToolCall] = [:]

    init(shape: AIHTTPConfiguration.APIShape) {
        self.shape = shape
    }

    static func parseError(
        from body: String, status: Int, shape: AIHTTPConfiguration.APIShape
    ) -> AIProviderError {
        if let data = body.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            if let errorObj = json["error"] as? [String: Any],
                let msg = errorObj["message"] as? String, !msg.isEmpty
            {
                return .responseFailed(msg)
            } else if let errorMsg = json["message"] as? String, !errorMsg.isEmpty {
                return .responseFailed(errorMsg)
            }
        }
        return .responseFailed("Request failed with status \(status)")
    }

    mutating func feed(_ chunk: Data) throws -> [AIStreamEvent] {
        guard !isTerminal else { return [] }
        let payloads = parser.feed(chunk)
        return try decode(payloads)
    }

    mutating func feed(line: String) throws -> [AIStreamEvent] {
        guard !isTerminal else { return [] }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let lineData = Data((trimmed + "\n\n").utf8)
        return try feed(lineData)
    }

    mutating func finish() throws -> [AIStreamEvent] {
        guard !isTerminal else { return [] }
        let payloads = parser.finish()
        var events = try decode(payloads)
        events.append(contentsOf: flushTerminal())
        return events
    }

    private mutating func flushPendingToolCalls() -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for (_, call) in openAIToolCalls.sorted(by: { $0.key < $1.key }) {
            if !call.name.isEmpty {
                events.append(.toolCall(AIToolCall(id: call.id, name: call.name, argumentsJSON: call.arguments)))
            }
        }
        openAIToolCalls.removeAll()

        for (_, call) in anthropicToolCalls.sorted(by: { $0.key < $1.key }) {
            if !call.name.isEmpty {
                events.append(.toolCall(AIToolCall(id: call.id, name: call.name, argumentsJSON: call.arguments)))
            }
        }
        anthropicToolCalls.removeAll()
        return events
    }

    private mutating func flushTerminal() -> [AIStreamEvent] {
        guard !isTerminal else { return [] }
        isTerminal = true
        var events = flushPendingToolCalls()
        if !usage.isEmpty { events.append(.usage(usage)) }
        events.append(.finished)
        return events
    }

    private mutating func decode(_ payloads: [String]) throws -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for rawPayload in payloads where !isTerminal {
            let payload = rawPayload.trimmingCharacters(in: .whitespacesAndNewlines)
            if payload.isEmpty { continue }
            if payload == "[DONE]" {
                isTerminal = true
                events.append(contentsOf: flushPendingToolCalls())
                if !usage.isEmpty { events.append(.usage(usage)) }
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
        guard let data = payload.data(using: .utf8) else {
            isTerminal = true
            throw AIProviderError.malformedResponse
        }

        if let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data) {
            // OpenRouter reports a mid-stream failure as a 200 payload, so it's an event, not a status.
            if let message = chunk.error?.message {
                isTerminal = true
                throw AIProviderError.responseFailed(message)
            }
            var events: [AIStreamEvent] = []
            if let choice = chunk.choices?.first {
                if let delta = choice.delta {
                    if let content = delta.content, !content.isEmpty {
                        events.append(.text(content))
                    } else if delta.hasReasoning {
                        events.append(.thinking)
                    }

                    if let toolCalls = delta.toolCalls {
                        for toolChunk in toolCalls {
                            let index = toolChunk.index ?? 0
                            var existing = openAIToolCalls[index] ?? InFlightToolCall(id: "", name: "", arguments: "")
                            if let id = toolChunk.id, !id.isEmpty { existing.id = id }
                            if let funcName = toolChunk.function?.name, !funcName.isEmpty { existing.name = funcName }
                            if let args = toolChunk.function?.arguments, !args.isEmpty { existing.arguments += args }
                            openAIToolCalls[index] = existing
                        }
                    }
                }

                if choice.finishReason == "tool_calls" {
                    events.append(contentsOf: flushPendingToolCalls())
                }
            }
            if let reported = chunk.usage {
                usage.inputTokens = reported.promptTokens ?? usage.inputTokens
                usage.outputTokens = reported.completionTokens ?? usage.outputTokens
            }
            return events
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorObj = json["error"] as? [String: Any], let msg = errorObj["message"] as? String {
                isTerminal = true
                throw AIProviderError.responseFailed(msg)
            } else if let errorStr = json["error"] as? String {
                isTerminal = true
                throw AIProviderError.responseFailed(errorStr)
            } else if let msg = json["message"] as? String {
                isTerminal = true
                throw AIProviderError.responseFailed(msg)
            }

            var events: [AIStreamEvent] = []
            if let choices = json["choices"] as? [[String: Any]], let first = choices.first {
                if let delta = first["delta"] as? [String: Any] {
                    if let content = delta["content"] as? String, !content.isEmpty {
                        events.append(.text(content))
                    } else if (delta["reasoning"] as? String)?.isEmpty == false || (delta["reasoning_content"] as? String)?.isEmpty == false {
                        events.append(.thinking)
                    }

                    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                        for toolChunk in toolCalls {
                            let index = toolChunk["index"] as? Int ?? 0
                            var existing = openAIToolCalls[index] ?? InFlightToolCall(id: "", name: "", arguments: "")
                            if let id = toolChunk["id"] as? String, !id.isEmpty { existing.id = id }
                            if let function = toolChunk["function"] as? [String: Any] {
                                if let funcName = function["name"] as? String, !funcName.isEmpty { existing.name = funcName }
                                if let args = function["arguments"] as? String, !args.isEmpty { existing.arguments += args }
                            }
                            openAIToolCalls[index] = existing
                        }
                    }
                }

                if let finishReason = first["finish_reason"] as? String, finishReason == "tool_calls" {
                    events.append(contentsOf: flushPendingToolCalls())
                }
            }

            if let usageObj = json["usage"] as? [String: Any] {
                if let promptTokens = usageObj["prompt_tokens"] as? Int {
                    usage.inputTokens = promptTokens
                }
                if let completionTokens = usageObj["completion_tokens"] as? Int {
                    usage.outputTokens = completionTokens
                }
            }

            return events
        }

        isTerminal = true
        throw AIProviderError.malformedResponse
    }

    private mutating func decodeAnthropic(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8) else {
            isTerminal = true
            throw AIProviderError.malformedResponse
        }

        if let event = try? JSONDecoder().decode(AnthropicEvent.self, from: data) {
            var events: [AIStreamEvent] = []
            switch event.type {
            case "content_block_start":
                if let block = event.contentBlock, block.type == "tool_use", let index = event.index {
                    anthropicToolCalls[index] = InFlightToolCall(
                        id: block.id ?? "",
                        name: block.name ?? "",
                        arguments: ""
                    )
                }
            case "content_block_delta":
                if let delta = event.delta {
                    if let text = delta.text, !text.isEmpty {
                        events.append(.text(text))
                    }
                    if let partial = delta.partialJson, !partial.isEmpty, let index = event.index {
                        var existing = anthropicToolCalls[index] ?? InFlightToolCall(id: "", name: "", arguments: "")
                        existing.arguments += partial
                        anthropicToolCalls[index] = existing
                    }
                }
            case "content_block_stop":
                break
            case "message_delta":
                if let usage = event.usage?.outputTokens { self.usage.outputTokens = usage }
                if event.delta?.stopReason == "tool_use" {
                    events.append(contentsOf: flushPendingToolCalls())
                }
            case "message_start":
                if let usage = event.message?.usage?.inputTokens {
                    self.usage.inputTokens = usage
                }
            case "message_stop":
                events.append(contentsOf: flushPendingToolCalls())
                if !usage.isEmpty { events.append(.usage(usage)) }
                events.append(.finished)
                isTerminal = true
            case "error":
                isTerminal = true
                throw AIProviderError.responseFailed(Self.anthropicErrorMessage(event.error?.type))
            default:
                break
            }
            return events
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorObj = json["error"] as? [String: Any], let msg = errorObj["message"] as? String {
                isTerminal = true
                throw AIProviderError.responseFailed(msg)
            } else if let errorStr = json["error"] as? String {
                isTerminal = true
                throw AIProviderError.responseFailed(errorStr)
            }
        }

        isTerminal = true
        throw AIProviderError.malformedResponse
    }

    private static func anthropicErrorMessage(_ type: String?) -> String {
        switch type {
        case "invalid_request_error": return "Invalid request sent to Anthropic."
        case "authentication_error": return "API key rejected — check it in Settings."
        case "permission_error": return "The provider rejected this key's permissions."
        case "not_found_error": return "The requested Anthropic model was not found."
        case "rate_limit_error": return "Rate limit hit. Try again shortly."
        case "overloaded_error": return "The provider is overloaded. Try again shortly."
        default: return "The Anthropic request failed."
        }
    }
}

private struct OpenAIChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct ReasoningDetail: Decodable { let text: String? }
            struct ToolCallFunctionChunk: Decodable {
                let name: String?
                let arguments: String?
            }
            struct ToolCallChunk: Decodable {
                let index: Int?
                let id: String?
                let type: String?
                let function: ToolCallFunctionChunk?
            }

            let content: String?
            let reasoning: String?
            let reasoningDetails: [ReasoningDetail]?
            let toolCalls: [ToolCallChunk]?

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

        let index: Int?
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
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
        let partialJson: String?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJson = "partial_json"
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
