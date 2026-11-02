import Foundation
import Synchronization

@main
@MainActor
struct AIResponsesTests {
    static var passes = 0
    static var failures = 0

    static let configuration = AIHTTPConfiguration(
        provider: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!,
        model: "gpt-6.1-terra")
    static let tool = AITool(
        name: "files__read", description: "Read a file",
        parameters: .object([
            "type": .string("object"),
            "properties": .object(["path": .object(["type": .string("string")])])
        ]), origin: "Files")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        endpointsStayWithinTheirProvider()
        requestBodiesKeepInstructionsAttachmentsAndSchemas()
        try streamsCarryOnlyCompletedCalls()
        try failuresNeverReleaseTools()
        try await toolRoundsReplayTheCompleteOutput()
        try await reasoningCountsAgainstTheTurnBudget()
        await cancellationStopsTheNextTool()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func endpointsStayWithinTheirProvider() {
        for path in ["/v1", "/v1/", "/v1/chat/completions", "/v1/responses", "/v1/responses/"] {
            let url = URL(string: "https://api.openai.com" + path)!
            let native = AIHTTPConfiguration(provider: .openAI, baseURL: url, model: "any-model")
            expect(native.shape == .openAIResponses, "direct OpenAI uses Responses at \(path)")
            expect(
                native.endpointURL.path == "/v1/responses",
                "a saved base or full endpoint resolves Responses once at \(path)")
            expect(
                !AIConnection(provider: .openAI, baseURL: url.absoluteString).takesThinkingField,
                "an official endpoint never receives a gateway's thinking control")
        }
        for (provider, url) in [
            (AIProviderKind.openAI, "https://gateway.example/v1"),
            (.openAI, "https://api.openai.com.example/v1"),
            (.openAICompatible, "https://api.openai.com/v1"),
            (.gemini, AIProviderKind.gemini.defaultBaseURL),
            (.openRouter, AIProviderKind.openRouter.defaultBaseURL)
        ] {
            let compatible = AIHTTPConfiguration(
                provider: provider, baseURL: URL(string: url)!, model: "gpt-6.1-terra")
            expect(compatible.shape == .openAICompatible, "\(url) keeps its compatible wire format")
            expect(
                compatible.endpointURL.path.hasSuffix("/chat/completions"),
                "a model name never migrates another provider's endpoint")
        }
        let query = try? AIModelDiscovery.query(
            provider: .openAI, baseURL: configuration.endpointURL, apiKey: "", appTitle: "Tests")
        expect(query?.request.url?.path == "/v1/models", "a full Responses URL still discovers models")
    }

    static func requestBodiesKeepInstructionsAttachmentsAndSchemas() {
        let image = AIImage(data: Data([1, 2]), mimeType: "image/png")
        let pdf = AIDocument(data: Data("%PDF".utf8), mimeType: "application/pdf", name: "notes.pdf")
        let body = AIRequestBody.make(
            AIRequest(
                instructions: "Answer briefly",
                messages: [
                    AIMessage(role: .user, text: "read", images: [image], documents: [pdf]),
                    AIMessage(role: .assistant, text: "Earlier answer")
                ], tools: [tool]), configuration: configuration)
        expect(body["store"] as? Bool == false, "Responses state is never stored server-side")
        expect(body["stream"] as? Bool == true, "Responses streams through the existing transport")
        expect(body["instructions"] as? String == "Answer briefly", "instructions remain top-level")
        expect(body["messages"] == nil, "Responses never receives Chat Completions messages")
        expect(
            body["reasoning_effort"] == nil && body["reasoning"] == nil,
            "the migration preserves the model's default reasoning")
        let input = body["input"] as? [[String: Any]] ?? []
        let parts = input.first?["content"] as? [[String: Any]] ?? []
        expect(
            parts.compactMap { $0["type"] as? String } == ["input_text", "input_image", "input_file"],
            "text, images and PDFs use native input parts")
        expect(parts.dropFirst().first?["image_url"] as? String == image.dataURL, "images keep their data")
        expect(parts.last?["filename"] as? String == pdf.name, "PDFs keep their filename")
        expect(parts.last?["file_data"] as? String == pdf.dataURL, "PDFs keep their data")
        expect(input.last?["content"] as? String == "Earlier answer", "saved assistant text remains input")
        let function = (body["tools"] as? [[String: Any]])?.first ?? [:]
        expect(function["name"] as? String == tool.name, "function definitions are flattened")
        expect(function["strict"] as? Bool == false, "optional MCP arguments remain optional")
        expect(function["parameters"].map(JSONValue.init) == tool.parameters, "MCP schemas stay intact")
        let plain = AIRequestBody.make(AIRequest(messages: []), configuration: configuration)
        expect(plain["instructions"] == nil && plain["tools"] == nil, "disabled capabilities add no fields")
    }

    static func streamsCarryOnlyCompletedCalls() throws {
        let output = outputItems(callID: "call_1")
        let frames =
            try frame(["type": "response.output_item.added", "item": ["type": "reasoning"]])
            + frame(["type": "response.output_text.delta", "delta": "Checking…"])
            + frame(["type": "response.function_call_arguments.delta", "delta": "{\"pa"])
        let complete = try completed(
            output,
            usage: [
                "input_tokens": 12, "output_tokens": 8,
                "input_tokens_details": ["cached_tokens": 4],
                "output_tokens_details": ["reasoning_tokens": 5]
            ])
        for slice in [1, 7, frames.count + complete.count] {
            var decoder = AIStreamDecoder(shape: .openAIResponses)
            let before = try feed(frames, slice: slice, decoder: &decoder)
            expect(!decoder.isTerminal, "deltas do not complete a response")
            expect(
                !before.contains {
                    if case .toolCallRequested = $0 { return true }; return false
                },
                "partial arguments cannot invoke a tool")
            let events = before + (try feed(complete, slice: slice, decoder: &decoder))
            expect(decoder.isTerminal && events.last == .finished, "response.completed ends the stream")
            expect(events.contains(.text("Checking…")), "answer text streams once")
            expect(
                events.filter {
                    if case .text = $0 { return true }; return false
                }.count == 1,
                "the completed output does not repeat streamed text")
            expect(events.contains(.thinking), "opaque reasoning still reports thinking activity")
            expect(
                events.contains(
                    .toolCallRequested(AIToolCall(id: "call_1", name: tool.name, arguments: "{}"))),
                "the complete function call uses call_id rather than the output item's id")
            expect(events.contains(.responseOutput(output.map(JSONValue.init))), "opaque output is preserved")
            let usage = AIUsage(inputTokens: 12, outputTokens: 8, reasoningTokens: 5)
            expect(events.contains(.usage(usage)), "input includes its cache and reasoning remains output")
            expect(usage.contextTokens == 20, "cached input is never counted twice")
            let repeated = try decoder.feed(complete)
            expect(repeated.isEmpty, "a repeated terminal event cannot repeat a call")
        }
        var refusal = AIStreamDecoder(shape: .openAIResponses)
        let refused = try refusal.feed(frame(["type": "response.refusal.delta", "delta": "Cannot help"]))
        expect(
            refused == [.text("Cannot help")], "refusals remain visible answer text")
    }

    static func failuresNeverReleaseTools() throws {
        for type in ["response.failed", "response.incomplete", "error"] {
            var decoder = AIStreamDecoder(shape: .openAIResponses, secrets: ["fixture-secret"])
            let failure: [String: Any] =
                type == "error"
                ? ["type": type, "message": "Failed with fixture-secret"]
                : [
                    "type": type,
                    "response": [
                        "error": ["message": "Failed with fixture-secret"],
                        "output": outputItems(callID: "must-not-run")
                    ]
                ]
            do {
                _ = try decoder.feed(frame(failure))
                expect(false, "\(type) must throw")
            } catch {
                expect(decoder.isTerminal, "\(type) terminates the decoder")
                expect(!error.localizedDescription.contains("fixture-secret"), "errors redact credentials")
                expect(error.localizedDescription.contains("[redacted]"), "the provider error is still shown")
            }
        }
        var incomplete = AIStreamDecoder(shape: .openAIResponses)
        do {
            _ = try incomplete.feed(
                frame([
                    "type": "response.incomplete",
                    "response": ["error": NSNull(), "incomplete_details": ["reason": "max_output_tokens"]]
                ]))
            expect(false, "an output limit is a failed turn")
        } catch {
            expect(error.localizedDescription.contains("max_output_tokens"), "the incomplete reason is shown")
        }
        var closed = AIStreamDecoder(shape: .openAIResponses)
        _ = try closed.feed(frame(["type": "response.output_text.delta", "delta": "partial"]))
        _ = try closed.finish()
        expect(!closed.isTerminal, "EOF never turns a truncated response into success")
        var malformed = AIStreamDecoder(shape: .openAIResponses)
        do {
            _ = try malformed.feed(Data("data: [DONE]\n\n".utf8))
            expect(false, "the Chat Completions terminator is not a Responses completion")
        } catch {
            expect(error as? AIProviderError == .malformedResponse, "invalid Responses data fails clearly")
        }
    }

    static func toolRoundsReplayTheCompleteOutput() async throws {
        let first = outputItems(callID: "call_1")
        let second = outputItems(callID: "call_2")
        let base = ResponsesFixtureProvider(replies: [
            try completed(first), try completed(second),
            try frame(["type": "response.output_text.delta", "delta": "done"]) + completed([])
        ])
        let provider = AIToolLoopProvider(base: base, tools: [tool], maxRounds: 3) { call in
            AIToolResult(callID: call.id, content: "file contents", isError: false)
        }
        var events: [AIStreamEvent] = []
        let request = AIRequest(instructions: "Brief", messages: [AIMessage(role: .user, text: "read")])
        for try await event in provider.stream(request) { events.append(event) }
        expect(base.requests.count == 3, "two tool rounds reach the final answer")
        expect(events.last == .finished && events.contains(.text("done")), "the answer completes once")
        expect(
            !events.contains {
                if case .responseOutput = $0 { return true }; return false
            },
            "opaque continuation items never reach the transcript")
        guard let last = base.requests.last else { return }
        let body = AIRequestBody.make(last, configuration: configuration)
        let input = body["input"] as? [[String: Any]] ?? []
        guard input.count == 9 else {
            expect(false, "the final request contains the question and both complete tool rounds")
            return
        }
        expect(
            input.compactMap { $0["type"] as? String } == [
                "reasoning", "message", "function_call", "function_call_output",
                "reasoning", "message", "function_call", "function_call_output"
            ], "reasoning, commentary, calls and results retain their order across rounds")
        expect(JSONValue(input[1]) == JSONValue(first[0]), "encrypted reasoning survives replay unchanged")
        expect(JSONValue(input[2]) == JSONValue(first[1]), "assistant phase survives replay unchanged")
        expect(input[4]["call_id"] as? String == "call_1", "the result answers its function call")
        expect(body["instructions"] as? String == "Brief", "every round keeps its instructions")
        expect(request.messages.count == 1, "a finished turn cannot modify the caller's conversation")
    }

    static func reasoningCountsAgainstTheTurnBudget() async throws {
        var output = outputItems(callID: "large")
        output[0]["encrypted_content"] = String(repeating: "x", count: AIToolLoopProvider.maxTurnHistoryBytes)
        let limits: [Int?] = [nil, 25]
        for limit in limits {
            let base = ResponsesFixtureProvider(replies: [try completed(output), try completed([])])
            let provider = AIToolLoopProvider(base: base, tools: [tool], maxRounds: limit) { call in
                AIToolResult(callID: call.id, content: "ok", isError: false)
            }
            do {
                for try await _ in provider.stream(AIRequest(messages: [])) {}
                expect(false, "opaque reasoning must not bypass the turn budget")
            } catch {
                expect(base.requests.count == 1, "a full turn is never billed for another round")
                expect(
                    error.localizedDescription
                        == String(
                            localized: "Stopped because this turn's tool history is too large."),
                    "fixed and unlimited turns name the size limit rather than the round cap")
            }
        }
    }

    static func cancellationStopsTheNextTool() async {
        let invoked = Mutex(0)
        let base = ResponsesFixtureProvider(replies: [
            (try? completed(outputItems(callID: "first") + outputItems(callID: "second"))) ?? Data()
        ])
        let provider = AIToolLoopProvider(base: base, tools: [tool], maxRounds: 3) { call in
            invoked.withLock { $0 += 1 }
            try? await Task.sleep(for: .seconds(30))
            return AIToolResult(callID: call.id, content: "cancelled", isError: false)
        }
        let task = Task {
            for try await _ in provider.stream(AIRequest(messages: [])) {}
        }
        for _ in 0..<200 where invoked.withLock({ $0 }) == 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        _ = await task.result
        expect(invoked.withLock { $0 } == 1, "cancelling a running call never starts the next tool")
    }

    static func outputItems(callID: String) -> [[String: Any]] {
        [
            ["type": "reasoning", "id": "reason_" + callID, "summary": [], "encrypted_content": "opaque"],
            [
                "type": "message", "role": "assistant", "id": "msg_" + callID, "phase": "commentary",
                "status": "completed",
                "content": [["type": "output_text", "text": "Checking", "annotations": []]]
            ],
            [
                "type": "function_call", "id": "item_" + callID,
                "call_id": callID, "name": tool.name, "arguments": "{}"
            ]
        ]
    }

    static func frame(_ value: [String: Any]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return Data("data: ".utf8) + json + Data("\n\n".utf8)
    }

    static func completed(_ output: [[String: Any]], usage: [String: Any] = [:]) throws -> Data {
        try frame(["type": "response.completed", "response": ["output": output, "usage": usage]])
    }

    static func feed(_ data: Data, slice: Int, decoder: inout AIStreamDecoder) throws -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for offset in stride(from: 0, to: data.count, by: slice) {
            events += try decoder.feed(data.subdata(in: offset..<min(offset + slice, data.count)))
        }
        return events
    }
}

final class ResponsesFixtureProvider: AIProvider, Sendable {
    private let replies: [Data]
    private let recorded = Mutex<[AIRequest]>([])
    var requests: [AIRequest] { recorded.withLock { $0 } }

    init(replies: [Data]) {
        self.replies = replies
    }

    func stream(_ request: AIRequest) -> AIProviderStream {
        let index = recorded.withLock { requests in
            requests.append(request)
            return requests.count - 1
        }
        return AIProviderStream { continuation in
            do {
                guard replies.indices.contains(index) else { throw AIProviderError.malformedResponse }
                var decoder = AIStreamDecoder(shape: .openAIResponses)
                for event in try decoder.feed(replies[index]) { continuation.yield(event) }
                guard decoder.isTerminal else { throw AIProviderError.malformedResponse }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
