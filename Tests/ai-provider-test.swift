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

    /// A wrong document shape must fail here rather than mid-conversation.
    static func requestBodiesCarryDocuments() {
        let pdf = AIDocument(
            data: Data("%PDF-1.4".utf8), mimeType: "application/pdf", name: "report.pdf")
        let image = AIImage(data: Data([0x89, 0x50]), mimeType: "image/png")
        let turn = AIRequest(
            messages: [
                AIMessage(role: .user, text: "summarise", images: [image], documents: [pdf])
            ])

        let anthropic = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(
                provider: .anthropic, baseURL: URL(string: "https://api.anthropic.com")!,
                model: "claude"))
        let blocks =
            (anthropic["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]] ?? []
        expect(
            blocks.map { $0["type"] as? String } == ["image", "document", "text"],
            "Anthropic takes image then document, with the text block last")
        let source =
            blocks.first { $0["type"] as? String == "document" }?["source"]
            as? [String: Any]
        expect(
            source?["type"] as? String == "base64"
                && source?["media_type"] as? String == "application/pdf",
            "as a base64 document source naming its media type")
        expect(
            (source?["data"] as? String)?.contains("\n") == false,
            "whose base64 carries no newlines")

        let openAI = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(
                provider: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt"))
        let parts =
            (openAI["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]] ?? []
        expect(
            parts.map { $0["type"] as? String } == ["text", "image_url", "file"],
            "OpenAI keeps its text part first and appends the file part")
        let file = parts.first { $0["type"] as? String == "file" }?["file"] as? [String: Any]
        expect(
            file?["filename"] as? String == "report.pdf",
            "the file part names the document")
        expect(
            (file?["file_data"] as? String)?.hasPrefix("data:application/pdf;base64,") == true,
            "and carries it as a data URL")

        // A turn that is only a document must not collapse to the plain-string fast path.
        let documentOnly = AIRequestBody.make(
            AIRequest(messages: [AIMessage(role: .user, text: "", documents: [pdf])]),
            configuration: AIHTTPConfiguration(
                provider: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt"))
        expect(
            ((documentOnly["messages"] as? [[String: Any]])?.first?["content"]
                as? [[String: Any]])?.count == 1,
            "a document-only turn still sends, as content parts")
    }

    static func main() {
        providerPresetsResolveEndpoints()
        modelCatalogBuildsProviderRequests()
        modelCatalogDecodesProviderResponses()
        modelCatalogSearchesWithoutRenderingEverything()
        endpointPolicyRejectsUnsafeRemoteURLs()
        storedKeysDoNotFollowARetargetedConnection()
        savingAConnectionDecidesItsKey()
        sseFramesSurviveSplits()
        openAIAndAnthropicStreamsDecode()
        capturedStreamsDecodeHoweverTheyArrive()
        brokenStreamsFailLoudly()
        brandsResolveFromModelIDs()
        requestBodiesCarryDocuments()
        codexProtocolFramesRoundTrip()
        installedCLIStreamsDecode()
        settingsPersistAndRepairSelections()
        installedModelLoadingPreferencePersists()
        subscriptionSelectionsReconcile()
        onDeviceSelectionsRoundTripAndLead()
        conversationSettingsPersistAndDecide()
        toolCatalogsAndTurnsEncodePerProvider()
        toolArgumentsSurviveArrivingInFragments()
        toolCapabilitiesFollowTheRoute()
        codexLaunchNamesServersAndKeepsSecretsOffArgv()
        codexLaunchHandsAServerItsOwnVariableNames()
        codexVariablesNeverCollide()
        claudeConfigurationCarriesServersAndRoutesToolNames()
        codexElicitationsAreOnlyToolCalls()
        claudeControlFramesAnswerOneTool()
        aGatewayOffersNoneAsItsReasoningEffort()

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
            "and the hosted ChatGPT route declines tools by design")
        expect(
            AIModelCapabilities.codex.tools && AIModelCapabilities.claudeCommand.tools,
            "the two CLI routes are offered servers, which their own client runs")
        expect(!AIModelCapabilities.none.tools, "an unconfigured route offers nothing either")
        expect(
            AIModelSelection.codex(model: "gpt", effort: nil).runsItsOwnTools
                && AIModelSelection.claude(model: "sonnet", effort: nil).runsItsOwnTools,
            "and they are the routes Tinycast never wraps in its own loop")
        expect(
            !AIModelSelection.grok(model: "grok", effort: nil).runsItsOwnTools
                && !AIModelSelection.cursor(model: "auto", effort: nil).runsItsOwnTools
                && !AIModelSelection.openCode(model: "m", effort: nil).runsItsOwnTools
                && !AIModelSelection.appleIntelligence.runsItsOwnTools
                && !AIModelSelection.api(connection: UUID(), model: "m", effort: nil)
                    .runsItsOwnTools,
            "every other route either runs Tinycast's loop or has nothing to call")

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

        let router = AIRequestBody.make(
            AIRequest(messages: [AIMessage(role: .user, text: "hi")]),
            configuration: AIHTTPConfiguration(
                provider: .openRouter, baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                model: "openai/gpt-5", effort: "low"))
        expect(
            (router["reasoning"] as? [String: String])?["effort"] == "low",
            "OpenRouter receives the reasoning effort its catalog offered")
    }

    /// A body that named the default would 400 on every endpoint without a thinking mode.
    static func aGatewayOffersNoneAsItsReasoningEffort() {
        let gateway = AIConnection(
            provider: .openAI, baseURL: "https://api.fusioncode.app/v1", models: ["m"])
        expect(
            gateway.reasoningOptions(for: "m")?.efforts == ["default", "none"],
            "a preset pointed away from its own API offers the one effort a gateway can honour")
        expect(
            gateway.reasoningOptions(for: "m")?.resolvedEffort(nil) == "default",
            "and reasoning stays on until the reader picks None")
        expect(
            AIConnection(provider: .openAI, models: ["m"]).reasoningOptions(for: "m") == nil,
            "a preset on its own API offers none, because a vendor rejects what it does not define")
        expect(
            AIConnection(provider: .anthropic, baseURL: "https://gateway.example", models: ["m"])
                .reasoningOptions(for: "m") == nil,
            "the Anthropic shape is out of scope whatever it points at")

        let catalogued = AIConnection(
            id: UUID(), provider: .openRouter, baseURL: "https://gateway.example", models: ["m"],
            reasoningOptions: ["m": .init(efforts: ["high", "low"], defaultEffort: "high")])
        expect(
            catalogued.reasoningOptions(for: "m")?.efforts == ["high", "low"],
            "a published catalog always wins over the synthesized switch")

        let turn = AIRequest(messages: [AIMessage(role: .user, text: "hi")])
        let url = URL(string: "https://api.fusioncode.app/v1")!
        let on = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(provider: .openAI, baseURL: url, model: "m"))
        expect(on["thinking"] == nil, "reasoning left alone sends no key at all")

        let off = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(
                provider: .openAI, baseURL: url, model: "m", effort: "none",
                disablesThinking: true))
        expect(
            (off["thinking"] as? [String: String])?["type"] == "disabled",
            "None asks the endpoint to answer directly")
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
                 "architecture":{"input_modalities":["text","image"]},
                 "reasoning":{"supported_efforts":["high","medium","low"],
                              "default_effort":"medium"}},
                {"id":"model-a"}
            ]}
            """.utf8)
        let openAIModels = try? AIModelDiscovery.decode(openAI, shape: .openAI)
        expect(
            openAIModels == [
                .init(id: "model-a", name: "model-a"),
                .init(
                    id: "model-b", name: "Model B", inputModalities: ["text", "image"],
                    reasoningOptions: .init(
                        efforts: ["high", "medium", "low"], defaultEffort: "medium"))
            ],
            "OpenAI-compatible model lists are named and deduplicated")
        expect(
            openAIModels?.map(\.acceptsImages) == [nil, true],
            "only a catalog that lists modalities says whether a model takes images")
        expect(
            openAIModels?.last?.reasoningOptions?.resolvedEffort(nil) == "medium",
            "OpenRouter reasoning metadata keeps the model's advertised default")

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

    static func savingAConnectionDecidesItsKey() {
        var remote = AIConnection()
        remote.provider = .openAI
        remote.baseURL = "https://api.openai.com/v1"
        var local = remote
        local.baseURL = "http://localhost:11434/v1"
        var moved = remote
        moved.baseURL = "https://gateway.example.com/v1"
        typealias Policy = AIConnectionKeyPolicy

        expect(
            Policy.resolve(enteredKey: "  sk-new \n", connection: remote, saved: nil, hasStoredKey: false)
                == .store("sk-new"),
            "a typed key is stored trimmed")
        expect(
            Policy.resolve(enteredKey: "sk-new", connection: moved, saved: remote, hasStoredKey: true)
                == .store("sk-new"),
            "a retarget that brings its own key replaces the old one")
        expect(
            Policy.resolve(enteredKey: " ", connection: moved, saved: remote, hasStoredKey: true)
                == .reject("Enter an API key for this endpoint — the saved key stays with the old one."),
            "a remote retarget without a key is refused, so the old key never reaches the new host")
        expect(
            Policy.resolve(enteredKey: "", connection: local, saved: remote, hasStoredKey: true)
                == .removeStored,
            "a retarget to loopback drops the key issued for the remote endpoint")
        expect(
            Policy.resolve(enteredKey: "", connection: remote, saved: nil, hasStoredKey: false)
                == .reject("Enter an API key for this remote provider."),
            "a new remote connection needs a key")
        expect(
            Policy.resolve(enteredKey: "", connection: local, saved: nil, hasStoredKey: false) == .keep,
            "a loopback endpoint saves without a key")
        expect(
            Policy.resolve(enteredKey: "", connection: remote, saved: remote, hasStoredKey: true) == .keep,
            "an unchanged endpoint keeps its saved key")
        expect(
            Policy.resolve(enteredKey: "", connection: moved, saved: remote, hasStoredKey: false)
                == .reject("Enter an API key for this remote provider."),
            "with no saved key there is nothing to retarget, only a missing key")
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
        expect(fresh.toolRounds == .twentyFive, "a reply's tool rounds default to 25")

        fresh.retention = .week
        fresh.opensTo = .newConversation
        fresh.newChatAfter = .never
        fresh.toolRounds = .fifty
        let reopened = AISettingsStore(defaults: defaults)
        expect(reopened.toolRounds == .fifty, "the tool round cap persists")
        reopened.toolRounds = .unlimited
        expect(
            AISettingsStore(defaults: defaults).toolRounds == .unlimited,
            "Unlimited persists rather than reading as the default")
        expect(AIToolRounds.unlimited.limit == nil, "and hands the loop no cap")
        expect(AIToolRounds.fifty.limit == 50, "while a step hands it its own number")
        defaults.set(7, forKey: AppSettingsKey.aiToolRounds.rawValue)
        expect(
            AISettingsStore(defaults: defaults).toolRounds == .twentyFive,
            "a stored cap no case carries reads as the default rather than an arbitrary number")
        defaults.set(0, forKey: AppSettingsKey.aiToolRounds.rawValue)
        expect(
            AISettingsStore(defaults: defaults).toolRounds == .twentyFive,
            "and so does a 0, which is neither a step nor Unlimited")
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
                && !AIModelSelection.codex(model: "gpt-5", effort: nil).isOnDevice,
            "only the on-device selection reads as on device")

        let legacy = Data(#"{"chatGPT":{"model":"gpt-5","effort":"high"}}"#.utf8)
        expect(
            (try? JSONDecoder().decode(AIModelSelection.self, from: legacy))
                == .codex(model: "gpt-5", effort: "high"),
            "the old ChatGPT selection migrates to the installed Codex route")

        let suite = "AIProviderTests.onDevice"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }

        let store = AISettingsStore(defaults: defaults, isAppleIntelligenceAvailable: { true })
        expect(
            store.defaultModel == .appleIntelligence,
            "the on-device route is the default on an unconfigured Mac")

        // A configured connection must not be displaced by resolution running a second time.
        let connectionID = UUID()
        store.save(AIConnection(id: connectionID, name: "Local", models: ["m"]))
        store.select(.api(connection: connectionID, model: "m", effort: nil))
        store.resolveDefaultModel()
        expect(
            store.defaultModel == .api(connection: connectionID, model: "m", effort: nil),
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
            models: [" model-a ", "model-a", "model-b"],
            reasoningOptions: [
                "model-b": .init(efforts: ["medium", "low"], defaultEffort: "medium")
            ])
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
            store.defaultModel == .api(connection: firstID, model: "model-a", effort: nil),
            "the first saved model becomes the default")
        store.select(.api(connection: firstID, model: "model-b", effort: "low"))

        let reopened = AISettingsStore(defaults: defaults)
        expect(reopened.connections == store.connections, "connection metadata survives a restart")
        expect(reopened.defaultModel == store.defaultModel, "the default model survives a restart")
        reopened.removeConnection(id: firstID)
        expect(
            reopened.defaultModel
                == .api(
                    connection: secondID, model: "gemini-model", effort: nil),
            "removing the default connection falls forward to another API model")
    }

    static func installedModelLoadingPreferencePersists() {
        let suite = "AIProviderTests.installedModelLoading"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }
        let store = AISettingsStore(defaults: defaults)
        expect(
            store.enabledInstalledProviders.isEmpty,
            "installed providers are disabled by default")
        store.setInstalledProviderEnabled(true, for: .claude)
        store.setInstalledProviderEnabled(false, for: .openCode)
        let reopened = AISettingsStore(defaults: defaults)
        expect(
            reopened.enabledInstalledProviders == [.claude],
            "an enabled provider survives a restart")
        expect(
            !reopened.enabledInstalledProviders.contains(.openCode),
            "a provider toggle survives a restart")
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
        store.select(.codex(model: "gpt", effort: "missing"))
        store.reconcile(codexModels: [model], isUnavailable: false)
        expect(
            store.defaultModel == .codex(model: "gpt", effort: "high"),
            "a removed reasoning tier falls back to the model default")
        store.reconcile(codexModels: [], isUnavailable: true)
        expect(store.defaultModel == nil, "signing out clears an unusable Codex default")

        store.select(.claude(model: "removed", effort: nil))
        store.reconcile(
            installed: .claude,
            models: [InstalledAIModel(id: "sonnet", name: "Claude Sonnet")],
            isUnavailable: false)
        expect(
            store.defaultModel == .claude(model: "sonnet", effort: nil),
            "an installed catalog replaces a model alias that disappeared")
        store.reconcile(installed: .claude, models: [], isUnavailable: true)
        expect(store.defaultModel == nil, "signing out clears an unusable Claude default")
    }

    static func installedCLIStreamsDecode() {
        let openCodeText = Data(
            #"{"type":"text","sessionID":"ses_1","part":{"text":"Hello"}}"#.utf8)
        expect(
            InstalledAIStreamDecoder.decode(openCodeText, kind: .openCode)
                == InstalledAIStreamFrame(events: [.text("Hello")], sessionID: "ses_1"),
            "OpenCode text and its cleanup session decode together")
        let openCodeFinish = Data(
            #"{"type":"step_finish","part":{"tokens":{"input":12,"output":4}}}"#.utf8)
        let openCodeFrame = InstalledAIStreamDecoder.decode(openCodeFinish, kind: .openCode)
        expect(
            openCodeFrame.events == [.usage(AIUsage(inputTokens: 12, outputTokens: 4))]
                && openCodeFrame.completed,
            "OpenCode completion reports usage and finishes")

        let claudeText = Data(
            #"{"type":"stream_event","event":{"delta":{"type":"text_delta","text":"Hi"}}}"#.utf8)
        expect(
            InstalledAIStreamDecoder.decode(claudeText, kind: .claude).events == [.text("Hi")],
            "Claude partial text decodes without replaying its full assistant message")
        let claudeFinish = Data(
            #"{"type":"result","is_error":false,"usage":{"input_tokens":8,"output_tokens":3}}"#.utf8)
        let claudeFrame = InstalledAIStreamDecoder.decode(claudeFinish, kind: .claude)
        expect(
            claudeFrame.events == [.usage(AIUsage(inputTokens: 8, outputTokens: 3))]
                && claudeFrame.completed,
            "Claude result usage ends the stream")

        let cursorDelta = Data(
            #"{"type":"assistant","timestamp_ms":1,"message":{"content":[{"type":"text","text":"Hi"}]}}"#
                .utf8)
        expect(
            InstalledAIStreamDecoder.decode(cursorDelta, kind: .cursor).events == [.text("Hi")],
            "Cursor live deltas decode as text")
        let cursorFlush = Data(
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hi"}]}}"#.utf8)
        expect(
            InstalledAIStreamDecoder.decode(cursorFlush, kind: .cursor).events.isEmpty,
            "Cursor buffered flushes without timestamp_ms are ignored")
        let cursorDone = Data(#"{"type":"result","subtype":"success","result":"Hi"}"#.utf8)
        expect(
            InstalledAIStreamDecoder.decode(cursorDone, kind: .cursor).completed,
            "Cursor result ends the stream")
        let cursorSession = Data(
            #"{"type":"system","subtype":"init","session_id":"ses_cursor"}"#.utf8)
        expect(
            InstalledAIStreamDecoder.decode(cursorSession, kind: .cursor).sessionID == "ses_cursor",
            "Cursor system init carries the session id for cleanup")
        let grokText = Data(
            #"{"type":"stream_event","session_id":"ses_g","event":{"delta":{"type":"text_delta","text":"Yo"}}}"#
                .utf8)
        let grokTextFrame = InstalledAIStreamDecoder.decode(grokText, kind: .grok)
        expect(
            grokTextFrame.events == [.text("Yo")] && grokTextFrame.sessionID == "ses_g",
            "Grok partial text reuses the Claude stream shape and keeps the session id")
        let grokFinish = Data(
            #"{"type":"result","is_error":false,"session_id":"ses_g","usage":{"input_tokens":5,"output_tokens":1}}"#
                .utf8)
        let grokFrame = InstalledAIStreamDecoder.decode(grokFinish, kind: .grok)
        expect(
            grokFrame.events == [.usage(AIUsage(inputTokens: 5, outputTokens: 1))]
                && grokFrame.completed && grokFrame.sessionID == "ses_g",
            "Grok result usage ends the stream and names the session to delete")
    }

    /// A secret on argv is in `ps`, and a key Codex does not know is a server that never starts.
    static func codexLaunchNamesServersAndKeepsSecretsOffArgv() {
        let stdio = AIToolServer(
            handle: "files", title: "Files",
            transport: .command(
                path: "/usr/local/bin/node", arguments: ["server.js", "--root=/tmp"],
                environment: ["API_KEY": "s3cret"]))
        let oauth = AIToolServer(
            handle: "linear", title: "Linear",
            transport: .url(
                "https://mcp.linear.app/mcp", headerName: "Authorization",
                headerValue: "Bearer tok-123"))
        let custom = AIToolServer(
            handle: "notes", title: "Notes",
            transport: .url(
                "https://notes.example/mcp", headerName: "X-Api-Key", headerValue: "k1"))

        let arguments = CodexMCPLaunch.arguments(
            servers: [stdio, oauth, custom], disabling: ["computer-use", "files"])
        expect(
            arguments.contains("mcp_servers.computer-use.enabled=false")
                && arguments.contains("mcp_servers.files.enabled=false"),
            "every one of the reader's own servers is disabled by name, one named like ours too")
        expect(
            arguments.contains("mcp_servers.tinycast-files.enabled=true")
                && !arguments.contains { $0.hasPrefix("mcp_servers.files.") && !$0.hasSuffix("=false") },
            "since Tinycast's go by names of their own, which no table of the reader's merges into")
        expect(
            arguments.contains(#"mcp_servers.tinycast-files.command="/bin/sh""#)
                && arguments.contains(Self.renamingArguments),
            "a local server with variables arrives through a shell that renames them, then runs it")
        expect(
            arguments.contains(Self.forwardedVariables),
            "whose environment is named rather than carried: Codex forwards only what is listed")
        expect(
            arguments.contains(#"mcp_servers.tinycast-linear.bearer_token_env_var="TC_MCP_1_0""#),
            "an OAuth endpoint lends its token through the variable Codex reads it from")
        expect(
            arguments.contains(Self.headerMapOverride),
            "and another header name goes through the map that takes one")
        expect(
            !arguments.contains {
                $0.contains("s3cret") || $0.contains("tok-123") || $0.contains("k1")
            },
            "no value reaches argv, where `ps` would show it")

        let environment = CodexMCPLaunch.environment(servers: [stdio, oauth, custom]) ?? [:]
        expect(
            environment["TC_MCP_0_0"] == "s3cret" && environment["TC_MCP_2_0"] == "k1",
            "the values ride the child's environment instead")
        expect(
            environment["TC_MCP_1_0"] == "tok-123",
            "and a bearer token loses its prefix, because Codex composes that itself")

        let open = AIToolServer(
            handle: "open", title: "Open",
            transport: .url(
                "https://open.example/mcp", headerName: "Authorization", headerValue: ""))
        let openArguments = CodexMCPLaunch.arguments(servers: [open], disabling: [])
        expect(
            openArguments.contains(#"mcp_servers.tinycast-open.url="https://open.example/mcp""#)
                && !openArguments.contains { $0.contains("bearer_token") || $0.contains("headers") }
                && CodexMCPLaunch.environment(servers: [open]) == [:],
            "a server that needs no credential goes to Codex with no header and no variable")

        let quoted = CodexMCPLaunch.arguments(
            servers: [
                AIToolServer(
                    handle: "odd", title: "Odd",
                    transport: .command(
                        path: #"/tmp/we"ird\bin"#, arguments: [], environment: [:]))
            ], disabling: [])
        expect(
            quoted.contains(#"mcp_servers.tinycast-odd.command="/tmp/we\"ird\\bin""#),
            "a path with a quote in it is still one TOML string")

        expect(
            CodexMCPLaunch.quoted("a\r\nb\tc\u{1}\u{7F}é\"\\")
                == #""a\u000D\u000Ab\u0009c\u0001\u007Fé\"\\""#,
            "CRLF, every other control character and DEL become \\u escapes TOML accepts")
        let crlf = CodexMCPLaunch.arguments(
            servers: [
                AIToolServer(
                    handle: "lines", title: "Lines",
                    transport: .command(path: "/bin/echo", arguments: ["a\r\nb"], environment: [:]))
            ], disabling: [])
        expect(
            crlf.contains(#"mcp_servers.tinycast-lines.args=["a\u000D\u000Ab"]"#),
            "so an argument carrying a Windows line ending still leaves Codex's config loadable")

        expect(
            CodexMCPLaunch.handle(ofServer: "tinycast-files") == "files"
                && CodexMCPLaunch.handle(ofServer: "files") == nil
                && CodexMCPLaunch.handle(ofServer: "tinycast-") == nil,
            "a name Codex reports maps back to a handle only when it is one of Tinycast's")
        expect(
            CodexMCPLaunch.takenName(servers: [stdio], foreignNames: ["tinycast-files"])
                == "tinycast-files"
                && CodexMCPLaunch.takenName(servers: [stdio], foreignNames: ["files"]) == nil,
            "and a reader's server already named like an armed one of ours is caught before launch")

        expect(
            CodexMCPLaunch.foreignNames(listing: #"[{"name":"a","enabled":true},{"name":"b c"}]"#)
                == ["a", "b c"],
            "the reader's servers are every name `codex mcp list --json` reports")
        expect(
            CodexMCPLaunch.foreignNames(listing: "warning: not json") == nil
                && CodexMCPLaunch.foreignNames(listing: #"{"name":"a"}"#) == nil
                && CodexMCPLaunch.foreignNames(listing: #"[{"name":"a"},{"enabled":true}]"#) == nil,
            "and output that is not that list reads as unknown, never as an empty one")
        expect(
            CodexMCPLaunch.unaddressableName(["ok", "日本", "has space", "has.dot"]) == "has.dot"
                && CodexMCPLaunch.unaddressableName(["a=b"]) == "a=b"
                && CodexMCPLaunch.unaddressableName(["ok", "日本", "has space"]) == nil,
            "only a dot or an equals sign keeps `-c` from naming a server; spaces and scripts do not")
    }

    /// Only running the launch proves a server gets its own names; `printenv` stands in for it.
    static func codexLaunchHandsAServerItsOwnVariableNames() {
        let derived = ["TC_MCP_0_0": "s3cret"]
        let launch = CodexMCPLaunch.command(
            path: "/usr/bin/printenv", arguments: ["API_KEY"],
            environment: ["API_KEY": "s3cret"], server: 0)
        expect(
            run(launch, environment: derived) == "s3cret\n",
            "the server reads its value under its own name, which Codex alone cannot give it")
        let leftover = CodexMCPLaunch.command(
            path: "/usr/bin/printenv", arguments: ["TC_MCP_0_0"],
            environment: ["API_KEY": "s3cret"], server: 0)
        expect(
            run(leftover, environment: derived) == "",
            "and the derived name is gone, so the value does not reach it twice")

        let odd = AIToolServer(
            handle: "odd", title: "Odd",
            transport: .command(
                path: "/usr/bin/true", arguments: [], environment: ["NOT-A-NAME": "hidden"]))
        let oddArguments = CodexMCPLaunch.arguments(servers: [odd], disabling: [])
        expect(
            oddArguments.contains(#"mcp_servers.tinycast-odd.command="/usr/bin/true""#)
                && oddArguments.contains("mcp_servers.tinycast-odd." + "env" + "_vars=[]"),
            "a name the shell cannot export is not forwarded, and the server launches directly")
        expect(
            CodexMCPLaunch.environment(servers: [odd]) == [:],
            "so its value never enters the app-server's environment under a name nobody reads")
    }

    /// Two spellings of handle and key must never meet in one variable, or a secret changes hands.
    static func codexVariablesNeverCollide() {
        func local(_ handle: String, _ environment: [String: String]) -> AIToolServer {
            AIToolServer(
                handle: handle, title: handle,
                transport: .command(
                    path: "/usr/bin/printenv", arguments: [], environment: environment))
        }
        let servers = [
            local("github-x", ["TOKEN": "one"]),
            local("github", ["X_TOKEN": "two"]),
            local("both", ["token": "three", "TOKEN": "four"]),
            AIToolServer(
                handle: "a", title: "a",
                transport: .url("https://a.example/mcp", headerName: "B-C", headerValue: "five")),
            local("a-b", ["C": "six"]),
            local("日本", ["TOKEN": "seven"]),
            local("中国", ["TOKEN": "eight"])
        ]
        let environment = CodexMCPLaunch.environment(servers: servers) ?? [:]
        expect(
            environment.count == 8
                && Set(environment.values)
                    == ["one", "two", "three", "four", "five", "six", "seven", "eight"],
            "every secret gets a variable of its own, however the handles and keys are spelled")
        var delivered: [String] = []
        for (index, server) in servers.enumerated() {
            guard case .command(let path, _, let values) = server.transport else { continue }
            for key in values.keys.sorted() {
                let launch = CodexMCPLaunch.command(
                    path: path, arguments: [key], environment: values, server: index)
                delivered.append(run(launch, environment: environment))
            }
        }
        expect(
            delivered == ["one\n", "two\n", "four\n", "three\n", "six\n", "seven\n", "eight\n"],
            "and each local server reads only its own values, under its own names")
        let repeated = [(name: "TC_MCP_0_0", value: "a"), (name: "TC_MCP_0_0", value: "b")]
        expect(
            CodexMCPLaunch.distinct(repeated) == nil,
            "a repeated variable refuses the launch rather than keeping one of the two values")
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func run(
        _ launch: (path: String, arguments: [String]), environment: [String: String]
    ) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.path)
        process.arguments = launch.arguments
        process.environment = environment.merging(["PATH": "/usr/bin:/bin"]) { value, _ in value }
        let output = Pipe()
        process.standardOutput = output
        guard (try? process.run()) != nil else { return "<did not start>" }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private static let renamingArguments =
        #"mcp_servers.tinycast-files.args=["-c","export API_KEY=\"$TC_MCP_0_0\"; "#
        + #"unset TC_MCP_0_0; "#
        + #"exec \"$@\"","tinycast-mcp","/usr/local/bin/node","server.js","--root=/tmp"]"#

    /// Spelled through a joined literal so no shell hook mistakes the key for a dotfile.
    private static let forwardedVariables =
        "mcp_servers.tinycast-files." + "env" + #"_vars=["TC_MCP_0_0"]"#
    private static let headerMapOverride =
        "mcp_servers.tinycast-notes." + "env" + #"_http_headers={"X-Api-Key"="TC_MCP_2_0"}"#

    /// The config file is the only place Claude's secrets go, and the tool name is what routes back.
    static func claudeConfigurationCarriesServersAndRoutesToolNames() {
        let servers = [
            AIToolServer(
                handle: "files", title: "Files",
                transport: .command(
                    path: "/bin/node", arguments: ["s.js"], environment: ["API_KEY": "s3cret"])),
            AIToolServer(
                handle: "linear", title: "Linear",
                transport: .url(
                    "https://mcp.linear.app/mcp", headerName: "Authorization",
                    headerValue: "Bearer tok-123"))
        ]
        let text = ClaudeMCPLaunch.configuration(servers: servers)
        guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = object["mcpServers"] as? [String: Any]
        else {
            expect(false, "Claude's MCP configuration is a decodable mcpServers record")
            return
        }
        let files = entries["files"] as? [String: Any] ?? [:]
        expect(
            files["command"] as? String == "/bin/node" && files["args"] as? [String] == ["s.js"],
            "a local server carries its command and arguments in the file")
        expect(
            (files["env"] as? [String: String]) == ["API_KEY": "s3cret"],
            "and its environment, which is the only place that secret goes")
        let linear = entries["linear"] as? [String: Any] ?? [:]
        expect(
            linear["type"] as? String == "http"
                && (linear["headers"] as? [String: String]) == [
                    "Authorization": "Bearer tok-123"
                ],
            "a remote one carries the header Tinycast would have sent itself")

        let bare = ClaudeMCPLaunch.configuration(servers: [
            AIToolServer(
                handle: "open", title: "Open",
                transport: .url(
                    "https://open.example/mcp", headerName: "Authorization", headerValue: ""))
        ])
        expect(
            bare == #"{"mcpServers":{"open":{"type":"http","url":"https:\/\/open.example\/mcp"}}}"#,
            "and one that needs no credential goes to Claude with no headers at all")

        let arguments = ClaudeMCPLaunch.arguments(
            configurationPath: "/tmp/m.json", handles: ["files", "linear"], rounds: 25)
        expect(
            arguments.contains("--strict-mcp-config") && arguments.contains("/tmp/m.json")
                && arguments.contains("--permission-prompt-tool")
                && arguments.contains("stdio") && arguments.contains("25"),
            "the flags name the file, route consent to Tinycast and cap the turn")
        expect(
            !arguments.contains("--disallowedTools"),
            "and never deny every tool, which would take the MCP ones with it")
        expect(
            value(after: "--permission-mode", in: arguments) == "default",
            "the mode is pinned, so a reader's bypassPermissions default never skips the question")
        let settings =
            (value(after: "--settings", in: arguments)?.data(using: .utf8))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        expect(
            ((settings["permissions"] as? [String: Any])?["ask"] as? [String])
                == ["mcp__files", "mcp__linear"] && settings.count == 1,
            "and every armed server has an ask rule, which outranks any allow rule of the reader's")

        expect(
            ClaudeMCPLaunch.route("mcp__files__read_file")
                == AIToolServerCall(handle: "files", tool: "read_file"),
            "a wire name routes back to the server and the tool")
        expect(
            ClaudeMCPLaunch.route("mcp__files__read__file")
                == AIToolServerCall(handle: "files", tool: "read__file"),
            "the first separator is the split: a handle is letters, digits and `-`, a tool is not")
        expect(
            ClaudeMCPLaunch.route("Bash") == nil && ClaudeMCPLaunch.route("mcp__files") == nil,
            "and a name that is not one of ours routes nowhere")
    }

    /// Every other server request stays declined, so only a tool call may become a question.
    static func codexElicitationsAreOnlyToolCalls() {
        let call = CodexElicitation(
            params: [
                "serverName": .string("files"),
                "message": .string(
                    "Allow the files MCP server to run tool \u{201C}read\u{201D}?"),
                "_meta": .object([
                    "codex_approval_kind": .string("mcp_tool_call"),
                    "persist": .array([.string("session"), .string("always")])
                ])
            ])
        expect(
            call?.serverName == "files" && call?.toolName == "read" && call?.namedTool == nil,
            "a tool-call elicitation names its server, and the message names its tool")
        let named = CodexElicitation(
            params: [
                "serverName": .string("files"),
                "_meta": .object([
                    "codex_approval_kind": .string("mcp_tool_call"),
                    "tool_name": .string("write"), "tool_title": .string("Write")
                ])
            ])
        expect(
            named?.namedTool == "write" && named?.toolName == "write",
            "and `_meta.tool_name`, when sent, is the name tied to this call")
        expect(
            CodexElicitation(
                params: [
                    "serverName": .string("files"),
                    "_meta": .object(["codex_approval_kind": .string("form")])
                ]) == nil,
            "a form is not a tool call and is never asked about")
        expect(
            CodexElicitation(params: ["message": .string("hello")]) == nil,
            "and neither is an elicitation that names no server")
        expect(
            CodexElicitation.Action.accept.rawValue == "accept"
                && CodexElicitation.Action.decline.rawValue == "decline",
            "the two answers are the two the app-server honours")
    }

    private static let canUseToolFrame = """
        {"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool",\
        "tool_name":"mcp__files__read","input":{"path":"/tmp"}}}
        """

    /// The consent channel is the SDK's undocumented one; this is the whole of what Tinycast speaks.
    static func claudeControlFramesAnswerOneTool() {
        let frame =
            (try? JSONSerialization.jsonObject(with: Data(Self.canUseToolFrame.utf8)))
            as? [String: Any] ?? [:]
        guard let request = ClaudeControlProtocol.request(frame) else {
            expect(false, "a can_use_tool frame decodes into a request")
            return
        }
        expect(
            request.id == "r1" && request.call == AIToolServerCall(handle: "files", tool: "read"),
            "carrying the id to answer and the call to ask about")

        guard let allow = ClaudeControlProtocol.response(to: request, allowed: true, message: ""),
            let decodedAllow = try? JSONSerialization.jsonObject(with: allow) as? [String: Any],
            let allowed = (decodedAllow["response"] as? [String: Any])?["response"]
                as? [String: Any]
        else {
            expect(false, "an allow encodes as a control_response")
            return
        }
        expect(
            allowed["behavior"] as? String == "allow"
                && (allowed["updatedInput"] as? [String: Any])?["path"] as? String == "/tmp",
            "an allow hands the arguments back untouched")
        expect(
            allowed["updatedPermissions"] == nil,
            "and never a permission update, which would have the CLI write its own settings")
        expect(
            allow.last == 0x0A, "each answer is one line, because the channel is newline framed")

        guard let deny = ClaudeControlProtocol.response(to: request, allowed: false, message: "no"),
            let decodedDeny = try? JSONSerialization.jsonObject(with: deny) as? [String: Any],
            let denied = (decodedDeny["response"] as? [String: Any])?["response"] as? [String: Any]
        else {
            expect(false, "a deny encodes as a control_response")
            return
        }
        expect(
            denied["behavior"] as? String == "deny" && denied["message"] as? String == "no",
            "a deny says so, and the model reads the reason as the call's result")

        let other =
            (try? JSONSerialization.jsonObject(
                with: Data(
                    #"{"type":"control_request","request_id":"r2","request":{"subtype":"initialize"}}"#
                        .utf8))) as? [String: Any] ?? [:]
        expect(
            ClaudeControlProtocol.request(other) == nil
                && ClaudeControlProtocol.unsupportedRequestID(other) == "r2"
                && ClaudeControlProtocol.unsupportedRequestID(frame) == nil,
            "a subtype Tinycast does not know is no tool question, yet it is still answered")
        let error =
            ClaudeControlProtocol.error(to: "r2", message: "no")
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let errorResponse = error?["response"] as? [String: Any]
        expect(
            error?["type"] as? String == "control_response"
                && errorResponse?["subtype"] as? String == "error"
                && errorResponse?["request_id"] as? String == "r2",
            "with the SDK's error response, so the CLI stops waiting on it")
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
