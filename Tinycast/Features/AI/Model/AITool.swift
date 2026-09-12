import Foundation

/// A tool offered to the model. `parameters` is the provider's schema, carried through untouched.
struct AITool: Equatable, Sendable {
    let name: String
    let description: String
    let parameters: JSONValue
    /// What the transcript row says the tool belongs to, and what it calls the tool.
    let origin: String
    let title: String

    init(
        name: String, description: String, parameters: JSONValue, origin: String,
        title: String? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.origin = origin
        self.title = title ?? name
    }
}

/// One call the model asked for; `arguments` stays the raw JSON text only the executor parses.
struct AIToolCall: Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let arguments: String
}

/// A failure is content the model can read and recover from, never a thrown error.
struct AIToolResult: Equatable, Sendable {
    let callID: String
    let content: String
    let isError: Bool

    static func failure(_ callID: String, _ message: String) -> AIToolResult {
        AIToolResult(callID: callID, content: message, isError: true)
    }
}
