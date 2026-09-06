import Foundation

/// An attached picture, already encoded for the wire; every provider takes it as a data URL.
struct AIImage: Equatable, Hashable, Sendable {
    let data: Data
    let mimeType: String

    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

/// A file a route reads natively; a text-ish file never becomes one, it inlines as text instead.
struct AIDocument: Equatable, Hashable, Sendable {
    let data: Data
    let mimeType: String
    /// On the wire, unlike an image's: a model shown three PDFs needs to tell them apart.
    let name: String

    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

/// Requests cap near 25 MB and a data URL costs a third more, so the ceiling lives here.
enum AIAttachmentBudget {
    static let maxCount = 6
    static let maxBytes = 10 * 1_048_576
    /// Inlined text rides the newest turn, which is never trimmed, so it is capped before staging.
    static let maxInlinedTextBytes = 32 * 1_024

    /// Counted jointly: two independent ceilings would let six of each through.
    static func admits(images: [AIImage], documents: [AIDocument], addingBytes bytes: Int) -> Bool {
        let used =
            images.reduce(0) { $0 + $1.data.count }
            + documents.reduce(0) { $0 + $1.data.count }
        return images.count + documents.count < maxCount && used + bytes <= maxBytes
    }

    /// The longest leading run that fits, for a turn assembled by any route but the composer.
    /// Images fill first, so a picture is never dropped in favour of a document behind it.
    static func bounded(
        _ images: [AIImage], _ documents: [AIDocument]
    )
        -> (images: [AIImage], documents: [AIDocument])
    {
        var total = 0
        var count = 0
        let keptImages = images.prefix { image in
            guard count < maxCount, total + image.data.count <= maxBytes else { return false }
            total += image.data.count
            count += 1
            return true
        }
        let keptDocuments = documents.prefix { document in
            guard count < maxCount, total + document.data.count <= maxBytes else { return false }
            total += document.data.count
            count += 1
            return true
        }
        return (Array(keptImages), Array(keptDocuments))
    }
}

struct AIMessage: Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    let role: Role
    let text: String
    let images: [AIImage]
    /// Only a PDF ever lands here: a text-ish file is inlined into `text` before any transport.
    let documents: [AIDocument]
    /// Assistant only: the calls this turn asked for, alongside whatever text came with them.
    let toolCalls: [AIToolCall]
    /// Tool only: the answer to one of them.
    let toolResult: AIToolResult?

    init(
        role: Role, text: String, images: [AIImage] = [], documents: [AIDocument] = [],
        toolCalls: [AIToolCall] = [], toolResult: AIToolResult? = nil
    ) {
        self.role = role
        self.text = text
        self.images = images
        self.documents = documents
        self.toolCalls = toolCalls
        self.toolResult = toolResult
    }
}

struct AIRequest: Equatable, Sendable {
    let instructions: String?
    let messages: [AIMessage]
    let maxOutputTokens: Int
    /// Lets the model search the web; each route has its own switch for that, all off by default.
    let webSearch: Bool
    /// Empty for every route that cannot call one, so a transport need not ask whether it may.
    let tools: [AITool]

    init(
        instructions: String? = nil, messages: [AIMessage], maxOutputTokens: Int = 4_096,
        webSearch: Bool = false, tools: [AITool] = []
    ) {
        self.instructions = instructions
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
        self.webSearch = webSearch
        self.tools = tools
    }

    /// The same turn carried forward, armed with what the loop wrapping it may call.
    func continuing(with messages: [AIMessage], tools: [AITool]) -> AIRequest {
        AIRequest(
            instructions: instructions, messages: messages, maxOutputTokens: maxOutputTokens,
            webSearch: webSearch, tools: tools)
    }
}

struct AIUsage: Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?

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
    /// What a transport emits; the loop consumes it and never passes it on to the transcript.
    case toolCallRequested(AIToolCall)
    /// What the loop emits in its place, already carrying what a row has to show.
    case toolCall(id: String, origin: String, title: String)
    case toolResult(id: String, isError: Bool)
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
        case .malformedResponse: return "The provider returned malformed streaming data."
        }
    }
}
