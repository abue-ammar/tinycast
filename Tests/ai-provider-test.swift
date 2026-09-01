import Foundation

@main
@MainActor
struct AIProviderTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        providerPresetsResolveEndpoints()
        modelCatalogBuildsProviderRequests()
        modelCatalogDecodesProviderResponses()
        modelCatalogSearchesWithoutRenderingEverything()
        endpointPolicyRejectsUnsafeRemoteURLs()
        storedKeysDoNotFollowARetargetedConnection()
        sseFramesSurviveSplits()
        openAIAndAnthropicStreamsDecode()
        capturedStreamsDecodeHoweverTheyArrive()
        brokenStreamsFailLoudly()
        brandsResolveFromModelIDs()
        codexProtocolFramesRoundTrip()
        settingsPersistAndRepairSelections()
        subscriptionSelectionsReconcile()
        onDeviceSelectionsRoundTripAndLead()
        conversationSettingsPersistAndDecide()
        toolCatalogsAndTurnsEncodePerProvider()
        toolArgumentsSurviveArrivingInFragments()
        toolCapabilitiesFollowTheRoute()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// Both providers stream a call's arguments in pieces; a half-parsed call would be uncallable.
    static func toolArgumentsSurviveArrivingInFragments() {
        var openAI = AIStreamDecoder(shape: .openAICompatible)
        let openAIData = Data(
            """
            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1",\
            "function":{"name":"fs__read","arguments":"{\\"pa"}}]}}]}

            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"th\\":\\"/tmp\\"}"}}]}}]}

            data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

            data: [DONE]

            """.utf8)
        var events = (try? openAI.feed(openAIData)) ?? []
        events += (try? openAI.finish()) ?? []
        expect(
            events.contains(
                .toolCallRequested(
                    AIToolCall(id: "call_1", name: "fs__read", arguments: #"{"path":"/tmp"}"#))),
            "OpenAI fragments reassemble into one whole call before it leaves the decoder")
        expect(events.last == .finished, "and the stream still terminates")

        var anthropic = AIStreamDecoder(shape: .anthropic)
        let anthropicData = Data(
            """
            data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"fs__read"}}

            data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"path"}}

            data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\\":\\"/tmp\\"}"}}

            data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}

            """.utf8)
        var anthropicEvents = (try? anthropic.feed(anthropicData)) ?? []
        anthropicEvents += (try? anthropic.finish()) ?? []
        expect(
            anthropicEvents.contains(
                .toolCallRequested(
                    AIToolCall(id: "toolu_1", name: "fs__read", arguments: #"{"path":"/tmp"}"#))),
            "an Anthropic tool_use block reassembles the same way")
        expect(
            !anthropicEvents.contains(.finished),
            "a tool turn ends without message_stop, so the loop decides whether the turn is over")

        var plain = AIStreamDecoder(shape: .openAICompatible)
        let none = (try? plain.feed(Data("data: [DONE]\n\n".utf8))) ?? []
        expect(
            none == [.finished],
            "a turn that called nothing emits no tool event at all")
    }

    /// Only a route that can actually run one is ever offered a tool.
    static func toolCapabilitiesFollowTheRoute() {
        let connection = AIConnection(provider: .anthropic, models: ["claude"])
        expect(
            connection.capabilities(for: "claude").tools,
            "both HTTP shapes speak tool calling natively")
        expect(
            !AIModelCapabilities.appleIntelligence.tools,
            "the on-device model reaches nothing, so it is offered nothing to reach with")
        expect(
            !AIModelCapabilities.chatGPT.tools,
            "and the Codex route declines tools by design, so it is never handed any")
        expect(!AIModelCapabilities.none.tools, "an unconfigured route offers nothing either")

        expect(
            AIRequest(messages: []).tools.isEmpty,
            "a request carries no tools unless a caller put them there")
    }

    /// Every provider 400s on a call without its result, or a result without its call.
    static func toolCatalogsAndTurnsEncodePerProvider() {
        let tool = AITool(
            name: "fs__read", description: "Reads a file.",
            parameters: .object(["type": .string("object")]), origin: "Files", title: "read")
        let call = AIToolCall(id: "c1", name: "fs__read", arguments: #"{"path":"/tmp"}"#)
        let turn = AIRequest(
            messages: [
                AIMessage(role: .user, text: "read it"),
                AIMessage(role: .assistant, text: "", toolCalls: [call]),
                AIMessage(
                    role: .tool, text: "",
                    toolResult: AIToolResult(callID: "c1", content: "hi", isError: false)),
                AIMessage(
                    role: .tool, text: "",
                    toolResult: AIToolResult(callID: "c2", content: "no", isError: true))
            ],
            tools: [tool])

        let openAI = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(
                provider: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-5"))
        let catalog = (openAI["tools"] as? [[String: Any]])?.first
        expect(
            catalog?["type"] as? String == "function",
            "OpenAI takes a tool wrapped as a function")
        expect(
            (catalog?["function"] as? [String: Any])?["parameters"] is [String: Any],
            "and the server's own schema is handed through as the parameters, unrewritten")
        let openAIMessages = openAI["messages"] as? [[String: Any]] ?? []
        let assistant = openAIMessages.first { $0["tool_calls"] != nil }
        expect(
            ((assistant?["tool_calls"] as? [[String: Any]])?.first?["id"] as? String) == "c1",
            "the assistant turn keeps the id its result has to quote")
        let results = openAIMessages.filter { $0["role"] as? String == "tool" }
        expect(results.count == 2, "each result is its own tool turn")
        expect(
            results.first?["tool_call_id"] as? String == "c1",
            "addressed by the call it answers")

        let anthropic = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(
                provider: .anthropic, baseURL: URL(string: "https://api.anthropic.com")!,
                model: "claude"))
        let anthropicTool = (anthropic["tools"] as? [[String: Any]])?.first
        expect(
            anthropicTool?["input_schema"] != nil && anthropicTool?["type"] == nil,
            "Anthropic names the same schema input_schema and takes no wrapper")
        let anthropicMessages = anthropic["messages"] as? [[String: Any]] ?? []
        let use =
            (anthropicMessages.first { $0["role"] as? String == "assistant" }?["content"]
            as? [[String: Any]])?.first
        expect(use?["type"] as? String == "tool_use", "a call is a content block, not a field")
        expect(
            (use?["input"] as? [String: Any])?["path"] as? String == "/tmp",
            "and its arguments are parsed back into the object Anthropic expects")
        let resultBlocks =
            anthropicMessages.last?["content"] as? [[String: Any]] ?? []
        expect(
            anthropicMessages.last?["role"] as? String == "user",
            "Anthropic takes results as a user turn")
        expect(
            resultBlocks.count == 2,
            "and a run of them arrives as one turn, because two would be rejected")
        expect(
            resultBlocks.last?["is_error"] as? Bool == true,
            "a tool's own failure stays marked so the model can work around it")

        let plain = AIRequestBody.make(
            AIRequest(messages: [AIMessage(role: .user, text: "hi")]),
            configuration: AIHTTPConfiguration(
                provider: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-5"))
        expect(plain["tools"] == nil, "a turn with no tools sends no tools key at all")
    }

    static func providerPresetsResolveEndpoints() {
        let expected: [(AIProviderKind, String)] = [
            (.openAI, "https://api.openai.com/v1/chat/completions"),
            (.anthropic, "https://api.anthropic.com/v1/messages"),
            (.gemini, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"),
            (.openRouter, "https://openrouter.ai/api/v1/chat/completions"),
            (.openAICompatible, "https://api.openai.com/v1/chat/completions")
        ]
        for (provider, endpoint) in expected {
            let configuration = AIHTTPConfiguration(
                provider: provider,
                baseURL: URL(string: provider.defaultBaseURL)!,
                model: "model")
            expect(
                configuration.endpointURL.absoluteString == endpoint,
                "\(provider.title) resolves its documented streaming endpoint")
        }
        let explicit = AIHTTPConfiguration(
            provider: .openAICompatible,
            baseURL: URL(string: "https://example.com/chat/completions")!,
            model: "model")
        expect(
            explicit.endpointURL.absoluteString == "https://example.com/chat/completions",
            "an explicit completion endpoint is not appended twice")
    }

    static func modelCatalogBuildsProviderRequests() {
        let expected: [(AIProviderKind, String)] = [
            (.openAI, "https://api.openai.com/v1/models"),
            (.anthropic, "https://api.anthropic.com/v1/models?limit=1000"),
            (.gemini, "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000"),
            (.openRouter, "https://openrouter.ai/api/v1/models/user"),
            (.openAICompatible, "https://api.openai.com/v1/models")
        ]
        for (provider, endpoint) in expected {
            let query = try? AIModelDiscovery.query(
                provider: provider, baseURL: URL(string: provider.defaultBaseURL)!,
                apiKey: "secret", appTitle: "Tinycast")
            expect(
                query?.request.url?.absoluteString == endpoint,
                "\(provider.title) resolves its model catalog endpoint")
        }

        let anthropic = try? AIModelDiscovery.query(
            provider: .anthropic, baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "secret", appTitle: "Tinycast"
        ).request
        expect(
            anthropic?.value(forHTTPHeaderField: "x-api-key") == "secret",
            "Anthropic model discovery uses x-api-key authentication")
        let gemini = try? AIModelDiscovery.query(
            provider: .gemini, baseURL: URL(string: AIProviderKind.gemini.defaultBaseURL)!,
            apiKey: "secret", appTitle: "Tinycast"
        ).request
        expect(
            gemini?.value(forHTTPHeaderField: "x-goog-api-key") == "secret",
            "Gemini model discovery uses native API-key authentication")
        let openAI = try? AIModelDiscovery.query(
            provider: .openAI, baseURL: URL(string: AIProviderKind.openAI.defaultBaseURL)!,
            apiKey: "secret", appTitle: "Tinycast"
        ).request
        expect(
            openAI?.value(forHTTPHeaderField: "Authorization") == "Bearer secret",
            "OpenAI-compatible discovery uses bearer authentication")
        let local = try? AIModelDiscovery.query(
            provider: .openAICompatible, baseURL: URL(string: "http://localhost:11434/")!,
            apiKey: "", appTitle: "Tinycast"
        ).request
        expect(
            local?.url?.absoluteString == "http://localhost:11434/models",
            "a root endpoint appends one model path separator")
    }

    static func modelCatalogDecodesProviderResponses() {
        let openAI = Data(
            """
            {"data":[
                {"id":"model-a"},
                {"id":"model-b","name":"Model B",
                 "architecture":{"input_modalities":["text","image"]}},
                {"id":"model-a"}
            ]}
            """.utf8)
        let openAIModels = try? AIModelDiscovery.decode(openAI, shape: .openAI)
        expect(
            openAIModels == [
                .init(id: "model-a", name: "model-a"),
                .init(id: "model-b", name: "Model B", inputModalities: ["text", "image"])
            ],
            "OpenAI-compatible model lists are named and deduplicated")
        expect(
            openAIModels?.map(\.acceptsImages) == [nil, true],
            "only a catalog that lists modalities says whether a model takes images")

        let router = AIConnection(
            provider: .openRouter, models: ["model-a", "model-b"], visionModels: ["model-b"])
        expect(
            !router.capabilities(for: "model-a").images
                && router.capabilities(for: "model-b").images
                && router.capabilities(for: "model-a").webSearch,
            "OpenRouter gates images by the catalog and searches for every model")
        let direct = AIConnection(provider: .openAI, models: ["model-a"])
        expect(
            direct.capabilities(for: "model-a").images
                && !direct.capabilities(for: "model-a").webSearch,
            "a vendor API takes images and has no search switch")

        let gemini = Data(
            """
            {"models":[
                {"name":"models/gemini-chat","displayName":"Gemini Chat",\
                 "supportedGenerationMethods":["generateContent"]},
                {"name":"models/gemini-embed","displayName":"Gemini Embed",\
                 "supportedGenerationMethods":["embedContent"]}
            ]}
            """.utf8)
        let geminiModels = try? AIModelDiscovery.decode(gemini, shape: .gemini)
        expect(
            geminiModels == [.init(id: "gemini-chat", name: "Gemini Chat")],
            "Gemini discovery keeps generation models and strips the resource prefix")
    }

    static func modelCatalogSearchesWithoutRenderingEverything() {
        let models = [
            AIModelDiscovery.Model(id: "openai/gpt-small", name: "GPT Small"),
            AIModelDiscovery.Model(id: "anthropic/claude", name: "Claude"),
            AIModelDiscovery.Model(id: "openai/gpt-large", name: "GPT Large"),
            AIModelDiscovery.Model(id: "google/gemini", name: "Gemini")
        ]
        expect(
            AIModelDiscovery.search(models, query: "").isEmpty,
            "an empty search never renders the complete provider catalog")
        expect(
            AIModelDiscovery.search(models, query: "openai").map(\.id)
                == ["openai/gpt-small", "openai/gpt-large"],
            "a provider name finds its models in provider order")
        expect(
            AIModelDiscovery.search(models, query: "GPT Large").first?.id
                == "openai/gpt-large",
            "an exact display-name match ranks first")
        expect(
            AIModelDiscovery.search(
                models, query: "gpt", excluding: ["openai/gpt-small"], limit: 1
            ).map(\.id) == ["openai/gpt-large"],
            "search excludes selected models and caps visible results")
    }

    static func endpointPolicyRejectsUnsafeRemoteURLs() {
        expect(
            (try? AIEndpointPolicy.validate("https://example.com/v1")) != nil,
            "remote HTTPS endpoints are accepted")
        expect(
            (try? AIEndpointPolicy.validate("http://localhost:11434/v1")) != nil,
            "local HTTP endpoints are accepted")
        expect(
            (try? AIEndpointPolicy.validate("http://127.0.0.1:1234/v1")) != nil,
            "IPv4 loopback endpoints are accepted")
        expect(
            (try? AIEndpointPolicy.validate("http://example.com/v1")) == nil,
            "remote plaintext endpoints are rejected")
        expect(
            (try? AIEndpointPolicy.validate("not a url")) == nil,
            "malformed endpoints are rejected")
        expect(
            (try? AIEndpointPolicy.validate("ftp://localhost/v1")) == nil,
            "a loopback host does not excuse a scheme the transport cannot speak")
        expect(
            (try? AIEndpointPolicy.validate("file:///etc/hosts")) == nil,
            "file URLs are not a provider")
    }

    static func storedKeysDoNotFollowARetargetedConnection() {
        var saved = AIConnection()
        saved.provider = .openAI
        saved.baseURL = "https://api.openai.com/v1"
        expect(
            AIEndpointPolicy.sameDestination(saved, saved),
            "an untouched connection still points where its key was issued")

        var switchedProvider = saved
        switchedProvider.provider = .anthropic
        expect(
            !AIEndpointPolicy.sameDestination(switchedProvider, saved),
            "a new provider is a new destination, so the OpenAI key must not go to Anthropic")

        var switchedURL = saved
        switchedURL.baseURL = "https://gateway.example.com/v1"
        expect(
            !AIEndpointPolicy.sameDestination(switchedURL, saved),
            "a retyped base URL is a new destination, whatever the provider preset still says")

        var renamed = saved
        renamed.name = "Work key"
        renamed.models = ["gpt-5.4-mini"]
        expect(
            AIEndpointPolicy.sameDestination(renamed, saved),
            "editing a label or the model list is not a retarget and keeps the saved key")
    }

    static func sseFramesSurviveSplits() {
        var parser = SSEParser()
        expect(parser.feed(Data("data: hel".utf8)).isEmpty, "a partial SSE frame waits")
        expect(
            parser.feed(Data("lo\n\ndata: world\r\n\r\n".utf8)) == ["hello", "world"],
            "split LF and CRLF frames are reassembled")
        expect(
            parser.feed(Data(": keepalive\n\ndata: final".utf8)).isEmpty,
            "comments are ignored and a final unterminated frame waits")
        expect(parser.finish() == ["final"], "finish flushes the final frame")
    }

    static func openAIAndAnthropicStreamsDecode() {
        var openAI = AIStreamDecoder(shape: .openAICompatible)
        let openAIData = Data(
            """
            data: {"choices":[{"delta":{"reasoning":"working"}}]}

            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2}}

            data: [DONE]

            """.utf8)
        var events = (try? openAI.feed(openAIData)) ?? []
        events += (try? openAI.finish()) ?? []
        expect(events.contains(.thinking), "reasoning is surfaced as state, not answer text")
        expect(events.contains(.text("Hello")), "OpenAI-compatible text is decoded")
        expect(
            events.contains(.usage(AIUsage(inputTokens: 3, outputTokens: 2))),
            "OpenAI-compatible usage is decoded")
        expect(events.last == .finished, "the OpenAI done marker terminates the stream")

        var anthropic = AIStreamDecoder(shape: .anthropic)
        let anthropicData = Data(
            """
            data: {"type":"message_start","message":{"usage":{"input_tokens":4}}}

            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}

            data: {"type":"message_delta","usage":{"output_tokens":1}}

            data: {"type":"message_stop"}

            """.utf8)
        var anthropicEvents = (try? anthropic.feed(anthropicData)) ?? []
        anthropicEvents += (try? anthropic.finish()) ?? []
        expect(anthropicEvents.contains(.text("Hi")), "Anthropic text is decoded")
        expect(
            anthropicEvents.contains(.usage(AIUsage(inputTokens: 4, outputTokens: 1))),
            "Anthropic usage accumulates across events")
        expect(anthropicEvents.last == .finished, "Anthropic message_stop terminates the stream")
    }

    /// Real OpenRouter captures, with the reasoning ones proving thought never leaks into text.
    static func capturedStreamsDecodeHoweverTheyArrive() {
        let captures: [(file: String, text: String?, reasons: Bool)] = [
            ("openrouter-plain", "1, 2, 3.", false),
            ("openrouter-gemma", nil, false),
            ("openrouter-nemotron-reasoning", nil, true),
            ("openrouter-cohere-reasoning", nil, true)
        ]
        for capture in captures {
            guard let data = FileManager.default.contents(atPath: "Tests/ai-fixtures/\(capture.file).txt")
            else {
                expect(false, "\(capture.file) fixture is readable")
                continue
            }
            let whole = decodeAll(data, slice: data.count)
            let sliced = decodeAll(data, slice: 7)
            expect(whole == sliced, "\(capture.file) decodes the same in 7-byte slices")
            let text = whole.compactMap { event -> String? in
                if case .text(let text) = event { return text }
                return nil
            }.joined()
            if let expected = capture.text {
                expect(text == expected, "\(capture.file) yields exactly its answer text")
            } else {
                expect(!text.isEmpty, "\(capture.file) yields answer text")
            }
            expect(
                whole.contains(.thinking) == capture.reasons,
                "\(capture.file) surfaces thinking only when the model reasoned")
            expect(whole.last == .finished, "\(capture.file) ends on the done marker")
            expect(
                whole.contains {
                    if case .usage(let usage) = $0 { return usage.totalTokens != nil } else { return false }
                },
                "\(capture.file) reports final usage")
        }
    }

    private static func decodeAll(_ data: Data, slice: Int) -> [AIStreamEvent] {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        var events: [AIStreamEvent] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + slice, data.count)
            events += (try? decoder.feed(data[offset..<end])) ?? []
            offset = end
        }
        events += (try? decoder.finish()) ?? []
        return events
    }

    static func brokenStreamsFailLoudly() {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        let failure = Data(
            """
            data: {"choices":[{"delta":{"content":"Par"}}]}

            data: {"error":{"message":"Provider returned error","code":502}}

            data: {"choices":[{"delta":{"content":"never"}}]}

            """.utf8)
        var events: [AIStreamEvent] = []
        var thrown: Error?
        do { events = try decoder.feed(failure) } catch { thrown = error }
        expect(
            thrown as? AIProviderError == .responseFailed("Provider returned error"),
            "a mid-stream error payload fails with the provider's message")
        expect(decoder.isTerminal, "a mid-stream error ends the stream")
        expect(events.isEmpty, "nothing after the error is decoded")

        var malformed = AIStreamDecoder(shape: .openAICompatible)
        let garbage = Data("data: {not json\n\n".utf8)
        expect(
            (try? malformed.feed(garbage)) == nil,
            "unparseable JSON is rejected rather than skipped")
        expect(malformed.isTerminal, "a malformed frame ends the stream")

        var anthropic = AIStreamDecoder(shape: .anthropic)
        let rejected = Data(
            "data: {\"type\":\"error\",\"error\":{\"type\":\"authentication_error\"}}\n\n".utf8)
        var anthropicError: Error?
        do { _ = try anthropic.feed(rejected) } catch { anthropicError = error }
        expect(
            anthropicError as? AIProviderError
                == .responseFailed("API key rejected — check it in Settings."),
            "an Anthropic error event names the cause without echoing the key")

        var silent = AIStreamDecoder(shape: .openAICompatible)
        let truncated = Data("data: {\"choices\":[{\"delta\":{\"content\":\"half\"}}]}\n\n".utf8)
        let partial = (try? silent.feed(truncated)) ?? []
        expect(partial == [.text("half")], "text before a cut-off is still delivered")
        expect(!silent.isTerminal, "a stream without a done marker stays open for the caller to fail")
    }

    static func brandsResolveFromModelIDs() {
        let expected: [(String, AIBrand?)] = [
            ("openai/gpt-oss-20b", .openAI), ("o4-mini", .openAI), ("o3", .openAI),
            ("anthropic/claude-sonnet-4", .claude), ("google/gemma-3-27b-it", .gemini),
            ("x-ai/grok-4", .x), ("deepseek/deepseek-r1", .deepSeek), ("qwen/qwq-32b", .qwen),
            ("mistralai/codestral-2501", .mistral), ("meta-llama/llama-3.3-70b", .meta),
            ("moonshotai/kimi-k2", .kimi), ("minimax/minimax-m1", .miniMax),
            ("perplexity/sonar-pro", .perplexity), ("z-ai/glm-4.5", .zai),
            ("openrouter/auto", .openRouter), ("cohere/command-r", nil), ("o10", nil)
        ]
        for (model, brand) in expected {
            expect(
                AIBrand.resolve(model: model) == brand, "\(model) resolves to \(String(describing: brand))")
        }
        expect(
            AIBrand.resolve(provider: .anthropic, model: "whatever") == .claude,
            "a vendor endpoint names its brand regardless of the model id")
        expect(
            AIBrand.resolve(provider: .openAICompatible, model: "deepseek-chat") == .deepSeek,
            "a compatible endpoint resolves the brand from the model id")
    }

    static func codexProtocolFramesRoundTrip() {
        let request = try? CodexAppServerProtocol.request(
            id: 7, method: "account/read", params: ["refreshToken": false])
        let requestObject = request.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        expect((requestObject?["id"] as? Int) == 7, "Codex requests keep numeric IDs")
        expect(
            requestObject?["method"] as? String == "account/read",
            "Codex requests keep their method")

        let response = Data("{\"id\":7,\"result\":{\"ok\":true}}".utf8)
        if case .response(let id, let result) = CodexAppServerProtocol.parse(response) {
            expect(id == 7, "Codex responses route to the pending request")
            expect(result["ok"]?.boolValue == true, "Codex response values preserve booleans")
        } else {
            expect(false, "a valid Codex response parses")
        }
    }

    static func conversationSettingsPersistAndDecide() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func decide(
            _ opensTo: AIOpensTo, _ after: AINewChatAfter, idle: TimeInterval?
        )
            -> AIConversationOpenPolicy.Decision
        {
            AIConversationOpenPolicy.decide(
                opensTo: opensTo, newAfter: after,
                lastActiveAt: idle.map { now.addingTimeInterval(-$0) }, now: now)
        }

        expect(
            decide(.newConversation, .never, idle: 0) == .startNew,
            "A New Conversation always starts fresh")
        expect(
            decide(.recent, .never, idle: 400 * 86_400) == .resume,
            "Never means no amount of idling starts a new chat")
        expect(decide(.recent, .fiveMinutes, idle: nil) == .startNew, "nothing to resume is new")
        expect(
            decide(.recent, .fiveMinutes, idle: 299) == .resume,
            "inside the window the conversation resumes")
        expect(
            decide(.recent, .fiveMinutes, idle: 301) == .startNew,
            "past the window the next summon starts fresh")
        expect(
            decide(.recent, .fiveMinutes, idle: 300) == .startNew,
            "the boundary itself starts fresh, so the window is exclusive at its end")
        // A backwards clock yields a negative interval; it must not strand a reader in a chat.
        expect(
            decide(.recent, .twoMinutes, idle: -3_600) == .resume,
            "a clock that moved backwards resumes rather than misreading the idle time")

        expect(
            AIRetention.allCases.allSatisfy { !$0.title.isEmpty },
            "every retention names itself")
        expect(
            AIRetention.week.cutoff(from: now) == now.addingTimeInterval(-7 * 86_400),
            "a week's cutoff is seven days back")
        expect(
            AINewChatAfter.allCases.filter { $0.rawValue == 0 }.isEmpty,
            "no timeout uses 0, which an unset key would swallow before the default applied")

        let suite = "AIProviderTests.conversations"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }

        let fresh = AISettingsStore(defaults: defaults)
        expect(fresh.retention == .forever, "retention defaults to Forever, so upgrading deletes nothing")
        expect(fresh.opensTo == .recent, "chat reopens on the recent conversation by default")
        expect(fresh.newChatAfter == .fiveMinutes, "the idle window defaults to five minutes")

        fresh.retention = .week
        fresh.opensTo = .newConversation
        fresh.newChatAfter = .never
        let reopened = AISettingsStore(defaults: defaults)
        expect(reopened.retention == .week, "retention persists")
        expect(reopened.opensTo == .newConversation, "the open policy persists")
        expect(reopened.newChatAfter == .never, "Never persists rather than reading as the default")
    }

    static func onDeviceSelectionsRoundTripAndLead() {
        let encoded = try? JSONEncoder().encode(AIModelSelection.appleIntelligence)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(AIModelSelection.self, from: $0) }
        expect(decoded == .appleIntelligence, "the on-device selection survives a round trip")
        expect(
            AIModelSelection.appleIntelligence.model == AppleIntelligence.modelID,
            "the on-device selection reports a stable model id")
        expect(
            AIModelSelection.appleIntelligence.source == .appleIntelligence,
            "the on-device selection is its own source")
        expect(
            AIModelSelection.appleIntelligence.isOnDevice
                && !AIModelSelection.chatGPT(model: "gpt-5", effort: nil).isOnDevice,
            "only the on-device selection reads as on device")

        // Data written before this route existed decodes to nothing; there is no migration.
        let suite = "AIProviderTests.onDevice"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }

        let store = AISettingsStore(defaults: defaults, isAppleIntelligenceAvailable: { true })
        expect(store.defaultModel == nil, "a fresh store chooses nothing on its own")
        store.resolveDefaultModel()
        expect(
            store.defaultModel == .appleIntelligence,
            "the on-device route is what an unconfigured Mac resolves to")

        // A configured connection must not be displaced by resolution running a second time.
        let connectionID = UUID()
        store.save(AIConnection(id: connectionID, name: "Local", models: ["m"]))
        store.select(.api(connection: connectionID, model: "m"))
        store.resolveDefaultModel()
        expect(
            store.defaultModel == .api(connection: connectionID, model: "m"),
            "resolution never overrides a selection the reader made")

        // A removed connection falls forward to the route that is always configured.
        store.removeConnection(id: connectionID)
        expect(
            store.defaultModel == .appleIntelligence,
            "a removed connection falls forward to the on-device route")

        let without = AISettingsStore(defaults: defaults, isAppleIntelligenceAvailable: { false })
        without.resolveDefaultModel()
        expect(
            without.defaultModel == .appleIntelligence,
            "an unavailable model does not silently reroute a stored on-device selection")
    }

    static func settingsPersistAndRepairSelections() {
        let suite = "AIProviderTests.persistence"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }
        let firstID = UUID()
        let secondID = UUID()

        var first = AIConnection(
            id: firstID, name: "  Work  ", provider: .openRouter,
            models: [" model-a ", "model-a", "model-b"])
        first.baseURL = " https://openrouter.ai/api/v1 "
        let store = AISettingsStore(defaults: defaults)
        store.save(first)
        store.save(
            AIConnection(id: secondID, provider: .gemini, models: ["gemini-model"]))
        expect(store.connections.first?.name == "Work", "connection names are normalized")
        expect(
            store.connections.first?.models == ["model-a", "model-b"],
            "models are trimmed and deduplicated")
        expect(
            store.defaultModel == .api(connection: firstID, model: "model-a"),
            "the first saved model becomes the default")
        store.select(.api(connection: firstID, model: "model-b"))

        let reopened = AISettingsStore(defaults: defaults)
        expect(reopened.connections == store.connections, "connection metadata survives a restart")
        expect(reopened.defaultModel == store.defaultModel, "the default model survives a restart")
        reopened.removeConnection(id: firstID)
        expect(
            reopened.defaultModel == .api(connection: secondID, model: "gemini-model"),
            "removing the default connection falls forward to another API model")
    }

    static func subscriptionSelectionsReconcile() {
        let suite = "AIProviderTests.subscription"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }
        let store = AISettingsStore(defaults: defaults)
        let model = ChatGPTSubscription.Model(
            id: "gpt", name: "GPT",
            efforts: [
                .init(id: "low", detail: nil), .init(id: "high", detail: nil)
            ], defaultEffort: "high", isDefault: true)
        store.select(.chatGPT(model: "gpt", effort: "missing"))
        store.reconcile(chatGPTModels: [model], isSignedOut: false)
        expect(
            store.defaultModel == .chatGPT(model: "gpt", effort: "high"),
            "a removed reasoning tier falls back to the model default")
        store.reconcile(chatGPTModels: [], isSignedOut: true)
        expect(store.defaultModel == nil, "signing out clears an unusable subscription default")
    }
}

/// `removePersistentDomain` only empties the domain; cfprefsd still leaves the plist on disk.
private func discardSuite(_ name: String, _ defaults: UserDefaults) {
    defaults.removePersistentDomain(forName: name)
    UserDefaults.standard.removeSuite(named: name)
    CFPreferencesAppSynchronize(name as CFString)
    try? FileManager.default.removeItem(
        at: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(name).plist"))
}

/// A fixed suite name stops cfprefsd accumulating a plist per run.
private func isolatedDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
