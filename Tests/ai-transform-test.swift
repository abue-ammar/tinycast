import Foundation

// Pure model + client layer: no network, no Keychain. The request is inspected by decoding its
// JSON body against a local mirror of the wire shape, so a field rename here fails loudly there.
@main
struct AITransformTests {
    @MainActor
    static func main() async {
        let suiteName = "com.tinycast.ai-transform-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("FAIL  could not create an isolated UserDefaults suite")
            exit(1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // MARK: Entry ids

        let transform = AITransform(name: "Fix Spelling", prompt: "Fix mistakes.")
        check(
            "the entry id round-trips to the UUID",
            AITransform.id(fromEntryID: transform.entryID) == transform.id)
        check("the entry id carries the ai-transform prefix", transform.entryID.hasPrefix("ai-transform:"))
        check("a foreign entry id parses to nothing", AITransform.id(fromEntryID: "custom-command:x") == nil)

        // MARK: Validation

        func validationError(of draft: AITransform, in store: AITransformStore) -> AITransformValidationError?
        {
            do {
                _ = try store.add(draft)
                return nil
            } catch let error as AITransformValidationError {
                return error
            } catch {
                return nil
            }
        }

        let validator = AITransformStore(defaults: defaults)
        _ = try? validator.add(AITransform(name: "Existing", prompt: "Do things."))

        check(
            "an empty name is rejected",
            validationError(of: AITransform(name: "   ", prompt: "x"), in: validator) == .emptyName)
        check(
            "an empty prompt is rejected",
            validationError(of: AITransform(name: "Named", prompt: ""), in: validator) == .emptyPrompt)
        check(
            "an over-long name is rejected",
            validationError(
                of: AITransform(name: String(repeating: "a", count: 61), prompt: "x"),
                in: validator) == .nameTooLong)
        check(
            "an over-long prompt is rejected",
            validationError(
                of: AITransform(name: "Named", prompt: String(repeating: "a", count: 4_001)),
                in: validator) == .promptTooLong)
        check(
            "a name differing only in case is rejected",
            validationError(of: AITransform(name: "existing", prompt: "x"), in: validator)
                == .duplicateName)
        check(
            "every validation error carries a human sentence",
            [
                AITransformValidationError.emptyName, .emptyPrompt, .nameTooLong, .promptTooLong,
                .duplicateName
            ]
            .allSatisfy { $0.errorDescription?.hasSuffix(".") == true })

        // MARK: Store

        // A fresh suite, so the validator's records above cannot leak into the store's assertions.
        let storeSuite = "com.tinycast.ai-transform-tests.store.\(UUID().uuidString)"
        guard let storeDefaults = UserDefaults(suiteName: storeSuite) else {
            print("FAIL  could not create the store defaults suite")
            exit(1)
        }
        storeDefaults.removePersistentDomain(forName: storeSuite)
        defer { storeDefaults.removePersistentDomain(forName: storeSuite) }

        let store = AITransformStore(defaults: storeDefaults)
        let added = try? store.add(
            AITransform(name: "  Polish Writing  ", prompt: "  Improve the prose.  ", model: "  "))

        check("add trims the name", added?.name == "Polish Writing")
        check("add trims the prompt", added?.prompt == "Improve the prose.")
        check("add drops a whitespace-only model override", added?.model == nil)

        guard let added else {
            print("FAIL  add returned nothing; the remaining cases need it")
            exit(1)
        }

        try? store.update(
            AITransform(id: added.id, name: "Polish Prose", prompt: "Better.", model: "gpt-4o"))
        check("update keeps the id", store.transform(id: added.id) != nil)
        check("update applies the new name", store.transform(id: added.id)?.name == "Polish Prose")
        check("update applies a model override", store.transform(id: added.id)?.model == "gpt-4o")

        check(
            "lookup by entry id resolves the transform",
            store.transform(entryID: added.entryID)?.id == added.id)

        let expected = store.transforms
        check(
            "transforms survive a reload",
            AITransformStore(defaults: storeDefaults).transforms == expected)

        let removed = store.remove(id: added.id)
        check("remove returns the removed transform", removed?.id == added.id)
        check("remove empties the store", store.transforms.isEmpty)

        // `replace` runs the import sanitizer, which must drop junk without touching survivors.
        let kept = UUID()
        let keptCount = store.replace(with: [
            AITransform(id: kept, name: " Kept ", prompt: "Stay.", model: ""),
            AITransform(name: "", prompt: "No name."),
            AITransform(id: kept, name: "Duplicate ID", prompt: "Same id."),
            AITransform(name: "kept", prompt: "Case-collision.")
        ])
        check("replace returns the kept count", keptCount == 1)
        check(
            "replace trims and keeps the one valid record",
            store.transforms == [AITransform(id: kept, name: "Kept", prompt: "Stay.")])

        store.remove(id: kept)

        // MARK: Seeded presets

        store.seedBuiltInsIfEmpty()
        let seededNames = store.transforms.map(\.name)
        check(
            "seeding inserts the four presets",
            seededNames == ["Fix Spelling & Grammar", "Polish Writing", "Make Concise", "Summarize"])
        check(
            "every seed has a non-empty prompt",
            store.transforms.allSatisfy { !$0.prompt.isEmpty })
        store.seedBuiltInsIfEmpty()
        check("seeding on a non-empty store changes nothing", store.transforms.count == 4)

        // MARK: Request building

        let request = AICompletionRequest(
            baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "sk-test", model: "gpt-4o-mini",
            instruction: "Fix mistakes.", selection: "Helo world")
        let urlRequest = request.makeURLRequest()
        check(
            "the endpoint joins the base URL with /chat/completions",
            urlRequest.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        check("the method is POST", urlRequest.httpMethod == "POST")
        check(
            "the key rides as a bearer token",
            urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        check(
            "the body is JSON",
            urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")

        struct WireBody: Decodable {
            var model: String
            var stream: Bool
            var max_tokens: Int
            var messages: [WireMessage]

            struct WireMessage: Decodable {
                var role: String
                var content: String
            }
        }
        let body = try? JSONDecoder().decode(WireBody.self, from: urlRequest.httpBody ?? Data())
        guard let body else {
            print("FAIL  the request body did not decode; the remaining cases need it")
            exit(1)
        }
        check("the body names the model", body.model == "gpt-4o-mini")
        check("streaming is off", body.stream == false)
        check("max_tokens is capped at 4096", body.max_tokens == 4096)
        check("there are exactly two messages", body.messages.count == 2)
        check("the system message comes first", body.messages[0].role == "system")
        check("the user message comes second", body.messages[1].role == "user")
        check(
            "the system message wraps the instruction",
            body.messages[0].content
                == AICompletionRequest.systemInstruction("Fix mistakes."))
        check(
            "the system instruction appends the strict output contract",
            AICompletionRequest.systemInstruction("Fix mistakes.").contains(
                "Unless explicitly requested otherwise")
                && AICompletionRequest.systemInstruction("Fix mistakes.").contains(
                    "Do NOT include any preamble")
                && AICompletionRequest.systemInstruction("Fix mistakes.").contains(
                    "Do NOT include any commentary")
                && AICompletionRequest.systemInstruction("Fix mistakes.").contains(
                    "Do NOT include follow-up questions")
        )
        check("the selection is the user message", body.messages[1].content == "Helo world")

        // MARK: Endpoint normalization

        func endpoint(_ base: String) -> String? {
            AICompletionRequest.endpointURL(fromBase: base)?.absoluteString
        }
        check(
            "a plain versioned root joins the path",
            endpoint("https://api.openai.com/v1") == "https://api.openai.com/v1/chat/completions")
        check(
            "a trailing slash is dropped before joining",
            endpoint("https://generativelanguage.googleapis.com/v1beta/")
                == "https://generativelanguage.googleapis.com/v1beta/chat/completions")
        check(
            "a full pasted endpoint keeps working instead of doubling the path",
            endpoint("https://api.openai.com/v1/chat/completions/")
                == "https://api.openai.com/v1/chat/completions")
        check(
            "surrounding whitespace goes",
            endpoint("  https://api.openai.com/v1  ") == "https://api.openai.com/v1/chat/completions"
        )
        check(
            "the suffix match ignores case",
            endpoint("https://api.openai.com/v1/Chat/Completions")
                == "https://api.openai.com/v1/chat/completions")

        // MARK: Provider catalog

        check("catalog names are unique", Set(AIProvider.catalog.map(\.id)).count == AIProvider.catalog.count)
        for provider in AIProvider.catalog {
            let url = AICompletionRequest.endpointURL(fromBase: provider.baseURL)
            check(
                "the \(provider.name) root joins into a valid endpoint",
                url != nil && url?.host != nil
                    && url?.path.hasSuffix("/chat/completions") == true)
            check(
                "the \(provider.name) scheme matches locality",
                provider.isLocal == (url?.scheme == "http"))
        }
        check(
            "matching tolerates a trailing slash",
            AIProvider.matching(baseURL: "https://api.groq.com/openai/v1/")?.name == "Groq")
        check(
            "an unknown root reads as no provider at all",
            AIProvider.matching(baseURL: "https://my-box.example/v1") == nil)

        // MARK: Response parsing

        func parseError(_ data: Data, status: Int) -> AIClientError? {
            do {
                _ = try AIClient.parseResponse(data, status: status)
                return nil
            } catch let error as AIClientError {
                return error
            } catch {
                return nil
            }
        }

        let happy = """
            {"choices":[{"message":{"role":"assistant","content":"  Hello world  "}}]}
            """.data(using: .utf8)!
        check(
            "a happy path returns the trimmed content",
            (try? AIClient.parseResponse(happy, status: 200)) == "Hello world")

        let providerError = """
            {"error":{"message":"Incorrect API key","type":"invalid_request_error"}}
            """.data(using: .utf8)!
        check(
            "a 401 maps to unauthorized even with an error body",
            parseError(providerError, status: 401) == .unauthorized)
        check(
            "a 429 maps to rate limited",
            parseError(providerError, status: 429) == .rateLimited)
        check(
            "another status surfaces the provider message",
            parseError(providerError, status: 500)
                == .provider(status: 500, message: "Incorrect API key"))

        let malformed = "not json".data(using: .utf8)!
        check(
            "malformed JSON with a good status is an empty response",
            parseError(malformed, status: 200) == .emptyResponse)
        check(
            "malformed JSON with a bad status degrades to a bounded raw snippet",
            parseError(malformed, status: 502) == .provider(status: 502, message: "not json"))

        let googleError = """
            {"error":{"code":404,"message":"Requested entity was not found.","status":"NOT_FOUND"}}
            """.data(using: .utf8)!
        let notFound = parseError(googleError, status: 404)
        if case .provider(404, let message)? = notFound {
            check(
                "a Google-style error body surfaces its message",
                message.hasPrefix("Requested entity was not found."))
            check(
                "a 404 carries the base-URL hint",
                message.contains("/v1beta/openai"))
        } else {
            check("a 404 maps to a provider error", false)
        }
        let flatMessage = """
            {"message":"Model gemini-x does not exist"}
            """.data(using: .utf8)!
        check(
            "a flat top-level message is surfaced too",
            parseError(flatMessage, status: 400)
                == .provider(status: 400, message: "Model gemini-x does not exist"))

        let emptyChoices = """
            {"choices":[]}
            """.data(using: .utf8)!
        check(
            "empty choices is an empty response",
            parseError(emptyChoices, status: 200) == .emptyResponse)

        let blankContent = """
            {"choices":[{"message":{"role":"assistant","content":"   "}}]}
            """.data(using: .utf8)!
        check(
            "whitespace-only content is an empty response",
            parseError(blankContent, status: 200) == .emptyResponse)

        // MARK: Model listing

        let envelope = """
            {"data":[{"id":"zeta"},{"id":"alpha"},{"id":"alpha"},{"object":"model"}]}
            """.data(using: .utf8)!
        check(
            "the OpenAI envelope yields sorted unique ids",
            AIClient.parseModelList(envelope) == ["alpha", "zeta"])
        let bare = """
            ["m2", {"name": "m1"}]
            """.data(using: .utf8)!
        check(
            "a bare array with mixed entries still lists",
            AIClient.parseModelList(bare) == ["m1", "m2"])
        check(
            "an unrecognizable body lists nothing",
            AIClient.parseModelList("nope".data(using: .utf8)!) == [])

        // MARK: Connection test request

        let testRequest = AIClient.makeTestURLRequest(
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            apiKey: "sk-test", model: "gpt-4o-mini")
        check("the probe posts", testRequest.httpMethod == "POST")
        check(
            "the probe authenticates",
            testRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        struct TestWire: Decodable {
            var model: String
            var stream: Bool
            var max_tokens: Int
            var messages: [WireBody.WireMessage]
        }
        let testBody = try? JSONDecoder().decode(TestWire.self, from: testRequest.httpBody ?? Data())
        check("the probe caps tokens", testBody?.max_tokens == 16)
        check(
            "the probe sends one user message",
            testBody?.messages.count == 1 && testBody?.messages.first?.role == "user")

        check(
            "error descriptions stay human sentences",
            AIClientError.notConfigured.errorDescription?.isEmpty == false
                && AIClientError.rateLimited.errorDescription?.contains("Rate limited") == true)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
