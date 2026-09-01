import Foundation

/// A route that can call tools: it re-streams the turn until the model stops asking, under a cap.
struct AIToolLoopProvider: AIProvider {
    private let base: any AIProvider
    private let tools: [AITool]
    private let invoke: @Sendable (AIToolCall) async -> AIToolResult

    /// A model that keeps calling has stopped answering; ten rounds is where the turn fails.
    static let maxRounds = 10
    static let maxResultBytes = 32_768
    /// Results bypass `boundedContext`, so the turn carries its own ceiling for what they add.
    static let maxTurnResultBytes = 131_072

    init(
        base: any AIProvider, tools: [AITool],
        invoke: @escaping @Sendable (AIToolCall) async -> AIToolResult
    ) {
        self.base = base
        self.tools = tools
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
        for _ in 0..<Self.maxRounds {
            let round = try await streamRound(
                request.continuing(with: messages, tools: tools), into: continuation)
            guard !round.calls.isEmpty else {
                continuation.yield(.finished)
                return
            }
            messages.append(
                AIMessage(role: .assistant, text: round.text, toolCalls: round.calls))
            for call in round.calls {
                try Task.checkCancellation()
                let tool = tools.first { $0.name == call.name }
                continuation.yield(
                    .toolCall(
                        id: call.id, origin: tool?.origin ?? "", title: tool?.title ?? call.name))
                let result = await bounded(invoke(call), spent: &spent)
                continuation.yield(.toolResult(id: call.id, isError: result.isError))
                messages.append(AIMessage(role: .tool, text: "", toolResult: result))
            }
        }
        throw AIProviderError.responseFailed(
            "Stopped after \(Self.maxRounds) rounds of tool calls.")
    }

    /// One pass over the base route: text flows straight to the transcript, calls are collected.
    private func streamRound(
        _ request: AIRequest, into continuation: AIProviderStream.Continuation
    ) async throws -> (text: String, calls: [AIToolCall]) {
        var text = ""
        var calls: [AIToolCall] = []
        for try await event in base.stream(request) {
            try Task.checkCancellation()
            switch event {
            case .text(let delta):
                text += delta
                continuation.yield(event)
            case .toolCallRequested(let call):
                calls.append(call)
            // `.finished` is the loop's to send, once the model has stopped asking for tools.
            case .finished:
                break
            default:
                continuation.yield(event)
            }
        }
        return (text, calls)
    }

    private func bounded(_ result: AIToolResult, spent: inout Int) -> AIToolResult {
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
