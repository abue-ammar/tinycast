import Foundation

/// The JSON body each route expects. Pure on purpose: a wrong shape is a mid-conversation 400.
enum AIRequestBody {
    static func make(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        switch configuration.shape {
        case .openAICompatible: return openAI(input, configuration: configuration)
        case .anthropic: return anthropic(input, configuration: configuration)
        }
    }

    private static func openAI(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        var messages = input.messages.compactMap(openAIMessage)
        if let instructions = input.instructions?.nonEmpty {
            messages.insert(["role": "system", "content": instructions], at: 0)
        }
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "stream": true
        ]
        // OpenRouter's own search layer, so it works for every model it routes.
        if input.webSearch, configuration.provider == .openRouter {
            body["plugins"] = [["id": "web"]]
        }
        if !input.tools.isEmpty {
            body["tools"] = input.tools.map {
                [
                    "type": "function",
                    "function": [
                        "name": $0.name, "description": $0.description,
                        "parameters": $0.parameters.jsonObject
                    ]
                ]
            }
        }
        return body
    }

    private static func anthropic(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        let systemParts =
            ([input.instructions]
            + input.messages.compactMap { $0.role == .system ? $0.text : nil })
            .compactMap { $0?.nonEmpty }
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": anthropicMessages(input.messages),
            "max_tokens": input.maxOutputTokens,
            "stream": true
        ]
        if !systemParts.isEmpty { body["system"] = systemParts.joined(separator: "\n\n") }
        if !input.tools.isEmpty {
            body["tools"] = input.tools.map {
                [
                    "name": $0.name, "description": $0.description,
                    "input_schema": $0.parameters.jsonObject
                ]
            }
        }
        return body
    }

    /// Plain text stays a string; only a message with images takes the content-part array.
    private static func openAIMessage(_ message: AIMessage) -> [String: Any]? {
        if let result = message.toolResult {
            return [
                "role": "tool", "tool_call_id": result.callID, "content": result.content
            ]
        }
        let text = message.text.nonEmpty
        if !message.toolCalls.isEmpty {
            return [
                "role": message.role.rawValue,
                "content": text ?? "",
                "tool_calls": message.toolCalls.map {
                    [
                        "id": $0.id, "type": "function",
                        "function": ["name": $0.name, "arguments": $0.arguments]
                    ]
                }
            ]
        }
        guard text != nil || !message.images.isEmpty else { return nil }
        guard !message.images.isEmpty else {
            return ["role": message.role.rawValue, "content": text ?? ""]
        }
        var parts: [[String: Any]] = []
        if let text { parts.append(["type": "text", "text": text]) }
        parts += message.images.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] }
        return ["role": message.role.rawValue, "content": parts]
    }

    /// Anthropic takes tool results as user content, and a run of them has to arrive as one turn.
    private static func anthropicMessages(_ messages: [AIMessage]) -> [[String: Any]] {
        var encoded: [[String: Any]] = []
        var results: [[String: Any]] = []
        for message in messages {
            if let result = message.toolResult {
                results.append([
                    "type": "tool_result", "tool_use_id": result.callID,
                    "content": result.content, "is_error": result.isError
                ])
                continue
            }
            if !results.isEmpty {
                encoded.append(["role": "user", "content": results])
                results = []
            }
            if let value = anthropicMessage(message) { encoded.append(value) }
        }
        if !results.isEmpty { encoded.append(["role": "user", "content": results]) }
        return encoded
    }

    private static func anthropicMessage(_ message: AIMessage) -> [String: Any]? {
        guard message.role != .system else { return nil }
        let text = message.text.nonEmpty
        if !message.toolCalls.isEmpty {
            var parts: [[String: Any]] = text.map { [["type": "text", "text": $0]] } ?? []
            parts += message.toolCalls.map {
                [
                    "type": "tool_use", "id": $0.id, "name": $0.name,
                    "input": JSONValue(data: Data($0.arguments.utf8))?.jsonObject ?? [:]
                ]
            }
            return ["role": message.role.rawValue, "content": parts]
        }
        guard text != nil || !message.images.isEmpty else { return nil }
        guard !message.images.isEmpty else {
            return ["role": message.role.rawValue, "content": text ?? ""]
        }
        var parts: [[String: Any]] = message.images.map {
            [
                "type": "image",
                "source": [
                    "type": "base64", "media_type": $0.mimeType,
                    "data": $0.data.base64EncodedString()
                ]
            ]
        }
        if let text { parts.append(["type": "text", "text": text]) }
        return ["role": message.role.rawValue, "content": parts]
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
