import Foundation

private func logDebug(_ message: String) {
    let line = "[\(Date())] \(message)\n"
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/tinycast-ai.log")) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/tinycast-ai.log"))
        }
    }
}

struct HTTPAIProvider: AIProvider {
    let configuration: AIHTTPConfiguration
    let apiKey: String
    private let session: URLSession

    init(
        configuration: AIHTTPConfiguration, apiKey: String,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.session = session
    }

    func stream(_ input: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(for: input)
                    if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
                        logDebug("REQUEST URL: \(request.url?.absoluteString ?? "")")
                        logDebug("REQUEST HEADERS: \(request.allHTTPHeaderFields ?? [:])")
                        logDebug("REQUEST BODY: \(bodyString)")
                    }
                    let (asyncBytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        logDebug("RESPONSE NOT HTTP: \(response)")
                        throw AIProviderError.responseFailed("Invalid response from server.")
                    }
                    logDebug("RESPONSE STATUS: \(http.statusCode)")
                    logDebug("RESPONSE HEADERS: \(http.allHeaderFields)")
                    guard (200...299).contains(http.statusCode) else {
                        var body = ""
                        for try await line in asyncBytes.lines {
                            body += line + "\n"
                        }
                        logDebug("NON-200 BODY: \(body)")
                        throw AIStreamDecoder.parseError(
                            from: body, status: http.statusCode, shape: configuration.shape)
                    }
                    var decoder = AIStreamDecoder(shape: configuration.shape)
                    for try await line in asyncBytes.lines {
                        guard !Task.isCancelled else { break }
                        logDebug("STREAM LINE: \(line)")
                        for event in try decoder.feed(line: line) {
                            logDebug("STREAM EVENT: \(event)")
                            continuation.yield(event)
                        }
                    }
                    for event in try decoder.finish() {
                        logDebug("FINISH EVENT: \(event)")
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    logDebug("STREAM CAUGHT ERROR: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildRequest(for input: AIRequest) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: Any
        switch configuration.shape {
        case .openAICompatible:
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            if configuration.provider == .openRouter {
                request.setValue(Bundle.main.appDisplayName, forHTTPHeaderField: "X-OpenRouter-Title")
            }
            var messages = input.messages.compactMap(Self.openAIMessage)
            if let instructions = input.instructions?.nonEmpty {
                messages.insert(["role": "system", "content": instructions], at: 0)
            }
            var value: [String: Any] = [
                "model": configuration.model,
                "messages": messages,
                "stream": true
            ]
            if !input.tools.isEmpty {
                let toolSchemas: [[String: Any]] = input.tools.compactMap { tool in
                    guard let data = tool.parametersJSON.data(using: .utf8),
                          let schema = try? JSONSerialization.jsonObject(with: data) else { return nil }
                    return [
                        "type": "function",
                        "function": [
                            "name": tool.name,
                            "description": tool.description,
                            "parameters": schema
                        ]
                    ]
                }
                if !toolSchemas.isEmpty { value["tools"] = toolSchemas }
            }
            // OpenRouter's own search layer, so it works for every model it routes.
            if input.webSearch, configuration.provider == .openRouter {
                value["plugins"] = [["id": "web"]]
            }
            body = value
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let systemParts =
                ([input.instructions]
                + input.messages.compactMap {
                    $0.role == .system ? $0.text : nil
                }).compactMap { $0?.nonEmpty }
            var value: [String: Any] = [
                "model": configuration.model,
                "messages": input.messages.compactMap(Self.anthropicMessage),
                "max_tokens": input.maxOutputTokens,
                "stream": true
            ]
            if !input.tools.isEmpty {
                let toolSchemas: [[String: Any]] = input.tools.compactMap { tool in
                    guard let data = tool.parametersJSON.data(using: .utf8),
                          let schema = try? JSONSerialization.jsonObject(with: data) else { return nil }
                    return [
                        "name": tool.name,
                        "description": tool.description,
                        "input_schema": schema
                    ]
                }
                if !toolSchemas.isEmpty { value["tools"] = toolSchemas }
            }
            if !systemParts.isEmpty { value["system"] = systemParts.joined(separator: "\n\n") }
            body = value
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Plain text stays a string; tool responses take role "tool".
    private static func openAIMessage(_ message: AIMessage) -> [String: Any]? {
        if message.role == .tool {
            let callID = AIToolCall.sanitizeID(message.toolCallID ?? "")
            return [
                "role": "tool",
                "tool_call_id": callID,
                "content": message.text
            ]
        }
        if !message.toolCalls.isEmpty {
            var msg: [String: Any] = ["role": "assistant"]
            if let text = message.text.nonEmpty {
                msg["content"] = text
            } else {
                msg["content"] = NSNull()
            }
            msg["tool_calls"] = message.toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.argumentsJSON
                    ]
                ]
            }
            return msg
        }
        let text = message.text.nonEmpty
        guard text != nil || !message.images.isEmpty else { return nil }
        guard !message.images.isEmpty else {
            return ["role": message.role.rawValue, "content": text ?? ""]
        }
        var parts: [[String: Any]] = []
        if let text { parts.append(["type": "text", "text": text]) }
        for image in message.images {
            parts.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
                ]
            ])
        }
        return ["role": message.role.rawValue, "content": parts]
    }

    private static func anthropicMessage(_ message: AIMessage) -> [String: Any]? {
        if message.role == .system { return nil }
        if message.role == .tool {
            let callID = AIToolCall.sanitizeID(message.toolCallID ?? "")
            return [
                "role": "user",
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": callID,
                        "content": message.text
                    ]
                ]
            ]
        }
        if !message.toolCalls.isEmpty {
            var content: [[String: Any]] = []
            if let text = message.text.nonEmpty {
                content.append(["type": "text", "text": text])
            }
            for call in message.toolCalls {
                let inputObj: Any = {
                    guard let data = call.argumentsJSON.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) else { return [:] }
                    return json
                }()
                content.append([
                    "type": "tool_use",
                    "id": call.id,
                    "name": call.name,
                    "input": inputObj
                ])
            }
            return ["role": "assistant", "content": content]
        }
        let text = message.text.nonEmpty
        guard text != nil || !message.images.isEmpty else { return nil }
        guard !message.images.isEmpty else {
            return ["role": message.role.rawValue, "content": text ?? ""]
        }
        var parts: [[String: Any]] = []
        for image in message.images {
            parts.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mimeType,
                    "data": image.data.base64EncodedString()
                ]
            ])
        }
        if let text { parts.append(["type": "text", "text": text]) }
        return ["role": message.role.rawValue, "content": parts]
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
