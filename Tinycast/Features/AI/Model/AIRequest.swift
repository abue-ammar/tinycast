import Foundation

/// An attached picture, already encoded for the wire; every provider takes it as a data URL.
struct AIImage: Equatable, Hashable, Sendable {
    let data: Data
    let mimeType: String

    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

/// Requests cap near 25 MB and a data URL costs a third more, so the ceiling lives here.
enum AIAttachmentBudget {
    static let maxCount = 6
    static let maxBytes = 10 * 1_048_576

    /// Whether `images` can take `candidate` and stay inside both limits.
    static func admits(_ images: [AIImage], adding candidate: AIImage) -> Bool {
        images.count < maxCount
            && images.reduce(candidate.data.count) { $0 + $1.data.count } <= maxBytes
    }

    /// The longest leading run that fits, for a turn assembled by any route but the composer.
    static func bounded(_ images: [AIImage]) -> [AIImage] {
        var total = 0
        return Array(
            images.prefix(maxCount).prefix { image in
                total += image.data.count
                return total <= maxBytes
            })
    }
}

struct AIMessage: Equatable, Sendable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    let role: Role
    let text: String
    let images: [AIImage]
    let toolCalls: [AIToolCall]
    let toolCallID: String?

    init(
        role: Role,
        text: String,
        images: [AIImage] = [],
        toolCalls: [AIToolCall] = [],
        toolCallID: String? = nil
    ) {
        self.role = role
        self.text = text
        self.images = images
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID.map { AIToolCall.sanitizeID($0) }
    }
}

struct AIRequest: Equatable, Sendable {
    let messages: [AIMessage]
    let instructions: String?
    let maxOutputTokens: Int
    let webSearch: Bool
    let tools: [AIToolDefinition]

    init(
        messages: [AIMessage],
        instructions: String? = nil,
        maxOutputTokens: Int = 4096,
        webSearch: Bool = false,
        tools: [AIToolDefinition] = []
    ) {
        self.messages = messages
        self.instructions = instructions
        self.maxOutputTokens = maxOutputTokens
        self.webSearch = webSearch
        self.tools = tools
    }

    init(
        instructions: String?,
        messages: [AIMessage],
        maxOutputTokens: Int = 4096,
        webSearch: Bool = false,
        tools: [AIToolDefinition] = []
    ) {
        self.messages = messages
        self.instructions = instructions
        self.maxOutputTokens = maxOutputTokens
        self.webSearch = webSearch
        self.tools = tools
    }
}

struct AIUsage: Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?

    var isEmpty: Bool {
        inputTokens == nil && outputTokens == nil
    }

    var totalTokens: Int? {
        guard let inputTokens, let outputTokens else { return nil }
        return inputTokens + outputTokens
    }
}

enum AIStreamEvent: Equatable, Sendable {
    case text(String)
    case thinking
    case searching(String?)
    case searched(String?)
    case toolCall(AIToolCall)
    case toolExecuting(name: String, detail: String?)
    case usage(AIUsage)
    case finished
}

enum AIProviderError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case responseFailed(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .responseFailed(let message): return message
        case .malformedResponse: return "The AI provider returned an unreadable response."
        }
    }
}

public struct AIToolParameter: Equatable, Sendable {
    public let name: String
    public let type: String
    public let description: String
    public let isRequired: Bool
    public let enumValues: [String]?

    public init(
        name: String,
        type: String = "string",
        description: String,
        isRequired: Bool = true,
        enumValues: [String]? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.isRequired = isRequired
        self.enumValues = enumValues
    }
}

public struct AIToolDefinition: Equatable, Sendable {
    public let name: String
    public let description: String
    public let parameters: [AIToolParameter]

    public var parametersJSON: String {
        var properties: [String: Any] = [:]
        var requiredList: [String] = []

        for p in parameters {
            var prop: [String: Any] = [
                "type": p.type,
                "description": p.description
            ]
            if let enums = p.enumValues, !enums.isEmpty {
                prop["enum"] = enums
            }
            properties[p.name] = prop
            if p.isRequired {
                requiredList.append(p.name)
            }
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": requiredList
        ]

        if let data = try? JSONSerialization.data(withJSONObject: schema, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"type\":\"object\",\"properties\":{}}"
    }

    public init(
        name: String,
        description: String,
        parameters: [AIToolParameter] = []
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct AIToolCall: Equatable, Sendable {
    public let id: String
    public let name: String
    public let arguments: String

    public var argumentsJSON: String { arguments }

    public init(id: String, name: String, arguments: String) {
        self.id = Self.sanitizeID(id)
        self.name = name
        self.arguments = arguments
    }

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = Self.sanitizeID(id)
        self.name = name
        self.arguments = argumentsJSON
    }

    public static func sanitizeID(_ rawID: String) -> String {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "call_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        var result = ""
        for scalar in trimmed.unicodeScalars {
            if allowed.contains(scalar) {
                result.append(Character(scalar))
            } else {
                result.append("_")
            }
        }
        return result.isEmpty ? ("call_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")) : result
    }
}

extension AIToolDefinition {
    public static let webSearch = AIToolDefinition(
        name: "web_search",
        description: "Search the web for real-time information, news, current events, and facts.",
        parameters: [
            AIToolParameter(name: "query", type: "string", description: "The search query to execute.", isRequired: true),
            AIToolParameter(name: "category", type: "string", description: "Optional category filter (e.g. general, news, weather).", isRequired: false)
        ]
    )

    public static let webFetch = AIToolDefinition(
        name: "web_fetch",
        description: "Fetch and read the text content of a specific webpage or PDF document by URL.",
        parameters: [
            AIToolParameter(name: "url", type: "string", description: "The full URL to fetch content from.", isRequired: true),
            AIToolParameter(name: "max_characters", type: "integer", description: "Maximum number of characters to extract (default 4000).", isRequired: false)
        ]
    )

    public static let calculate = AIToolDefinition(
        name: "calculate",
        description: "Evaluate a mathematical expression, unit conversion, currency exchange, or date calculation accurately.",
        parameters: [
            AIToolParameter(name: "expression", type: "string", description: "The mathematical formula or conversion string (e.g. 128 * 4.5).", isRequired: true)
        ]
    )

    public static let getLocation = AIToolDefinition(
        name: "get_location",
        description: "Get the user current physical location (city, region, country, coordinates).",
        parameters: []
    )

    public static let getWeather = AIToolDefinition(
        name: "get_weather",
        description: "Get current weather conditions and forecasts for a specific location or current location.",
        parameters: [
            AIToolParameter(name: "location", type: "string", description: "City or region name. If omitted, uses current location.", isRequired: false),
            AIToolParameter(name: "days", type: "integer", description: "Forecast days (1 to 7, default 1).", isRequired: false)
        ]
    )
}

public struct AIToolResult: Equatable, Sendable {
    public let callID: String
    public let toolName: String
    public let output: String
    public let isError: Bool

    public init(callID: String, toolName: String, output: String, isError: Bool = false) {
        self.callID = AIToolCall.sanitizeID(callID)
        self.toolName = toolName
        self.output = output
        self.isError = isError
    }

    public init(callID: String, name: String, output: String, isError: Bool = false) {
        self.callID = AIToolCall.sanitizeID(callID)
        self.toolName = name
        self.output = output
        self.isError = isError
    }
}
