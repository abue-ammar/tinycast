import Foundation

/// Claude's consent channel, and the only place Tinycast speaks it.
///
/// `--permission-prompt-tool stdio` puts a `control_request` on stdout and takes a
/// `control_response` on stdin. That is the Agent SDK's wire format: it is not documented for a
/// host that is not the SDK, and a CLI release may change it. Everything about it lives here so
/// the fallback — `--allowedTools "mcp__<handle>"`, with anything not pre-allowed denied — is one
/// type's worth of change rather than a rewrite of the runner.
enum ClaudeControlProtocol {
    /// One call the CLI is holding open until Tinycast answers.
    struct Request: Equatable, Sendable {
        let id: String
        let call: AIToolServerCall
        /// Passed straight back on allow: the CLI takes the arguments it sent, never rewritten.
        let input: JSONValue
    }

    /// `nil` for every frame that is not a tool question, including subtypes Tinycast does not know.
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

    /// The answer. `updatedPermissions` is never sent: it would have the CLI write its own
    /// settings, and only Tinycast's Settings may change a standing decision.
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
