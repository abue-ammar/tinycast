import Foundation
import Testing

@testable import Tinycast

extension AIProviderTests {
    // MARK: Decoding calls

    /// Both providers stream a call's arguments in pieces; a half-parsed call would be uncallable.
    @Test func openAIArgumentFragmentsReassembleIntoOneWholeCall() throws {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        let stream = Data(
            """
            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1",\
            "function":{"name":"fs__read","arguments":"{\\"pa"}}]}}]}

            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"th\\":\\"/tmp\\"}"}}]}}]}

            data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

            data: [DONE]

            """.utf8)
        let events = try decoder.feed(stream) + decoder.finish()
        let call = AIToolCall(id: "call_1", name: "fs__read", arguments: #"{"path":"/tmp"}"#)
        #expect(events.contains(.toolCallRequested(call)))
        #expect(events.last == .finished, "the stream still terminates")
    }

    @Test func anAnthropicToolUseBlockReassemblesAndLeavesTheTurnOpen() throws {
        var decoder = AIStreamDecoder(shape: .anthropic)
        let stream = Data(
            """
            data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"fs__read"}}

            data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"path"}}

            data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\\":\\"/tmp\\"}"}}

            data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}

            """.utf8)
        let events = try decoder.feed(stream) + decoder.finish()
        let call = AIToolCall(id: "toolu_1", name: "fs__read", arguments: #"{"path":"/tmp"}"#)
        #expect(events.contains(.toolCallRequested(call)))
        #expect(
            !events.contains(.finished),
            "a tool turn ends without message_stop, so the loop decides whether the turn is over")
    }

    @Test func aTurnThatCalledNothingEmitsNoToolEvent() throws {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        #expect(try decoder.feed(Data("data: [DONE]\n\n".utf8)) == [.finished])
    }

    /// Gemini 3 400s on the follow-up turn if a call's signature doesn't come back unchanged.
    @Test func geminiThoughtSignaturesSurviveDecodingAndGoBackUnchanged() throws {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        let stream = Data(
            """
            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1",\
            "function":{"name":"exa__search","arguments":"{}"},\
            "extra_content":{"google":{"thought_signature":"sig=="}}},\
            {"index":1,"id":"c2","function":{"name":"exa__fetch","arguments":"{}"}}]}}]}

            data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

            data: [DONE]

            """.utf8)
        let calls = try (decoder.feed(stream) + decoder.finish()).compactMap { event -> AIToolCall? in
            if case .toolCallRequested(let call) = event { call } else { nil }
        }
        try #require(calls.count == 2)
        #expect(calls[0].thoughtSignature == "sig==", "the signature Gemini attaches survives decoding")
        #expect(calls[1].thoughtSignature == nil, "a parallel call that arrived without one stays so")

        let body = AIRequestBody.make(
            AIRequest(messages: [
                AIMessage(role: .user, text: "search"),
                AIMessage(role: .assistant, text: "", toolCalls: calls)
            ]),
            configuration: AIHTTPConfiguration(
                provider: .gemini,
                baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
                model: "gemini-3.5-flash-lite"))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let encoded = try #require(
            messages.first { $0["tool_calls"] != nil }?["tool_calls"] as? [[String: Any]])
        try #require(encoded.count == 2)
        let google = (encoded[0]["extra_content"] as? [String: Any])?["google"] as? [String: Any]
        #expect(google?["thought_signature"] as? String == "sig==", "it goes back exactly as it arrived")
        #expect(encoded[1]["extra_content"] == nil, "a call with no signature sends no extra_content")
    }

    // MARK: Web search

    struct SearchRoute: CustomTestStringConvertible, Sendable {
        let provider: AIProviderKind
        let baseURL: String?
        let searches: Bool
        var testDescription: String { "\(provider) at \(baseURL ?? "its default endpoint")" }
    }

    static let searchRoutes = [
        SearchRoute(provider: .openAI, baseURL: nil, searches: true),
        SearchRoute(provider: .anthropic, baseURL: nil, searches: true),
        SearchRoute(provider: .openRouter, baseURL: nil, searches: true),
        SearchRoute(provider: .openAI, baseURL: "https://gateway.example/v1", searches: false),
        SearchRoute(provider: .anthropic, baseURL: "https://gateway.example/anthropic", searches: false),
        SearchRoute(provider: .gemini, baseURL: nil, searches: false),
        SearchRoute(provider: .openAICompatible, baseURL: nil, searches: false)
    ]

    /// Only a route that can actually run one is ever offered a tool.
    @Test(arguments: searchRoutes)
    func webSearchStaysOnTheVendorsOwnEndpoint(_ route: SearchRoute) {
        let connection = AIConnection(provider: route.provider, baseURL: route.baseURL, models: ["m"])
        #expect(connection.capabilities(for: "m").webSearch == route.searches)
    }

    @Test func anthropicsSearchRidesBesideTheClientToolsAsItsServerTool() throws {
        let tool = AITool(name: "files__read", description: "Read", parameters: .object([:]), origin: "Files")
        let body = AIRequestBody.make(
            AIRequest(messages: [AIMessage(role: .user, text: "news")], webSearch: true, tools: [tool]),
            configuration: ToolsFixtures.anthropicDefault)
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.map { $0["name"] as? String } == [tool.name, "web_search"])
        #expect(tools.last?["type"] as? String == "web_search_20250305")
    }

    @Test func searchOffAddsNoTool() {
        let body = AIRequestBody.make(
            AIRequest(messages: [AIMessage(role: .user, text: "news")]),
            configuration: ToolsFixtures.anthropicDefault)
        #expect(body["tools"] == nil)
    }

    @Test func anthropicSearchesReportTheirQueryAndCiteTheirSourcesOnce() throws {
        let cite = #"{"type":"citations_delta","citation":{"url":"https://swift.org/a_(b)"}}"#
        let payloads = [
            #"{"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","name":"web_search"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\":\"swift "}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"6\"}"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","content":[]}}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":2,"delta":"# + cite + "}",
            #"{"type":"content_block_delta","index":2,"delta":"# + cite + "}",
            #"{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Swift 6 shipped."}}"#,
            #"{"type":"content_block_stop","index":2}"#,
            #"{"type":"message_stop"}"#
        ]
        var decoder = AIStreamDecoder(shape: .anthropic)
        let events = try decoder.feed(Data(payloads.map { "data: \($0)\n\n" }.joined().utf8))
        let link = " ([swift.org](https://swift.org/a_%28b%29))"
        #expect(
            events == [
                .searching(nil), .searched("swift 6"), .text("Swift 6 shipped."), .text(link), .finished
            ])
        #expect(
            ChatReferences.extract(from: "Swift 6 shipped." + link).map(\.url.absoluteString)
                == ["https://swift.org/a_%28b%29"],
            "the inlined citation is a source the transcript reads")
        let reachesTheToolLoop = events.contains {
            if case .toolCallRequested = $0 { true } else { false }
        }
        #expect(!reachesTheToolLoop, "a server tool never reaches Tinycast's own tool loop")
    }

    // MARK: Capabilities

    @Test func bothHTTPShapesSpeakToolCallingNatively() {
        #expect(AIConnection(provider: .anthropic, models: ["claude"]).capabilities(for: "claude").tools)
    }

    @Test func routesThatCannotRunAToolAreOfferedNone() {
        #expect(!AIModelCapabilities.appleIntelligence.tools, "the on-device model reaches nothing")
        #expect(!AIModelCapabilities.chatGPT.tools, "the hosted ChatGPT route declines tools by design")
        #expect(!AIModelCapabilities.none.tools, "an unconfigured route offers nothing either")
    }

    @Test func theTwoCLIRoutesAreOfferedServersTheirOwnClientRuns() {
        #expect(AIModelCapabilities.codex.tools)
        #expect(AIModelCapabilities.claudeCommand.tools)
    }

    @Test(arguments: [
        AIModelSelection.codex(model: "gpt", effort: nil), .claude(model: "sonnet", effort: nil)
    ])
    func theCLIRoutesRunTheirOwnTools(_ selection: AIModelSelection) {
        #expect(selection.runsItsOwnTools, "Tinycast never wraps these in its own loop")
    }

    @Test(arguments: [
        AIModelSelection.grok(model: "grok", effort: nil), .cursor(model: "auto", effort: nil),
        .openCode(model: "m", effort: nil), .appleIntelligence,
        .api(connection: UUID(), model: "m", effort: nil)
    ])
    func everyOtherRouteRunsTinycastsLoopOrHasNothingToCall(_ selection: AIModelSelection) {
        #expect(!selection.runsItsOwnTools)
    }

    @Test func aRequestCarriesNoToolsUnlessACallerPutThemThere() {
        #expect(AIRequest(messages: []).tools.isEmpty)
    }

    // MARK: Encoding turns

    /// Every provider 400s on a call without its result, or a result without its call.
    @Test func openAIWrapsToolsAsFunctionsAndAddressesEachResultToItsCall() throws {
        let body = AIRequestBody.make(
            ToolsFixtures.toolTurn,
            configuration: AIHTTPConfiguration(
                provider: .openAICompatible, baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-5"))
        let catalog = try #require((body["tools"] as? [[String: Any]])?.first)
        #expect(catalog["type"] as? String == "function", "OpenAI takes a tool wrapped as a function")
        #expect(
            (catalog["function"] as? [String: Any])?["parameters"] is [String: Any],
            "the server's own schema is handed through as the parameters, unrewritten")
        let messages = try #require(body["messages"] as? [[String: Any]])
        let assistant = try #require(messages.first { $0["tool_calls"] != nil })
        #expect(
            (assistant["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == "c1",
            "the assistant turn keeps the id its result has to quote")
        let results = messages.filter { $0["role"] as? String == "tool" }
        #expect(results.count == 2, "each result is its own tool turn")
        #expect(results.first?["tool_call_id"] as? String == "c1", "addressed by the call it answers")
    }

    @Test func anthropicTakesCallsAsBlocksAndARunOfResultsAsOneUserTurn() throws {
        let body = AIRequestBody.make(
            ToolsFixtures.toolTurn,
            configuration: AIHTTPConfiguration(
                provider: .anthropic, baseURL: URL(string: "https://api.anthropic.com")!, model: "claude"))
        let tool = try #require((body["tools"] as? [[String: Any]])?.first)
        #expect(tool["input_schema"] != nil, "Anthropic names the same schema input_schema")
        #expect(tool["type"] == nil, "and takes no wrapper")
        let messages = try #require(body["messages"] as? [[String: Any]])
        let assistant = try #require(messages.first { $0["role"] as? String == "assistant" })
        let use = try #require((assistant["content"] as? [[String: Any]])?.first)
        #expect(use["type"] as? String == "tool_use", "a call is a content block, not a field")
        #expect(
            (use["input"] as? [String: Any])?["path"] as? String == "/tmp",
            "its arguments are parsed back into the object Anthropic expects")
        let last = try #require(messages.last)
        #expect(last["role"] as? String == "user", "Anthropic takes results as a user turn")
        let results = try #require(last["content"] as? [[String: Any]])
        #expect(results.count == 2, "a run of them arrives as one turn, because two would be rejected")
        #expect(
            results.last?["is_error"] as? Bool == true,
            "a tool's own failure stays marked so the model can work around it")
    }

    @Test func aTurnWithNoToolsSendsNoToolsKey() {
        let body = AIRequestBody.make(
            AIRequest(messages: [AIMessage(role: .user, text: "hi")]),
            configuration: AIHTTPConfiguration(
                provider: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-5"))
        #expect(body["tools"] == nil)
    }

    @Test func openRouterReceivesTheReasoningEffortItsCatalogOffered() {
        let body = AIRequestBody.make(
            AIRequest(messages: [AIMessage(role: .user, text: "hi")]),
            configuration: AIHTTPConfiguration(
                provider: .openRouter, baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                model: "openai/gpt-5", effort: "low"))
        #expect((body["reasoning"] as? [String: String])?["effort"] == "low")
    }
}

private enum ToolsFixtures {
    static let anthropicDefault = AIHTTPConfiguration(
        provider: .anthropic, baseURL: URL(string: AIProviderKind.anthropic.defaultBaseURL)!, model: "claude")

    /// A call, its result and a failed result for a call the turn never made.
    static let toolTurn = AIRequest(
        messages: [
            AIMessage(role: .user, text: "read it"),
            AIMessage(
                role: .assistant, text: "",
                toolCalls: [AIToolCall(id: "c1", name: "fs__read", arguments: #"{"path":"/tmp"}"#)]),
            AIMessage(
                role: .tool, text: "", toolResult: AIToolResult(callID: "c1", content: "hi", isError: false)),
            AIMessage(
                role: .tool, text: "", toolResult: AIToolResult(callID: "c2", content: "no", isError: true))
        ],
        tools: [
            AITool(
                name: "fs__read", description: "Reads a file.",
                parameters: .object(["type": .string("object")]), origin: "Files", title: "read")
        ])
}
