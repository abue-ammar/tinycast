import Foundation

struct InstalledAIStreamFrame: Equatable, Sendable {
    var events: [AIStreamEvent] = []
    var sessionID: String?
    var error: String?
    var completed = false
}

enum InstalledAIStreamDecoder {
    static func decode(_ data: Data, kind: InstalledAIKind) -> InstalledAIStreamFrame {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else { return InstalledAIStreamFrame() }
        switch kind {
        case .openCode: return openCode(object, type: type)
        case .claude: return claude(object, type: type)
        case .codex: return InstalledAIStreamFrame()
        }
    }

    private static func openCode(
        _ object: [String: Any], type: String
    ) -> InstalledAIStreamFrame {
        var frame = InstalledAIStreamFrame(sessionID: object["sessionID"] as? String)
        let part = object["part"] as? [String: Any]
        switch type {
        case "text":
            if let text = part?["text"] as? String, !text.isEmpty { frame.events = [.text(text)] }
        case "step_start":
            frame.events = [.thinking]
        case "step_finish":
            if let tokens = part?["tokens"] as? [String: Any] {
                frame.events.append(
                    .usage(
                        AIUsage(
                            inputTokens: integer(tokens["input"]),
                            outputTokens: integer(tokens["output"]))))
            }
            frame.completed = true
        case "error":
            frame.error = message(in: object) ?? "OpenCode could not finish the response."
        default:
            break
        }
        return frame
    }

    private static func claude(
        _ object: [String: Any], type: String
    ) -> InstalledAIStreamFrame {
        var frame = InstalledAIStreamFrame()
        if type == "stream_event", let event = object["event"] as? [String: Any],
            let delta = event["delta"] as? [String: Any]
        {
            switch delta["type"] as? String {
            case "text_delta":
                if let text = delta["text"] as? String, !text.isEmpty {
                    frame.events = [.text(text)]
                }
            case "thinking_delta":
                frame.events = [.thinking]
            default:
                break
            }
            return frame
        }
        guard type == "result" else { return frame }
        if object["is_error"] as? Bool == true {
            frame.error = object["result"] as? String ?? "Claude could not finish the response."
            return frame
        }
        if let usage = object["usage"] as? [String: Any] {
            frame.events.append(
                .usage(
                    AIUsage(
                        inputTokens: integer(usage["input_tokens"]),
                        outputTokens: integer(usage["output_tokens"]))))
        }
        frame.completed = true
        return frame
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func message(in object: [String: Any]) -> String? {
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String
        }
        return nil
    }
}
