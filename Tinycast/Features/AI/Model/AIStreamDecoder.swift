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

/// Sources an API cites beside its text, inlined as the Markdown links `ChatReferences` reads.
struct AICitationLinker: Sendable {
    private var text = ""
    private var linked: Set<String> = []

    mutating func record(_ delta: String) {
        text += delta
    }

    /// Nil for a page the reply already links, so a source the model wrote itself is not repeated.
    mutating func link(to string: String) -> String? {
        guard let url = URL(string: string), url.scheme == "https" || url.scheme == "http",
            !text.contains(string), linked.insert(string).inserted
        else { return nil }
        let target = string.replacing("(", with: "%28").replacing(")", with: "%29")
        return " ([\(ChatReference.host(of: url))](\(target)))"
    }
}

struct AIStreamDecoder: Sendable {
    /// A call arrives in fragments keyed by index, with its id and name only on the first one.
    private struct PartialToolCall {
        var id = ""
        var name = ""
        var arguments = ""
        var thoughtSignature: String?
    }

    private let shape: AIHTTPConfiguration.APIShape
    /// What a provider's own error text must never show; the decoder is handed it, never reads it.
    private let secrets: [String]
    private var parser = SSEParser()
    private var thinkTags = AIThinkTagDecoder()
    private var responses: AIResponsesDecoder
    private var usage = AIUsage()
    private var partialToolCalls: [Int: PartialToolCall] = [:]
    private var citations = AICitationLinker()
    private var citedURLs: [Int: [String]] = [:]
    private var searchIndex: Int?
    private var searchInput = ""
    private(set) var isTerminal = false

    init(shape: AIHTTPConfiguration.APIShape, secrets: [String] = []) {
        self.shape = shape
        self.secrets = secrets
        responses = AIResponsesDecoder(secrets: secrets)
    }

    /// Assembled in index order, so a turn's calls reach the loop as the model listed them.
    private mutating func flushToolCalls() -> [AIStreamEvent] {
        guard !partialToolCalls.isEmpty else { return [] }
        let calls = partialToolCalls.sorted { $0.key < $1.key }.map(\.value)
        partialToolCalls.removeAll()
        return calls.compactMap { call in
            guard !call.name.isEmpty else { return nil }
            return .toolCallRequested(
                AIToolCall(
                    id: call.id, name: call.name, arguments: call.arguments,
                    thoughtSignature: call.thoughtSignature))
        }
    }

    mutating func feed(_ data: Data) throws -> [AIStreamEvent] {
        try decode(parser.feed(data))
    }

    mutating func finish() throws -> [AIStreamEvent] {
        var events = try decode(parser.finish())
        if shape == .openAICompatible, !isTerminal { events += thinkTags.finish() }
        return events
    }

    private mutating func decode(_ payloads: [String]) throws -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for payload in payloads where !isTerminal {
            if payload == "[DONE]", shape != .openAIResponses {
                isTerminal = true
                if shape == .openAICompatible { events += thinkTags.finish() }
                events.append(contentsOf: flushToolCalls())
                events.append(.finished)
                continue
            }
            switch shape {
            case .openAIResponses:
                do {
                    events.append(contentsOf: try responses.decode(payload))
                    isTerminal = responses.isTerminal
                } catch {
                    isTerminal = true
                    throw error
                }
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
        if chunk.error?.message != nil {
            isTerminal = true
            throw AIProviderError.responseFailed(
                AIProviderFailure.providerMessage(in: data)
                    .map { AIProviderFailure.kept($0, secrets: secrets) } ?? AIProviderFailure.stopped)
        }
        var events: [AIStreamEvent] = []
        if let choice = chunk.choices?.first {
            if let content = choice.delta?.content, !content.isEmpty {
                events += thinkTags.feed(content)
            } else if let reasoning = choice.delta?.reasoningText {
                events += [.thinking, .reasoning(reasoning)]
            }
            for fragment in choice.delta?.toolCalls ?? [] { absorb(fragment) }
            if choice.finishReason == "tool_calls" { events.append(contentsOf: flushToolCalls()) }
        }
        if let reported = chunk.usage {
            usage.inputTokens = reported.promptTokens ?? usage.inputTokens
            usage.outputTokens = reported.completionTokens ?? usage.outputTokens
            usage.reasoningTokens =
                reported.completionTokensDetails?.reasoningTokens ?? usage.reasoningTokens
            usage.costUSD = reported.cost ?? usage.costUSD
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
        if let signature = fragment.extraContent?.google?.thoughtSignature {
            partial.thoughtSignature = signature
        }
        partialToolCalls[fragment.index ?? 0] = partial
    }

    private mutating func decodeAnthropic(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8),
            let event = try? JSONDecoder().decode(AnthropicEvent.self, from: data)
        else {
            isTerminal = true
            throw AIProviderError.malformedResponse
        }

        let index = event.index ?? 0
        switch event.type {
        case "content_block_start":
            switch event.contentBlock?.type {
            case "tool_use":
                partialToolCalls[index] = PartialToolCall(
                    id: event.contentBlock?.id ?? "", name: event.contentBlock?.name ?? "",
                    arguments: "")
                return []
            case "server_tool_use" where event.contentBlock?.name == "web_search":
                searchIndex = index
                searchInput = ""
                return [.searching(nil)]
            case "web_search_tool_result":
                searchIndex = nil
                return [.searched(searchQuery)]
            default:
                return []
            }
        case "content_block_delta":
            if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                citations.record(text)
                return [.text(text)]
            }
            if event.delta?.type == "input_json_delta" {
                let fragment = event.delta?.partialJSON ?? ""
                if index == searchIndex {
                    searchInput += fragment
                } else {
                    partialToolCalls[index]?.arguments += fragment
                }
                return []
            }
            if event.delta?.type == "citations_delta", let url = event.delta?.citation?.url {
                citedURLs[index, default: []].append(url)
                return []
            }
            guard event.delta?.type == "thinking_delta" else { return [] }
            guard let thinking = event.delta?.thinking, !thinking.isEmpty else { return [.thinking] }
            return [.thinking, .reasoning(thinking)]
        case "content_block_stop":
            let links = (citedURLs.removeValue(forKey: index) ?? []).compactMap {
                citations.link(to: $0)
            }
            return links.isEmpty ? [] : [.text(links.joined())]
        case "message_start":
            let reported = event.message?.usage
            usage.inputTokens = reported?.inputTokens ?? usage.inputTokens
            let cached = [reported?.cacheReadInputTokens, reported?.cacheCreationInputTokens]
                .compactMap { $0 }
            if !cached.isEmpty { usage.cachedInputTokens = cached.reduce(0, +) }
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
            throw AIProviderError.responseFailed(
                AIProviderFailure.described(
                    Self.anthropicErrorMessage(event.error?.type), said: event.error?.message,
                    secrets: secrets))
        default:
            return []
        }
    }

    private var searchQuery: String? {
        let input = try? JSONSerialization.jsonObject(with: Data(searchInput.utf8))
        return (input as? [String: Any])?["query"] as? String
    }

    private static func anthropicErrorMessage(_ type: String?) -> String {
        switch type {
        case "authentication_error": return String(localized: "API key rejected — check it in Settings.")
        case "rate_limit_error": return String(localized: "Rate limit reached — try again later.")
        default: return AIProviderFailure.stopped
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

                struct ExtraContent: Decodable {
                    struct Google: Decodable {
                        let thoughtSignature: String?

                        enum CodingKeys: String, CodingKey {
                            case thoughtSignature = "thought_signature"
                        }
                    }

                    let google: Google?
                }

                let index: Int?
                let id: String?
                let function: Function?
                let extraContent: ExtraContent?

                enum CodingKeys: String, CodingKey {
                    case index, id, function
                    case extraContent = "extra_content"
                }
            }

            let content: String?
            let reasoning: String?
            let reasoningContent: String?
            let reasoningDetails: [ReasoningDetail]?
            let toolCalls: [ToolCall]?

            /// OpenRouter says `reasoning`, DeepSeek and its copies `reasoning_content`.
            var reasoningText: String? {
                let text =
                    [reasoning, reasoningContent].compactMap { $0 }.first { !$0.isEmpty }
                    ?? reasoningDetails?.compactMap(\.text).joined()
                return text?.isEmpty == false ? text : nil
            }

            enum CodingKeys: String, CodingKey {
                case content, reasoning
                case reasoningContent = "reasoning_content"
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
        struct CompletionDetails: Decodable {
            let reasoningTokens: Int?

            enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        let promptTokens: Int?
        let completionTokens: Int?
        let completionTokensDetails: CompletionDetails?
        /// OpenRouter's own figure; a vendor API sends none.
        let cost: Double?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case completionTokensDetails = "completion_tokens_details"
            case cost
        }
    }

    struct ErrorBody: Decodable { let message: String? }

    let choices: [Choice]?
    let usage: Usage?
    let error: ErrorBody?
}

private struct AnthropicEvent: Decodable {
    struct Delta: Decodable {
        struct Citation: Decodable { let url: String? }

        let type: String?
        let text: String?
        let thinking: String?
        let partialJSON: String?
        let stopReason: String?
        let citation: Citation?

        enum CodingKeys: String, CodingKey {
            case type, text, thinking, citation
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
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }
    }

    struct Message: Decodable { let usage: Usage? }
    struct ErrorBody: Decodable {
        let type: String?
        let message: String?
    }

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
