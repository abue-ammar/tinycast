import Foundation
import Testing

@testable import Tinycast

extension AIProviderTests {
    // MARK: Server-sent events

    @Test func sseFramesSurviveSplitsAndTheLastFlushesAtFinish() {
        var parser = SSEParser()
        #expect(parser.feed(Data("data: hel".utf8)).isEmpty, "a partial frame waits")
        #expect(
            parser.feed(Data("lo\n\ndata: world\r\n\r\n".utf8)) == ["hello", "world"],
            "LF and CRLF reassemble")
        #expect(parser.feed(Data(": keepalive\n\ndata: final".utf8)).isEmpty, "a comment is ignored")
        #expect(parser.finish() == ["final"])
    }

    @Test func openAICompatibleStreamsDecodeReasoningTextUsageAndDone() throws {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        let data = Data(
            """
            data: {"choices":[{"delta":{"reasoning":"working"}}]}

            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2}}

            data: [DONE]

            """.utf8)
        let events = try decoder.feed(data) + decoder.finish()
        #expect(events.contains(.thinking), "reasoning is surfaced as state, not answer text")
        #expect(events.contains(.reasoning("working")), "and its text reaches the reasoning fold")
        #expect(events.contains(.text("Hello")))
        #expect(events.contains(.usage(AIUsage(inputTokens: 3, outputTokens: 2))))
        #expect(events.last == .finished)
    }

    @Test func anthropicStreamsDecodeThinkingTextAccumulatedUsageAndStop() throws {
        var decoder = AIStreamDecoder(shape: .anthropic)
        let data = Data(
            """
            data: {"type":"message_start","message":{"usage":{"input_tokens":4}}}

            data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"Hmm"}}

            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}

            data: {"type":"message_delta","usage":{"output_tokens":1}}

            data: {"type":"message_stop"}

            """.utf8)
        let events = try decoder.feed(data) + decoder.finish()
        #expect(events.contains(.text("Hi")))
        #expect(events.contains(.reasoning("Hmm")), "thinking is reasoning")
        #expect(!events.contains(.text("Hmm")), "never answer text")
        #expect(
            events.contains(.usage(AIUsage(inputTokens: 4, outputTokens: 1))),
            "usage accumulates across events")
        #expect(events.last == .finished)
    }

    // MARK: Captured streams

    /// Real OpenRouter captures, with the reasoning ones proving thought never leaks into text.
    @Test(arguments: [
        StreamCapture(file: "openrouter-plain", text: "1, 2, 3.", reasons: false),
        StreamCapture(file: "openrouter-gemma", text: nil, reasons: false),
        StreamCapture(file: "openrouter-nemotron-reasoning", text: nil, reasons: true),
        StreamCapture(file: "openrouter-cohere-reasoning", text: nil, reasons: true)
    ])
    func capturedStreamsDecodeHoweverTheyArrive(_ capture: StreamCapture) throws {
        let data = try Data(contentsOf: Fixture.url("AI/\(capture.file).txt"))
        let whole = StreamFixtures.decodeAll(data, slice: data.count)
        #expect(whole == StreamFixtures.decodeAll(data, slice: 7), "decodes the same in 7-byte slices")
        let text = StreamFixtures.answerText(whole)
        if let expected = capture.text {
            #expect(text == expected)
        } else {
            #expect(!text.isEmpty)
        }
        #expect(whole.contains(.thinking) == capture.reasons, "thinking shows only when the model reasoned")
        #expect(whole.last == .finished)
        #expect(whole.contains { if case .usage(let usage) = $0 { usage.totalTokens != nil } else { false } })
    }

    struct StreamCapture: CustomTestStringConvertible, Sendable {
        let file: String
        let text: String?
        let reasons: Bool

        var testDescription: String { file }
    }

    // MARK: Think tags

    @Test func aThinkTagCaptureKeepsReasoningAnswerAndUsageOrder() throws {
        let data = try Data(contentsOf: Fixture.url("AI/openai-think-tags.txt"))
        let whole = StreamFixtures.decodeAll(data, slice: data.count)
        #expect(whole == StreamFixtures.decodeAll(data, slice: 7), "survives 7-byte slices")
        #expect(StreamFixtures.reasoningText(whole) == "Plan carefully.")
        #expect(StreamFixtures.answerText(whole) == "The answer.")
        #expect(whole.contains(.thinking))
        #expect(whole.suffix(2) == [.usage(AIUsage(inputTokens: 5, outputTokens: 9)), .finished])
    }

    @Test(arguments: StreamFixtures.taggedReplySplits)
    func everyThreeWaySplitOfATaggedReplyKeepsReasoningAndAnswer(_ first: Int, _ second: Int) {
        let content = StreamFixtures.taggedReply
        let events = StreamFixtures.decodeContent([
            String(content[..<first]), String(content[first..<second]), String(content[second...])
        ])
        #expect(StreamFixtures.reasoningText(events) == "reason")
        #expect(StreamFixtures.answerText(events) == "answer")
    }

    @Test func oneCharacterPerDeltaKeepsReasoningAndAnswer() {
        let events = StreamFixtures.decodeContent(StreamFixtures.taggedReply.map(String.init))
        #expect(StreamFixtures.reasoningText(events) == "reason")
        #expect(StreamFixtures.answerText(events) == "answer")
    }

    @Test func onlyLeadingTagSpaceAndTheAnswerSeparatorAreRemoved() {
        let events = StreamFixtures.decodeContent([
            " \n", "<think> ", "\n", "reason \n</thi", "nk>\n", "\t", "answer", " \n"
        ])
        #expect(StreamFixtures.reasoningText(events) == " \nreason \n")
        #expect(StreamFixtures.answerText(events) == "answer \n")
    }

    @Test func aSingleDeltaEmitsReasoningBeforeAnswerText() {
        #expect(
            StreamFixtures.decodeContent(["<think>r</think>answer"])
                == [.thinking, .reasoning("r"), .text("answer"), .finished])
    }

    @Test(arguments: [
        "<div>x</div>", "<thinking>…", "\n\nHello", "Hello <think>x</think> world",
        "Hello<think>x</think> world", "</think>answer"
    ])
    func contentThatIsNotALeadingThinkBlockStaysVerbatim(_ literal: String) {
        let events = StreamFixtures.decodeContent(literal.map(String.init))
        #expect(StreamFixtures.answerText(events) == literal)
        #expect(!events.contains(.thinking))
    }

    @Test(arguments: ["<think></think>", "<think> \n\t</think>"])
    func emptyOrWhitespaceOnlyReasoningEmitsNothing(_ content: String) {
        #expect(StreamFixtures.decodeContent(content.map(String.init)) == [.finished])
    }

    @Test func recognitionNeverResumesAfterTheFirstBlock() {
        let events = StreamFixtures.decodeContent(["<think>r</think>", "answer <think>literal</think> world"])
        #expect(StreamFixtures.answerText(events) == "answer <think>literal</think> world")
    }

    /// `true` ends on DONE, `false` on EOF.
    @Test(arguments: [true, false])
    func unclosedReasoningAndUndecidedContentFlushAtTheEnd(_ done: Bool) {
        let unclosed = StreamFixtures.decodeContent(["<think>reason</thi"], done: done)
        #expect(StreamFixtures.reasoningText(unclosed) == "reason</thi")
        #expect(StreamFixtures.answerText(unclosed).isEmpty)
        #expect(StreamFixtures.answerText(StreamFixtures.decodeContent(["<thi"], done: done)) == "<thi")
    }

    @Test func endOfFileFlushesTheHeldPrefixOnce() throws {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        _ = try decoder.feed(StreamFixtures.contentFrame("<thi"))
        #expect(try decoder.finish() == [.text("<thi")])
        #expect(try decoder.finish() == [], "never flushes twice")
    }

    @Test func doneFlushesReasoningBeforeCompletionAndEndOfFileAddsNothing() throws {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        _ = try decoder.feed(StreamFixtures.contentFrame("<think>r</thi"))
        #expect(
            try decoder.feed(Data("data: [DONE]\n\n".utf8)) == [.thinking, .reasoning("</thi"), .finished])
        #expect(try decoder.finish() == [])
    }

    @Test func reasoningPrecedesToolsWithoutReorderingToolUsageOrCompletion() {
        let tools = Data(
            """
            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"read","arguments":"{}"}}]}}]}

            data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

            data: {"choices":[],"usage":{"prompt_tokens":2,"completion_tokens":3}}

            data: [DONE]

            """.utf8)
        let events = StreamFixtures.decodeAll(
            StreamFixtures.contentFrame("<think>r</think>") + tools, slice: 7)
        #expect(
            events == [
                .thinking, .reasoning("r"),
                .toolCallRequested(AIToolCall(id: "c1", name: "read", arguments: "{}")),
                .usage(AIUsage(inputTokens: 2, outputTokens: 3)), .finished
            ])
    }

    @Test func reasoningContentKeepsItsOwnEventSequence() {
        let native = Data(
            """
            data: {"choices":[{"delta":{"reasoning_content":"native"}}]}

            data: {"choices":[{"delta":{"content":"answer"}}]}

            data: [DONE]

            """.utf8)
        #expect(
            StreamFixtures.decodeAll(native, slice: 7) == [
                .thinking, .reasoning("native"), .text("answer"), .finished
            ])
    }

    // MARK: Refusals

    /// A refusal is read, not discarded: the status's line, then what the provider said under it.
    @Test(arguments: Refusal.all)
    func aRefusalShowsTheProvidersOwnWordsUnderItsStatusLine(_ refusal: Refusal) {
        let shown = AIProviderFailure.description(
            status: refusal.status, body: Data(refusal.body.utf8), retryAfter: refusal.retryAfter, secrets: []
        )
        #expect(shown == refusal.expected)
    }

    struct Refusal: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let status: Int
        let body: String
        var retryAfter: String?
        let expected: String

        static let general = "The provider rejected the model or request (HTTP 400)."
        static let unavailable = "The provider is temporarily unavailable (HTTP 502)."
        static let unprocessable = "The provider rejected the model or request (HTTP 422)."

        static let all: [Refusal] = [
            Refusal(
                testDescription: "OpenAI's error shape", status: 400,
                body: #"{"error":{"object":"error","type":"invalid_request_error","message":"#
                    + #""Model accounts/fireworks/models/glm-5p3-flash does not support image input."}}"#,
                expected:
                    "\(general)\n\nModel accounts/fireworks/models/glm-5p3-flash does not support image input."
            ),
            Refusal(
                testDescription: "OpenRouter's nested upstream body, read through its raw string",
                status: 400,
                body: #"{"error":{"message":"Provider returned error","code":400,"metadata":"#
                    + #"{"raw":"{\"error\":{\"message\":\"Maximum context length is 8192 tokens\"}}","#
                    + #""provider_name":"Fireworks"}}}"#,
                expected: "\(general)\n\nMaximum context length is 8192 tokens"),
            Refusal(
                testDescription: "Anthropic's shape", status: 400,
                body:
                    #"{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long"}}"#,
                expected: "\(general)\n\nprompt is too long"),
            Refusal(
                testDescription: "Gemini's array", status: 400,
                body: #"[{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}]"#,
                expected: "\(general)\n\nAPI key not valid."),
            Refusal(
                testDescription: "vLLM's shape", status: 404,
                body: #"{"object":"error","message":"The model `x` does not exist.","code":404}"#,
                expected:
                    "The provider rejected the model or request (HTTP 404).\n\nThe model `x` does not exist."),
            Refusal(
                testDescription: "a status keeps its own line, with the reason under it", status: 429,
                body: #"{"error":{"message":"You exceeded your current quota."}}"#, retryAfter: "12",
                expected: "Rate limit reached — retry after 12 seconds.\n\nYou exceeded your current quota."),
            Refusal(
                testDescription: "a plain-text body is shown as sent", status: 400,
                body: "Bad request: unknown field", expected: "\(general)\n\nBad request: unknown field"),
            Refusal(
                testDescription: "an HTML error page is not pasted into the chat", status: 502,
                body: "<html><body>Bad gateway</body></html>", expected: unavailable),
            Refusal(
                testDescription: "an empty body leaves the line alone", status: 401,
                body: "", expected: "API key rejected — check it in Settings."),
            Refusal(
                testDescription: "a nested HTML page gives way to the message beside it", status: 502,
                body:
                    #"{"error":{"message":"Upstream timed out","metadata":{"raw":"<html>Bad gateway</html>"}}}"#,
                expected: "\(unavailable)\n\nUpstream timed out"),
            Refusal(
                testDescription: "a nested HTML page is left out when it is all there is", status: 502,
                body: #"{"error":"<html><body>Bad gateway</body></html>"}"#, expected: unavailable),
            Refusal(
                testDescription: "an upstream body with no message falls back to the wrapper's", status: 400,
                body: #"{"error":{"message":"Provider returned error","metadata":{"raw":"{\"code\":7}"}}}"#,
                expected: "\(general)\n\nProvider returned error"),
            Refusal(
                testDescription: "a bare JSON string loses its quotes", status: 400,
                body: #""Bad request""#, expected: "\(general)\n\nBad request"),
            Refusal(
                testDescription: "text that only starts like JSON is still text", status: 400,
                body: "[Errno 111] Connection refused",
                expected: "\(general)\n\n[Errno 111] Connection refused"),
            Refusal(
                testDescription: "a body cut inside its message shows no fragment of JSON", status: 400,
                body: #"{"error":{"message":"Half a mess"#, expected: general),
            Refusal(
                testDescription: "a cut array is read the same way, however it is spaced", status: 400,
                body: "[\n  {\"error\": {\"message\": \"Too long\"}", expected: "\(general)\n\nToo long"),
            Refusal(
                testDescription: "a cut list of strings is not shown raw", status: 400,
                body: #"["first error", "second"#, expected: general),
            Refusal(
                testDescription: "nor a cut list of anything else", status: 400, body: "[1, 2,",
                expected: general),
            Refusal(
                testDescription: "a sentence that opens with a bracket and closes it is a sentence",
                status: 400,
                body: #"["model"] is not supported"#, expected: "\(general)\n\n[\"model\"] is not supported"),
            Refusal(
                testDescription: "whichever bracket it is", status: 400,
                body: "{model} was not found", expected: "\(general)\n\n{model} was not found"),
            Refusal(
                testDescription: "a sentence bracketed from end to end", status: 400,
                body: "[request timed out]", expected: "\(general)\n\n[request timed out]"),
            Refusal(
                testDescription: "a cut body's HTML first candidate does not hide the next one", status: 400,
                body: #"{"message":"<html>Bad gateway</html>","detail":"Reduce your prompt","padding":"#,
                expected: "\(general)\n\nReduce your prompt"),
            Refusal(
                testDescription: "a cut upstream body falls back to the wrapper's message", status: 400,
                body:
                    #"{"error":{"message":"Provider returned error","metadata":{"raw":"{\"error\":{\"mess"}}}"#,
                expected: "\(general)\n\nProvider returned error"),
            Refusal(
                testDescription: "an `error` echoed back in the request does not pass for the message",
                status: 422,
                body:
                    #"{"detail":[{"input":{"error":"boom from a tool"},"msg":"Input should be a valid string","x":"#,
                expected: "\(unprocessable)\n\nInput should be a valid string")
        ]
    }

    @Test func aBodyTheCapCutStillGivesUpTheMessageNearItsStart() {
        let echo = String(repeating: "A", count: AIProviderFailure.bodyLimit)
        let oversized =
            #"{"detail":[{"type":"string_type","msg":"Input should be a valid string","input":"\#(echo)"}]}"#
        let shown = AIProviderFailure.description(
            status: 422, body: Data(oversized.utf8).prefix(AIProviderFailure.bodyLimit), retryAfter: nil,
            secrets: [])
        #expect(shown == "\(Refusal.unprocessable)\n\nInput should be a valid string")
    }

    @Test func aVeryLongMessageIsCutRatherThanFillingTheChat() {
        let long = String(repeating: "x", count: AIProviderFailure.messageLimit + 50)
        let shown = AIProviderFailure.description(
            status: 400, body: Data(#"{"error":{"message":"\#(long)"}}"#.utf8), retryAfter: nil, secrets: [])
        #expect(shown.hasSuffix("x…"))
        #expect(shown.count == Refusal.general.count + 2 + AIProviderFailure.messageLimit + 1)
    }

    @Test func theKeyABearerTokenAndKeyShapedStringsNeverReachTheTranscript() {
        let key = "fw_3c8a7b2e91d04f5a"
        let shown = AIProviderFailure.description(
            status: 400,
            body: Data(
                #"{"error":{"message":"Bad header: Bearer \#(key), also sk-proj-abcdefghijklmnop"}}"#.utf8),
            retryAfter: nil, secrets: [key])
        #expect(!shown.contains(key))
        #expect(!shown.contains("sk-proj-abcdef"))
        #expect(shown.contains("[redacted]"))
    }

    @Test func aKeyTheCutLandsInsideIsRedactedFirstNotHalfShown() {
        let filler = String(repeating: "x", count: AIProviderFailure.messageLimit - 8)
        let shown = AIProviderFailure.description(
            status: 400, body: Data(#"{"error":{"message":"\#(filler) sk-proj-abcdefghijklmnop"}}"#.utf8),
            retryAfter: nil, secrets: [])
        #expect(!shown.contains("sk-pro"))
    }

    /// A short key is a key all the same, digit or not, but only as a whole word.
    @Test(arguments: [
        ("Invalid key: abc123.", ["abc123"], "Invalid key: [redacted]."),
        ("Port 7 refused key 7 (70 tries)", ["7", ""], "Port [redacted] refused key [redacted] (70 tries)"),
        ("Invalid key: abcdef", ["abcdef"], "Invalid key: [redacted]"),
        ("Received API Key = sk-1234", ["sk-1234"], "Received API Key = [redacted]")
    ])
    func shortSecretsAreRedactedAsWholeWords(_ text: String, _ secrets: [String], _ expected: String) {
        #expect(AIProviderFailure.redacted(text, secrets: secrets) == expected)
    }

    // MARK: Broken streams

    @Test func aMidStreamErrorPayloadEndsTheStreamWithTheProvidersMessage() {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        let failure = Data(
            """
            data: {"choices":[{"delta":{"content":"Par"}}]}

            data: {"error":{"message":"Provider returned error","code":502}}

            data: {"choices":[{"delta":{"content":"never"}}]}

            """.utf8)
        var events: [AIStreamEvent] = []
        let error = #expect(throws: AIProviderError.self) { events = try decoder.feed(failure) }
        #expect(error == .responseFailed("Provider returned error"))
        #expect(decoder.isTerminal)
        #expect(events.isEmpty, "nothing after the error is decoded")
    }

    @Test(arguments: [
        StreamFailure(
            "the upstream reason, with the connection's key out", shape: .openAICompatible,
            secrets: ["hunter2-gateway-key"],
            frame: #"data: {"error":{"message":"Provider returned error","code":400,"metadata":{"raw":"#
                + #""{\"error\":{\"message\":\"Too long for key hunter2-gateway-key\"}}"}}}"#,
            message: "Too long for key [redacted]"),
        StreamFailure(
            "an HTML page in Tinycast's own words", shape: .openAICompatible,
            frame: #"data: {"error":{"message":"<html>Bad gateway</html>"}}"#,
            message: "The provider stopped the response with an error."),
        StreamFailure(
            "a message that opens with a bracket", shape: .openAICompatible,
            frame: #"data: {"error":{"message":"[\"model\"] is not supported"}}"#,
            message: #"["model"] is not supported"#),
        StreamFailure(
            "an Anthropic error event names the cause without echoing the key", shape: .anthropic,
            frame: #"data: {"type":"error","error":{"type":"authentication_error"}}"#,
            message: "API key rejected — check it in Settings.")
    ])
    func aMidStreamErrorFailsWithAReadableMessage(_ failure: StreamFailure) throws {
        var decoder = AIStreamDecoder(shape: failure.shape, secrets: failure.secrets)
        let error = #expect(throws: AIProviderError.self) { _ = try decoder.feed(failure.data) }
        #expect(error == .responseFailed(failure.message))
    }

    @Test func unparseableJSONIsRejectedAndEndsTheStream() {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        #expect(throws: (any Error).self) { _ = try decoder.feed(Data("data: {not json\n\n".utf8)) }
        #expect(decoder.isTerminal)
    }

    @Test func anAnthropicErrorEventShowsWhatItSaidUnderTheLine() throws {
        let error = try StreamFixtures.anthropicError(#"{"type":"overloaded_error","message":"Overloaded"}"#)
        #expect(
            error.localizedDescription == "The provider stopped the response with an error.\n\nOverloaded")
    }

    @Test func anAnthropicErrorEventNeverShowsTheConnectionsKey() throws {
        let error = try StreamFixtures.anthropicError(
            #"{"type":"api_error","message":"Bad key hunter2-gateway-key"}"#, secrets: ["hunter2-gateway-key"]
        )
        #expect(error.localizedDescription.hasSuffix("Bad key [redacted]"))
    }

    @Test func anAnthropicErrorEventNeverShowsAnHTMLPageForAMessage() throws {
        let error = try StreamFixtures.anthropicError(
            #"{"type":"api_error","message":"<html>Bad gateway</html>"}"#)
        #expect(error.localizedDescription == "The provider stopped the response with an error.")
    }

    @Test func textBeforeACutOffIsDeliveredAndTheStreamStaysOpenForTheCallerToFail() throws {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        let partial = try decoder.feed(
            Data("data: {\"choices\":[{\"delta\":{\"content\":\"half\"}}]}\n\n".utf8))
        #expect(partial == [.text("half")])
        #expect(!decoder.isTerminal)
    }

    struct StreamFailure: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let shape: AIHTTPConfiguration.APIShape
        let secrets: [String]
        let frame: String
        let message: String

        var data: Data { Data((frame + "\n\n").utf8) }

        init(
            _ description: String, shape: AIHTTPConfiguration.APIShape, secrets: [String] = [], frame: String,
            message: String
        ) {
            testDescription = description
            self.shape = shape
            self.secrets = secrets
            self.frame = frame
            self.message = message
        }
    }

    // MARK: Installed CLI streams

    @Test func openCodeTextAndItsCleanupSessionDecodeTogether() {
        let data = Data(#"{"type":"text","sessionID":"ses_1","part":{"text":"Hello"}}"#.utf8)
        #expect(
            InstalledAIStreamDecoder.decode(data, kind: .openCode)
                == InstalledAIStreamFrame(events: [.text("Hello")], sessionID: "ses_1"))
    }

    @Test func openCodeReasoningOpensItsOwnBlock() {
        let data = Data(#"{"type":"reasoning","sessionID":"ses_1","part":{"text":"Weighing it"}}"#.utf8)
        #expect(
            InstalledAIStreamDecoder.decode(data, kind: .openCode).events == [.reasoning("\n\nWeighing it")])
    }

    @Test func anOpenCodeStepReportsUsageAndLeavesTheFinishToTheCleanExit() {
        let data = Data(
            #"""
            {"type":"step_finish","sessionID":"ses_1","part":{"cost":0.25,"tokens":{"input":12,
            "output":4,"reasoning":3,"cache":{"read":5,"write":1}}}}
            """#.utf8)
        let frame = InstalledAIStreamDecoder.decode(data, kind: .openCode)
        #expect(
            frame.events == [
                .usage(
                    AIUsage(
                        inputTokens: 12, outputTokens: 7, cachedInputTokens: 6, reasoningTokens: 3,
                        costUSD: 0.25))
            ])
        #expect(!frame.completed)
    }

    @Test func anOpenCodeErrorBeforeAnySessionFailsTheTurnWithNothingToDelete() {
        let data = Data(
            #"{"type":"error","sessionID":"","error":{"type":"unknown","message":"No provider"}}"#.utf8)
        let frame = InstalledAIStreamDecoder.decode(data, kind: .openCode)
        #expect(frame.error == "No provider")
        #expect(frame.sessionID == nil)
    }

    @Test func openCodeModelsListByReferenceWithEffortsImagesAndTools() throws {
        let catalog = InstalledAIModel.openCodeCatalog(
            #"""
            {"location":{"directory":"/w"},"data":[
            {"id":"gpt-5","providerID":"openai","name":"GPT-5",
            "capabilities":{"tools":true,"input":["text","image"],"output":["text"]},
            "variants":[{"id":"high"},{"id":"low"},{"id":"minimal"}]},
            {"id":"glm-4.6","providerID":"zai","name":"GLM 4.6",
            "capabilities":{"tools":true,"input":["text"],"output":["text"]},"variants":[]},
            {"id":"claude-sonnet-4-5","providerID":"anthropic","name":"Claude Sonnet 4.5",
            "capabilities":{"tools":true,"input":["text","image","pdf"],"output":["text"]},
            "variants":[]}]}
            """#)
        #expect(catalog.map(\.id) == ["anthropic/claude-sonnet-4-5", "openai/gpt-5", "zai/glm-4.6"])
        try #require(catalog.count == 3)
        #expect(
            catalog[1].efforts.map(\.id) == ["minimal", "low", "high"], "variants become efforts in order")
        #expect(catalog.map(\.acceptsImages) == [true, true, false])
        #expect(catalog.allSatisfy { $0.supportsTools })
    }

    @Test func openCodeModelsWithoutAdvertisedToolSupportOfferNoTools() {
        let catalog = InstalledAIModel.openCodeCatalog(
            #"""
            {"data":[{"id":"text","providerID":"local","capabilities":{"tools":false}},
            {"id":"unknown","providerID":"local"}]}
            """#)
        #expect(catalog.map(\.supportsTools) == [false, false])
    }

    @Test func anOpenCodeAnswerThatIsNotTheModelListYieldsNoModels() {
        #expect(InstalledAIModel.openCodeCatalog("Error: server failed to start").isEmpty)
    }

    @Test func claudePartialTextDecodesWithoutReplayingItsFullMessage() {
        let data = Data(#"{"type":"stream_event","event":{"delta":{"type":"text_delta","text":"Hi"}}}"#.utf8)
        #expect(InstalledAIStreamDecoder.decode(data, kind: .claude).events == [.text("Hi")])
    }

    @Test func claudeResultUsageEndsTheStream() {
        let data = Data(
            #"{"type":"result","is_error":false,"usage":{"input_tokens":8,"output_tokens":3}}"#.utf8)
        let frame = InstalledAIStreamDecoder.decode(data, kind: .claude)
        #expect(frame.events == [.usage(AIUsage(inputTokens: 8, outputTokens: 3))])
        #expect(frame.completed)
    }

    @Test func cursorLiveDeltasDecodeAndBufferedFlushesAreIgnored() {
        let delta = Data(
            #"{"type":"assistant","timestamp_ms":1,"message":{"content":[{"type":"text","text":"Hi"}]}}"#.utf8
        )
        #expect(InstalledAIStreamDecoder.decode(delta, kind: .cursor).events == [.text("Hi")])
        let flush = Data(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Hi"}]}}"#.utf8)
        #expect(InstalledAIStreamDecoder.decode(flush, kind: .cursor).events.isEmpty, "no timestamp_ms")
    }

    @Test func cursorResultEndsTheStreamAndInitCarriesTheSession() {
        let done = Data(#"{"type":"result","subtype":"success","result":"Hi"}"#.utf8)
        #expect(InstalledAIStreamDecoder.decode(done, kind: .cursor).completed)
        let session = Data(#"{"type":"system","subtype":"init","session_id":"ses_cursor"}"#.utf8)
        #expect(InstalledAIStreamDecoder.decode(session, kind: .cursor).sessionID == "ses_cursor")
    }

    @Test func grokPartialTextReusesTheClaudeShapeAndKeepsTheSession() {
        let data = Data(
            #"{"type":"stream_event","session_id":"ses_g","event":{"delta":{"type":"text_delta","text":"Yo"}}}"#
                .utf8)
        let frame = InstalledAIStreamDecoder.decode(data, kind: .grok)
        #expect(frame.events == [.text("Yo")])
        #expect(frame.sessionID == "ses_g")
    }

    @Test func grokResultUsageEndsTheStreamAndNamesTheSessionToDelete() {
        let data = Data(
            #"{"type":"result","is_error":false,"session_id":"ses_g","usage":{"input_tokens":5,"output_tokens":1}}"#
                .utf8)
        let frame = InstalledAIStreamDecoder.decode(data, kind: .grok)
        #expect(frame.events == [.usage(AIUsage(inputTokens: 5, outputTokens: 1))])
        #expect(frame.completed)
        #expect(frame.sessionID == "ses_g")
    }

    @Test func grokExecutionErrorsNameTheCauseAndIgnoreAnEmptySession() {
        let data = Data(
            #"""
            {"type":"result","subtype":"error_during_execution","is_error":true,"errors":["Not signed in."],"session_id":""}
            """#.utf8)
        let frame = InstalledAIStreamDecoder.decode(data, kind: .grok)
        #expect(frame.error == "Not signed in.")
        #expect(frame.sessionID == nil)
        #expect(!frame.completed)
    }

    @Test func aGrokErrorWithNoCauseStillNamesGrok() {
        let data = Data(#"{"type":"result","is_error":true}"#.utf8)
        #expect(
            InstalledAIStreamDecoder.decode(data, kind: .grok).error == "Grok could not finish the response.")
    }
}

private enum StreamFixtures {
    static let taggedReply = Array("<think>reason</think>\n\nanswer")

    static let taggedReplySplits: [(Int, Int)] = (0...taggedReply.count).flatMap { first in
        (first...taggedReply.count).map { (first, $0) }
    }

    static func contentFrame(_ content: String) -> Data {
        let quoted = (try? JSONEncoder().encode(content)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        return Data("data: {\"choices\":[{\"delta\":{\"content\":\(quoted)}}]}\n\n".utf8)
    }

    static func decodeContent(_ fragments: [String], done: Bool = true) -> [AIStreamEvent] {
        var data = fragments.reduce(into: Data()) { $0 += contentFrame($1) }
        if done { data += Data("data: [DONE]\n\n".utf8) }
        return decodeAll(data, slice: max(1, data.count))
    }

    static func reasoningText(_ events: [AIStreamEvent]) -> String {
        events.compactMap { if case .reasoning(let text) = $0 { text } else { nil } }.joined()
    }

    static func answerText(_ events: [AIStreamEvent]) -> String {
        events.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
    }

    static func decodeAll(_ data: Data, slice: Int) -> [AIStreamEvent] {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        var events: [AIStreamEvent] = []
        for start in stride(from: 0, to: data.count, by: slice) {
            events += (try? decoder.feed(data[start..<min(start + slice, data.count)])) ?? []
        }
        events += (try? decoder.finish()) ?? []
        return events
    }

    /// The error an Anthropic `error` event with this `error` object fails the stream with.
    static func anthropicError(_ error: String, secrets: [String] = []) throws -> any Error {
        var decoder = AIStreamDecoder(shape: .anthropic, secrets: secrets)
        let frame = Data(#"data: {"type":"error","error":\#(error)}"#.utf8) + Data("\n\n".utf8)
        return try #require(throws: (any Error).self) { _ = try decoder.feed(frame) }
    }
}
