import Foundation

/// One tool a server advertises, still carrying which server it came from.
struct MCPTool: Equatable, Sendable {
    let serverID: UUID
    let serverSlug: String
    let serverTitle: String
    let name: String
    let description: String
    let inputSchema: JSONValue

    /// The name the model sees. A wire name has to survive both providers' character rules.
    var wireName: String { MCPToolName.compose(slug: serverSlug, tool: name) }

    var aiTool: AITool {
        AITool(
            name: wireName, description: description, parameters: inputSchema,
            origin: serverTitle, title: name)
    }

    /// Everything a server listed, dropping entries too malformed to call.
    static func list(
        _ result: JSONValue, serverID: UUID, serverSlug: String, serverTitle: String
    ) -> [MCPTool] {
        (result.objectValue?["tools"]?.arrayValue ?? []).compactMap { entry in
            guard let tool = entry.objectValue, let name = tool["name"]?.stringValue,
                !name.isEmpty
            else { return nil }
            return MCPTool(
                serverID: serverID, serverSlug: serverSlug, serverTitle: serverTitle, name: name,
                description: tool["description"]?.stringValue ?? "",
                inputSchema: tool["inputSchema"] ?? .object(["type": .string("object")]))
        }
    }
}

/// The one place a server's slug and a tool's own name become a single provider-safe identifier.
enum MCPToolName {
    static let separator = "__"
    /// OpenAI's ceiling, and the tighter of the two.
    static let maxLength = 64

    static func compose(slug: String, tool: String) -> String {
        let tail = sanitize(tool)
        let room = maxLength - separator.count - sanitize(slug).count
        // The slug is what routes the call, so the tool's own name is the half that gives way.
        return sanitize(slug) + separator + String(tail.suffix(max(room, 1)))
    }

    /// Back to the slug that routes it; a name without the separator was never one of ours.
    static func parse(_ wireName: String) -> (slug: String, tool: String)? {
        guard let range = wireName.range(of: separator) else { return nil }
        let slug = String(wireName[..<range.lowerBound])
        guard !slug.isEmpty else { return nil }
        return (slug, String(wireName[range.upperBound...]))
    }

    private static func sanitize(_ value: String) -> String {
        let cleaned = value.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
                ? character : "_"
        }
        return String(cleaned)
    }
}

/// What a `tools/call` answered, flattened to the text a model can read.
enum MCPToolOutput {
    static func flatten(_ result: JSONValue) -> (content: String, isError: Bool) {
        let object = result.objectValue ?? [:]
        let isError = object["isError"]?.boolValue ?? false
        let blocks = (object["content"]?.arrayValue ?? []).compactMap(describe)
        guard blocks.isEmpty else {
            return (blocks.joined(separator: "\n"), isError)
        }
        // A server may answer with structured content alone; the model reads it as JSON.
        guard let structured = object["structuredContent"],
            let data = try? JSONSerialization.data(withJSONObject: structured.jsonObject),
            let text = String(bytes: data, encoding: .utf8)
        else {
            return ("The tool returned no content.", isError)
        }
        return (text, isError)
    }

    /// Only what a text model can act on; a picture or a blob is named rather than inlined.
    private static func describe(_ block: JSONValue) -> String? {
        guard let block = block.objectValue else { return nil }
        switch block["type"]?.stringValue {
        case "text":
            return block["text"]?.stringValue
        case "resource":
            let resource = block["resource"]?.objectValue ?? [:]
            return resource["text"]?.stringValue
                ?? resource["uri"]?.stringValue.map { "[resource \($0)]" }
        case "resource_link":
            return block["uri"]?.stringValue.map { "[resource \($0)]" }
        case "image", "audio":
            return "[\(block["type"]?.stringValue ?? "binary") content omitted]"
        default:
            return nil
        }
    }
}
