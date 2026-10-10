import Foundation

/// A refused turn's text for the transcript: the status's line, then what the provider itself said.
enum AIProviderFailure {
    /// Past this the body is someone else's log, not an answer worth reading for one sentence.
    static let bodyLimit = 8_000
    /// A provider's message is a sentence or two; a longer one is cut rather than filling the chat.
    static let messageLimit = 600
    /// A key under this is redacted only as a whole word: inside a longer one it is letters.
    static let shortSecret = 8

    private static let messageKeys = ["message", "detail", "msg", "error_message"]
    private static let redaction = "[redacted]"

    static func description(
        status: Int, body: Data, retryAfter: String?, secrets: [String]
    ) -> String {
        described(
            statusLine(status, retryAfter: retryAfter), said: providerMessage(in: body), secrets: secrets)
    }

    /// The provider's words go under the line, never in its place: the line is Tinycast's own.
    static func described(_ line: String, said: String?, secrets: [String]) -> String {
        guard let said = said.flatMap(sentence) else { return line }
        return "\(line)\n\n\(kept(said, secrets: secrets))"
    }

    /// A provider's words made fit to keep: keys out first, so the cut cannot leave half of one.
    static func kept(_ said: String, secrets: [String]) -> String {
        let safe = redacted(said, secrets: secrets)
        return safe.count > messageLimit ? "\(safe.prefix(messageLimit))…" : safe
    }

    static func statusLine(_ status: Int, retryAfter: String?) -> String {
        switch status {
        case 401, 403:
            return "API key rejected — check it in Settings."
        case 429:
            guard let retryAfter, let seconds = Int(retryAfter), seconds >= 0 else {
                return "Rate limit reached — try again later."
            }
            return "Rate limit reached — retry after \(seconds) seconds."
        case 500...599:
            return "The provider is temporarily unavailable (HTTP \(status))."
        default:
            return "The provider rejected the model or request (HTTP \(status))."
        }
    }

    // MARK: - Reading the body

    /// Every shape seen in the wild: OpenAI's and its copies', Anthropic's, Gemini's array, vLLM's.
    static func providerMessage(in body: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: body, options: .fragmentsAllowed) {
            return message(in: json, depth: 0)
        }
        return text(body.prefix(bodyLimit)).flatMap(sentence)
    }

    private static func message(in json: Any, depth: Int) -> String? {
        // OpenRouter's nested upstream body is five levels down; past eight is no error body.
        guard depth < 8 else { return nil }
        if let list = json as? [Any] {
            return list.lazy.compactMap { message(in: $0, depth: depth + 1) }.first
        }
        if let text = json as? String {
            // OpenRouter nests the upstream provider's own body as a JSON string in `raw`.
            if let data = text.data(using: .utf8), let inner = try? JSONSerialization.jsonObject(with: data) {
                return message(in: inner, depth: depth + 1)
            }
            return sentence(text)
        }
        guard let object = json as? [String: Any] else { return nil }
        if let error = object["error"] {
            if let nested = error as? [String: Any],
                let raw = (nested["metadata"] as? [String: Any])?["raw"],
                let upstream = message(in: raw, depth: depth + 1)
            {
                return upstream
            }
            if let found = message(in: error, depth: depth + 1) { return found }
        }
        for key in messageKeys {
            if let value = object[key], let found = message(in: value, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    /// Neither a gateway's HTML page nor JSON that never parsed is a sentence, wherever it sits.
    private static func sentence(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<") else { return nil }
        return isUnparsedJSON(trimmed) ? salvaged(from: trimmed) : trimmed
    }

    /// Its bracket never closes, or closes at the very end around a quote; "[Errno 1] x" is prose.
    private static func isUnparsedJSON(_ text: String) -> Bool {
        guard text.hasPrefix("{") || text.hasPrefix("[") else { return false }
        let last = text.count - 1
        var depth = 0
        var quoted = false
        var escaped = false
        for (offset, character) in text.enumerated() {
            if escaped {
                escaped = false
            } else if character == "\"" {
                quoted.toggle()
            } else if quoted {
                escaped = character == "\\"
            } else if character == "{" || character == "[" {
                depth += 1
            } else if character == "}" || character == "]" {
                depth -= 1
                if depth == 0 { return offset == last && text.contains("\"") }
            }
        }
        return true
    }

    /// A body the cap cut is no longer JSON, but a message near its start may still be whole.
    private static func salvaged(from text: String) -> String? {
        // `error` last: as a bare string it is rarer than one echoed back inside the request.
        for keys in [messageKeys, ["error"]] {
            let names = keys.joined(separator: "|")
            guard let pattern = try? Regex(#""(?:\#(names))"\s*:\s*("(?:[^"\\]|\\.)*")"#) else { continue }
            for match in text.matches(of: pattern) {
                if let literal = match.output[1].substring, let data = String(literal).data(using: .utf8),
                    let said = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String,
                    let found = sentence(said)
                {
                    return found
                }
            }
        }
        return nil
    }

    /// The cap can fall inside a character, so up to three trailing bytes give way before it fails.
    private static func text(_ bytes: Data) -> String? {
        for cut in 0...min(3, bytes.count) {
            if let text = String(bytes: bytes.dropLast(cut), encoding: .utf8) { return text }
        }
        return nil
    }

    // MARK: - Keeping keys out of the transcript

    /// A provider sometimes echoes the request; the key itself, and any key-shaped token, go.
    static func redacted(_ text: String, secrets: [String]) -> String {
        var result = text
        for secret in secrets where !secret.isEmpty {
            let literal = NSRegularExpression.escapedPattern(for: secret)
            // A short key goes only as a whole word; inside a longer one it is just characters.
            let pattern = secret.count < shortSecret ? #"(?<![A-Za-z0-9])\#(literal)(?![A-Za-z0-9])"# : literal
            result = result.replacingOccurrences(of: pattern, with: redaction, options: .regularExpression)
        }
        for pattern in [#"Bearer\s+[A-Za-z0-9._~+/=-]{8,}"#, #"\b(sk|fw|gsk|xai|pk)[-_][A-Za-z0-9_-]{12,}"#,
                        #"AIza[0-9A-Za-z_-]{20,}"#]
        {
            result = result.replacingOccurrences(of: pattern, with: redaction, options: .regularExpression)
        }
        return result
    }
}
