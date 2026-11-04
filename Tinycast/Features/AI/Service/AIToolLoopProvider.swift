import Foundation

/// A route that can call tools: it re-streams the turn until the model stops or a cap ends it.
struct AIToolLoopProvider: AIProvider {
    private let base: any AIProvider
    private let tools: [AITool]
    private let invoke: @Sendable (AIToolCall) async -> AIToolResult

    /// A model that keeps calling has stopped answering; this many rounds is where the turn fails.
    private let maxRounds: Int?
    static let maxResultBytes = 32_768
    /// Results bypass `boundedContext`, so the turn carries its own ceiling for what they add.
    static let maxTurnResultBytes = 131_072
    /// Each round replays prior output, including opaque reasoning, so its growth must be bounded.
    static let maxTurnHistoryBytes = 1_048_576

    init(
        base: any AIProvider, tools: [AITool], maxRounds: Int?,
        invoke: @escaping @Sendable (AIToolCall) async -> AIToolResult
    ) {
        self.base = base
        self.tools = tools
        self.maxRounds = maxRounds
        self.invoke = invoke
    }

    func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            let task = Task.detached {
                do {
                    try await run(request, into: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ request: AIRequest, into continuation: AIProviderStream.Continuation
    ) async throws {
        var messages = request.messages
        var spent = 0
        var carried = 0
        var rounds = 0
        while carried < Self.maxTurnHistoryBytes, maxRounds.map({ rounds < $0 }) ?? true {
            rounds += 1
            let round = try await streamRound(
                request.continuing(with: messages, tools: tools), into: continuation)
            try Task.checkCancellation()
            guard !round.calls.isEmpty else {
                continuation.yield(.finished)
                return
            }
            messages.append(
                AIMessage(
                    role: .assistant, text: round.text, toolCalls: round.calls,
                    responseItems: round.responseItems))
            if round.responseItems.isEmpty {
                carried += round.text.utf8.count + round.calls.reduce(0) { $0 + $1.arguments.utf8.count }
            } else {
                carried += try JSONSerialization.data(
                    withJSONObject: round.responseItems.map(\.jsonObject)
                ).count
            }
            for call in round.calls {
                try Task.checkCancellation()
                let tool = tools.first { $0.name == call.name }
                continuation.yield(
                    .toolCall(
                        id: call.id, origin: tool?.origin ?? "", title: tool?.title ?? call.name))
                let result = await Self.bounded(invoke(call), spent: &spent)
                try Task.checkCancellation()
                continuation.yield(.toolResult(id: call.id, isError: result.isError))
                carried += result.content.utf8.count
                messages.append(AIMessage(role: .tool, text: "", toolResult: result))
            }
        }
        let message =
            carried >= Self.maxTurnHistoryBytes
            ? String(localized: "Stopped because this turn's tool history is too large.")
            : String(localized: "Stopped after \(rounds) rounds of tool calls.")
        throw AIProviderError.responseFailed(message)
    }

    /// One pass over the base route: text flows straight to the transcript, calls are collected.
    private func streamRound(
        _ request: AIRequest, into continuation: AIProviderStream.Continuation
    ) async throws -> (text: String, calls: [AIToolCall], responseItems: [JSONValue]) {
        var text = ""
        var calls: [AIToolCall] = []
        var responseItems: [JSONValue] = []
        for try await event in base.stream(request) {
            try Task.checkCancellation()
            switch event {
            case .text(let delta):
                text += delta
                continuation.yield(event)
            case .toolCallRequested(let call):
                calls.append(call)
            case .responseOutput(let items):
                responseItems = items
            // `.finished` is the loop's to send, once the model has stopped asking for tools.
            case .finished:
                break
            default:
                continuation.yield(event)
            }
        }
        return (text, calls, responseItems)
    }

    static func bounded(_ result: AIToolResult, spent: inout Int) -> AIToolResult {
        guard spent < Self.maxTurnResultBytes else {
            return .failure(result.callID, "This turn's tool output budget is used up.")
        }
        let allowance = min(Self.maxResultBytes, Self.maxTurnResultBytes - spent)
        let utf8 = result.content.utf8
        spent += min(utf8.count, allowance)
        guard utf8.count > allowance else { return result }
        // A cut can land mid-scalar; `String(decoding:)` turns the remainder into a replacement.
        let content = String(decoding: Array(utf8.prefix(allowance)), as: UTF8.self)
        return AIToolResult(
            callID: result.callID, content: content + "\n…truncated.", isError: result.isError)
    }
}
