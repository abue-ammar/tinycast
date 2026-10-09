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
///
/// A wire name is only ever looked up, never parsed back: a sanitised or trimmed name cannot say
/// which server or which original tool it came from, so `MCPToolRoutes` keeps that answer.
enum MCPToolName {
    static let separator = "__"
    /// OpenAI's ceiling, and the tighter of the two.
    static let maxLength = 64
    private static let hashLength = 8

    static func compose(slug: String, tool: String) -> String {
        let handle = String(sanitize(slug).prefix(MCPSlug.maxLength))
        let cleaned = sanitize(tool)
        let room = max(maxLength - separator.count - handle.count, hashLength + 2)
        // A name that survives untouched stays readable; one that had to change carries a hash
        // of the original, so `get.file` and `get_file`, or two long names, never collide.
        guard cleaned != tool || cleaned.count > room else { return handle + separator + cleaned }
        let kept = String(cleaned.prefix(room - hashLength - 1))
        return handle + separator + kept + "_" + fingerprint(tool)
    }

    /// The slug half of a wire name, for display and legacy callers; routing uses `MCPToolRoutes`.
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

    /// FNV-1a, so the same tool gets the same wire name on every launch and every Mac.
    private static func fingerprint(_ value: String) -> String {
        var hash: UInt32 = 0x811C_9DC5
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: hashLength - hex.count) + hex
    }
}

/// Wire name → the server and the tool's own name, built from what the servers listed.
struct MCPToolRoutes: Sendable {
    private var routes: [String: MCPTool] = [:]

    init(_ tools: [MCPTool]) {
        // First listed wins: a duplicate wire name would be a hash collision, not a second tool.
        for tool in tools where routes[tool.wireName] == nil { routes[tool.wireName] = tool }
    }

    func tool(named wireName: String) -> MCPTool? { routes[wireName] }
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
