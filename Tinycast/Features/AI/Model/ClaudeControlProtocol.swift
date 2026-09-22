import Foundation

/// Claude's consent channel: the Agent SDK's undocumented wire format, kept to this one type.
enum ClaudeControlProtocol {
    /// One call the CLI is holding open until Tinycast answers.
    struct Request: Equatable, Sendable {
        let id: String
        let call: AIToolServerCall
        /// Passed straight back on allow: the CLI takes the arguments it sent, never rewritten.
        let input: JSONValue
    }

    /// `nil` for every frame that is not a tool question on one of Tinycast's servers.
    static func request(_ object: [String: Any]) -> Request? {
        guard object["type"] as? String == "control_request",
            let id = object["request_id"] as? String,
            let request = object["request"] as? [String: Any],
            request["subtype"] as? String == "can_use_tool",
            let name = request["tool_name"] as? String,
            let call = ClaudeMCPLaunch.route(name)
        else { return nil }
        return Request(
            id: id, call: call, input: JSONValue(request["input"] ?? [String: Any]()))
    }

    /// The answer; never `updatedPermissions`, which would have the CLI write its own settings.
    static func response(to request: Request, allowed: Bool, message: String) -> Data? {
        let answer: [String: Any] =
            allowed
            ? ["behavior": "allow", "updatedInput": request.input.jsonObject]
            : ["behavior": "deny", "message": message]
        var line = try? JSONSerialization.data(
            withJSONObject: [
                "type": "control_response",
                "response": [
                    "subtype": "success", "request_id": request.id, "response": answer
                ]
            ])
        line?.append(0x0A)
        return line
    }

    /// A control request that is no tool question of ours; unanswered, the CLI waits for good.
    static func unsupportedRequestID(_ object: [String: Any]) -> String? {
        guard object["type"] as? String == "control_request", request(object) == nil else {
            return nil
        }
        return object["request_id"] as? String
    }

    static func error(to id: String, message: String) -> Data? {
        var line = try? JSONSerialization.data(
            withJSONObject: [
                "type": "control_response",
                "response": ["subtype": "error", "request_id": id, "error": message]
            ])
        line?.append(0x0A)
        return line
    }

    /// The single user message a `stream-json` turn is made of, framed for stdin.
    static func userMessage(_ text: String) -> Data? {
        var line = try? JSONSerialization.data(
            withJSONObject: ["type": "user", "message": ["role": "user", "content": text]])
        line?.append(0x0A)
        return line
    }
}
