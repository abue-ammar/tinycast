import Foundation
import Testing

@testable import Tinycast

extension AIProviderTests {
    // MARK: Endpoints

    @Test(arguments: [
        (AIProviderKind.openAI, "https://api.openai.com/v1/responses"),
        (.anthropic, "https://api.anthropic.com/v1/messages"),
        (.gemini, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"),
        (.openRouter, "https://openrouter.ai/api/v1/chat/completions"),
        (.openAICompatible, "https://api.openai.com/v1/chat/completions")
    ])
    func eachPresetResolvesItsDocumentedStreamingEndpoint(_ provider: AIProviderKind, _ endpoint: String) throws {
        let configuration = AIHTTPConfiguration(
            provider: provider, baseURL: try #require(URL(string: provider.defaultBaseURL)), model: "model")
        #expect(configuration.endpointURL.absoluteString == endpoint)
    }

    @Test func anExplicitCompletionEndpointIsNotAppendedTwice() throws {
        let configuration = AIHTTPConfiguration(
            provider: .openAICompatible,
            baseURL: try #require(URL(string: "https://example.com/chat/completions")), model: "model")
        #expect(configuration.endpointURL.absoluteString == "https://example.com/chat/completions")
    }

    // MARK: Model catalog requests

    @Test(arguments: [
        (AIProviderKind.openAI, "https://api.openai.com/v1/models"),
        (.anthropic, "https://api.anthropic.com/v1/models?limit=1000"),
        (.gemini, "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000"),
        (.openRouter, "https://openrouter.ai/api/v1/models/user"),
        (.openAICompatible, "https://api.openai.com/v1/models")
    ])
    func eachProviderQueriesItsModelCatalogEndpoint(_ provider: AIProviderKind, _ endpoint: String) throws {
        let request = try CatalogFixtures.discovery(provider, baseURL: provider.defaultBaseURL, apiKey: "secret")
        #expect(request.url?.absoluteString == endpoint)
    }

    @Test(arguments: [
        (AIProviderKind.anthropic, "https://api.anthropic.com", "x-api-key", "secret"),
        (.gemini, AIProviderKind.gemini.defaultBaseURL, "x-goog-api-key", "secret"),
        (.openAI, AIProviderKind.openAI.defaultBaseURL, "Authorization", "Bearer secret")
    ])
    func discoveryAuthenticatesTheWayEachVendorExpects(
        _ provider: AIProviderKind, _ baseURL: String, _ header: String, _ value: String
    ) throws {
        let request = try CatalogFixtures.discovery(provider, baseURL: baseURL, apiKey: "secret")
        #expect(request.value(forHTTPHeaderField: header) == value)
    }

    @Test func aRootEndpointAppendsOneModelPathSeparator() throws {
        let request = try CatalogFixtures.discovery(.openAICompatible, baseURL: "http://localhost:11434/")
        #expect(request.url?.absoluteString == "http://localhost:11434/models")
    }

    @Test func customHeadersReplaceADefaultOfTheSameNameAndAnEmptyKeySendsNone() throws {
        let request = try CatalogFixtures.discovery(
            .anthropic, baseURL: "https://gateway.example.com",
            headers: ["anthropic-version": "2024-01-01", "X-Tenant": "acme"])
        #expect(request.value(forHTTPHeaderField: "x-api-key") == nil, "an empty key sends no credential header")
        #expect(request.value(forHTTPHeaderField: "Anthropic-Version") == "2024-01-01")
        #expect(request.value(forHTTPHeaderField: "x-tenant") == "acme")
    }

    // MARK: Request headers

    @Test func headerRowsAreTrimmedBlankRowsDroppedAndTabsKept() throws {
        let headers = try AIRequestHeaders.validated([
            (" X-Tenant ", " acme\n"), ("", " "), ("Authorization", "Bearer\ttoken")
        ])
        #expect(headers == ["X-Tenant": "acme", "Authorization": "Bearer\ttoken"])
    }

    @Test(arguments: [
        HeaderRows("a missing name", [("", "value")]),
        HeaderRows("a name outside the HTTP token set", [("X Tenant", "acme")]),
        HeaderRows("a name repeated in another case", [("X-Tenant", "a"), ("x-tenant", "b")]),
        HeaderRows("a value carrying a line break into another header", [("X-Tenant", "a\r\nX-Injected: b")])
    ])
    func anInvalidHeaderRowIsRefused(_ headers: HeaderRows) {
        #expect(throws: (any Error).self) { try AIRequestHeaders.validated(headers.rows) }
    }

    struct HeaderRows: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let rows: [(name: String, value: String)]

        init(_ description: String, _ rows: [(name: String, value: String)]) {
            testDescription = description
            self.rows = rows
        }
    }

    // MARK: Model catalog responses

    @Test func openAICompatibleModelListsAreNamedAndDeduplicated() throws {
        let models = try AIModelDiscovery.decode(CatalogFixtures.openAICatalog, shape: .openAI)
        #expect(
            models == [
                .init(id: "model-a", name: "model-a"),
                .init(
                    id: "model-b", name: "Model B", inputModalities: ["text", "image"],
                    reasoningOptions: .init(efforts: ["high", "medium", "low"], defaultEffort: "medium"))
            ])
    }

    @Test func onlyACatalogThatListsModalitiesSaysWhetherAModelTakesImages() throws {
        let models = try AIModelDiscovery.decode(CatalogFixtures.openAICatalog, shape: .openAI)
        #expect(models.map(\.acceptsImages) == [nil, true])
    }

    @Test func reasoningMetadataKeepsTheModelsAdvertisedDefault() throws {
        let models = try AIModelDiscovery.decode(CatalogFixtures.openAICatalog, shape: .openAI)
        #expect(models.last?.reasoningOptions?.resolvedEffort(nil) == "medium")
    }

    @Test func aReasoningFieldThatIsNotAnObjectIsIgnoredAndTheCatalogStillLoads() throws {
        let gateway = Data(
            """
            {"data":[
                {"id":"model-c","name":"Model C","reasoning":true,
                 "architecture":{"input_modalities":["text","image"]}},
                {"id":"model-d","reasoning":"high"},
                {"id":"model-e","reasoning":{"supported_efforts":["low"],"default_effort":"low"}}
            ]}
            """.utf8)
        #expect(
            try AIModelDiscovery.decode(gateway, shape: .openAI) == [
                .init(id: "model-c", name: "Model C", inputModalities: ["text", "image"]),
                .init(id: "model-d", name: "model-d"),
                .init(id: "model-e", name: "model-e", reasoningOptions: .init(efforts: ["low"], defaultEffort: "low"))
            ])
    }

    @Test func openRouterGatesImagesByTheCatalogAndSearchesForEveryModel() {
        let router = AIConnection(provider: .openRouter, models: ["model-a", "model-b"], visionModels: ["model-b"])
        #expect(!router.capabilities(for: "model-a").images)
        #expect(router.capabilities(for: "model-b").images)
        #expect(router.capabilities(for: "model-a").webSearch)
    }

    @Test func aVendorAPITakesImagesAndHasNoSearchSwitch() {
        let direct = AIConnection(provider: .gemini, models: ["model-a"])
        #expect(direct.capabilities(for: "model-a").images)
        #expect(!direct.capabilities(for: "model-a").webSearch)
    }

    @Test func geminiDiscoveryKeepsGenerationModelsAndStripsTheResourcePrefix() throws {
        let gemini = Data(
            """
            {"models":[
                {"name":"models/gemini-chat","displayName":"Gemini Chat",\
                 "supportedGenerationMethods":["generateContent"]},
                {"name":"models/gemini-embed","displayName":"Gemini Embed",\
                 "supportedGenerationMethods":["embedContent"]}
            ]}
            """.utf8)
        #expect(try AIModelDiscovery.decode(gemini, shape: .gemini) == [.init(id: "gemini-chat", name: "Gemini Chat")])
    }

    // MARK: Model search

    @Test func anEmptySearchNeverRendersTheCompleteCatalog() {
        #expect(AIModelDiscovery.search(CatalogFixtures.searchable, query: "").isEmpty)
    }

    @Test func aProviderNameFindsItsModelsInProviderOrder() {
        #expect(
            AIModelDiscovery.search(CatalogFixtures.searchable, query: "openai").map(\.id)
                == ["openai/gpt-small", "openai/gpt-large"])
    }

    @Test func anExactDisplayNameMatchRanksFirst() {
        #expect(AIModelDiscovery.search(CatalogFixtures.searchable, query: "GPT Large").first?.id == "openai/gpt-large")
    }

    @Test func searchExcludesSelectedModelsAndCapsVisibleResults() {
        let found = AIModelDiscovery.search(
            CatalogFixtures.searchable, query: "gpt", excluding: ["openai/gpt-small"], limit: 1)
        #expect(found.map(\.id) == ["openai/gpt-large"])
    }

    @Test(arguments: [
        (" GPT-5.4-MINI ", "gpt-5.4-mini"),
        ("claude sonnet 4", "claude-sonnet-4-20250514")
    ])
    func anExactIDOrDisplayNameNamesItsModelWhateverItsCaseAndSpacing(_ query: String, _ id: String) {
        #expect(AIModelDiscovery.exactMatch(CatalogFixtures.exact, query: query)?.id == id)
    }

    /// "gpt-5" is contained in a listed ID, which is not a whole-model match.
    @Test(arguments: ["gpt-5", "  "])
    func aPartialOrBlankQueryMatchesNothing(_ query: String) {
        #expect(AIModelDiscovery.exactMatch(CatalogFixtures.exact, query: query) == nil)
    }

    @Test func anExactIDWinsOverAnEarlierModelWhoseDisplayNameMatches() {
        let aliased = [
            AIModelDiscovery.Model(id: "gateway-default", name: "gpt-5"),
            AIModelDiscovery.Model(id: "gpt-5", name: "GPT-5")
        ]
        #expect(AIModelDiscovery.exactMatch(aliased, query: "gpt-5")?.id == "gpt-5")
    }

    // MARK: Endpoint policy

    @Test(arguments: ["https://example.com/v1", "http://localhost:11434/v1", "http://127.0.0.1:1234/v1"])
    func remoteHTTPSAndLoopbackHTTPEndpointsAreAccepted(_ endpoint: String) throws {
        #expect(throws: Never.self) { try AIEndpointPolicy.validate(endpoint) }
    }

    /// A loopback host does not excuse a scheme the transport cannot speak, and a file is no provider.
    @Test(arguments: ["http://example.com/v1", "not a url", "ftp://localhost/v1", "file:///etc/hosts"])
    func plaintextRemoteMalformedAndForeignSchemeEndpointsAreRejected(_ endpoint: String) {
        #expect(throws: (any Error).self) { try AIEndpointPolicy.validate(endpoint) }
    }

    @Test func anUntouchedOrRelabelledConnectionKeepsItsDestination() {
        let saved = CatalogFixtures.openAIConnection
        #expect(AIEndpointPolicy.sameDestination(saved, saved), "an untouched connection points where its key was issued")
        var renamed = saved
        renamed.name = "Work key"
        renamed.models = ["gpt-5.4-mini"]
        #expect(AIEndpointPolicy.sameDestination(renamed, saved), "a label or model list edit is not a retarget")
    }

    /// The OpenAI key must not go to Anthropic, whatever the provider preset still says.
    @Test func aNewProviderOrBaseURLIsANewDestination() {
        let saved = CatalogFixtures.openAIConnection
        var switchedProvider = saved
        switchedProvider.provider = .anthropic
        #expect(!AIEndpointPolicy.sameDestination(switchedProvider, saved))
        var switchedURL = saved
        switchedURL.baseURL = "https://gateway.example.com/v1"
        #expect(!AIEndpointPolicy.sameDestination(switchedURL, saved))
    }

    // MARK: Saving a connection's key

    @Test(arguments: KeyDecision.all)
    func savingAConnectionDecidesItsKey(_ decision: KeyDecision) {
        let outcome = AIConnectionKeyPolicy.resolve(
            enteredKey: decision.enteredKey, connection: decision.connection, saved: decision.saved,
            hasStoredKey: decision.hasStoredKey, hasHeaders: decision.hasHeaders)
        #expect(outcome == decision.expected)
    }

    struct KeyDecision: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let enteredKey: String
        let connection: AIConnection
        let saved: AIConnection?
        let hasStoredKey: Bool
        let hasHeaders: Bool
        let expected: AIConnectionKeyPolicy.Outcome

        static let all: [KeyDecision] = {
            let remote = CatalogFixtures.openAIConnection
            var local = remote
            local.baseURL = "http://localhost:11434/v1"
            var moved = remote
            moved.baseURL = "https://gateway.example.com/v1"
            let retargetRefusal = "Enter an API key for this endpoint — the saved key stays with the old one."
            let missingKey = "Enter an API key for this remote provider."
            return [
                KeyDecision(
                    "a typed key is stored trimmed",
                    "  sk-new \n", remote, nil, stored: false, headers: false, .store("sk-new")),
                KeyDecision(
                    "a retarget that brings its own key replaces the old one",
                    "sk-new", moved, remote, stored: true, headers: false, .store("sk-new")),
                KeyDecision(
                    "a remote retarget without a key is refused, so the old key never reaches the new host",
                    " ", moved, remote, stored: true, headers: false, .reject(retargetRefusal)),
                KeyDecision(
                    "a retarget to loopback drops the key issued for the remote endpoint",
                    "", local, remote, stored: true, headers: false, .removeStored),
                KeyDecision(
                    "a new remote connection needs a key",
                    "", remote, nil, stored: false, headers: false, .reject(missingKey)),
                KeyDecision(
                    "a loopback endpoint saves without a key",
                    "", local, nil, stored: false, headers: false, .keep),
                KeyDecision(
                    "an unchanged endpoint keeps its saved key",
                    "", remote, remote, stored: true, headers: false, .keep),
                KeyDecision(
                    "with no saved key there is nothing to retarget, only a missing key",
                    "", moved, remote, stored: false, headers: false, .reject(missingKey)),
                KeyDecision(
                    "request headers can authenticate a remote endpoint without a key",
                    "", remote, nil, stored: false, headers: true, .keep),
                KeyDecision(
                    "a retarget authenticated by headers drops the old key rather than carry it over",
                    "", moved, remote, stored: true, headers: true, .removeStored)
            ]
        }()

        private init(
            _ description: String, _ enteredKey: String, _ connection: AIConnection, _ saved: AIConnection?,
            stored: Bool, headers: Bool, _ expected: AIConnectionKeyPolicy.Outcome
        ) {
            testDescription = description
            self.enteredKey = enteredKey
            self.connection = connection
            self.saved = saved
            hasStoredKey = stored
            hasHeaders = headers
            self.expected = expected
        }
    }
}

private enum CatalogFixtures {
    static let openAICatalog = Data(
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

    static let searchable = [
        AIModelDiscovery.Model(id: "openai/gpt-small", name: "GPT Small"),
        AIModelDiscovery.Model(id: "anthropic/claude", name: "Claude"),
        AIModelDiscovery.Model(id: "openai/gpt-large", name: "GPT Large"),
        AIModelDiscovery.Model(id: "google/gemini", name: "Gemini")
    ]

    static let exact = [
        AIModelDiscovery.Model(id: "gpt-5.4-mini", name: "GPT-5.4 Mini"),
        AIModelDiscovery.Model(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4")
    ]

    static let openAIConnection: AIConnection = {
        var connection = AIConnection()
        connection.provider = .openAI
        connection.baseURL = "https://api.openai.com/v1"
        return connection
    }()

    static func discovery(
        _ provider: AIProviderKind, baseURL: String, apiKey: String = "", headers: [String: String] = [:]
    ) throws -> URLRequest {
        let url = try #require(URL(string: baseURL))
        return try AIModelDiscovery.query(
            provider: provider, baseURL: url, apiKey: apiKey, appTitle: "Tinycast", headers: headers
        ).request
    }
}
