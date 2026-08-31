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
        self.toolCallID = toolCallID
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
        webSearch: Bool = false,
        tools: [AIToolDefinition] = []
    ) {
        self.messages = messages
        self.instructions = instructions
        self.maxOutputTokens = 4096
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
