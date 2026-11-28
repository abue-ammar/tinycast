import Foundation
import Testing

@testable import Tinycast

extension AIProviderTests {
    // MARK: A gateway's thinking switch

    @Test func aGatewayOffersDefaultAndNoneWithReasoningLeftOn() throws {
        let gateway = AIConnection(provider: .openAI, baseURL: EffortFixtures.gateway, models: ["m"])
        let options = try #require(gateway.reasoningOptions(for: "m"))
        #expect(
            options.efforts == ["default", "none"],
            "a preset pointed away from its own API offers the one effort a gateway can honour")
        #expect(options.resolvedEffort(nil) == "default", "reasoning stays on until the reader picks None")
    }

    /// A vendor rejects what it does not define.
    @Test func aPresetOnItsOwnAPIOffersNoSwitch() {
        #expect(AIConnection(provider: .openAI, models: ["m"]).reasoningOptions(for: "m") == nil)
    }

    @Test func theAnthropicShapeNeverTakesTheGatewaysSwitch() {
        let connection = AIConnection(provider: .anthropic, baseURL: "https://gateway.example", models: ["m"])
        #expect(connection.reasoningOptions(for: "m") == nil)
    }

    @Test func aPublishedCatalogWinsOverTheSynthesizedSwitch() {
        let catalogued = AIConnection(
            id: UUID(), provider: .openRouter, baseURL: "https://gateway.example", models: ["m"],
            reasoningOptions: ["m": .init(efforts: ["high", "low"], defaultEffort: "high")])
        #expect(catalogued.reasoningOptions(for: "m")?.efforts == ["high", "low"])
    }

    @Test func reasoningLeftAloneSendsNoThinkingKey() {
        let body = EffortFixtures.body(AIHTTPConfiguration(
            provider: .openAI, baseURL: EffortFixtures.gatewayURL, model: "m"))
        #expect(body["thinking"] == nil)
    }

    @Test func noneAsksTheGatewayToAnswerDirectlyWithNoEffortBesideIt() {
        let body = EffortFixtures.body(AIHTTPConfiguration(
            provider: .openAI, baseURL: EffortFixtures.gatewayURL, model: "m", effort: "none",
            disablesThinking: true))
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
        #expect(body["reasoning_effort"] == nil)
    }

    // MARK: Declared levels on a gateway

    @Test func declaredLevelsSitInLadderOrderBetweenDefaultAndNone() throws {
        var declared = AIConnection(provider: .openAI, baseURL: EffortFixtures.gateway, models: ["m"])
        declared.declareLevels(["high", "low", "bogus"], for: "m")
        let options = try #require(declared.reasoningOptions(for: "m"))
        #expect(options.efforts == ["default", "low", "high", "none"], "strangers drop")
        #expect(
            options.resolvedEffort(nil) == "default",
            "a declaration leaves reasoning alone until the reader picks a level")
        #expect(declared.declaredLevels(for: "m") == ["low", "high"], "the declaration reads back")
    }

    @Test func clearingADeclarationReturnsToDefaultAndNone() {
        var declared = AIConnection(provider: .openAI, baseURL: EffortFixtures.gateway, models: ["m"])
        declared.declareLevels(["high", "low"], for: "m")
        declared.declareLevels([], for: "m")
        #expect(declared.reasoningOptions(for: "m")?.efforts == ["default", "none"])
    }

    @Test func aDeclaredLevelGoesOutAsOpenAIsOwnReasoningEffort() {
        let body = EffortFixtures.body(AIHTTPConfiguration(
            provider: .openAI, baseURL: EffortFixtures.gatewayURL, model: "m", effort: "low"))
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(body["reasoning"] == nil, "not as OpenRouter's reasoning object")
    }

    @Test func defaultOnAGatewaySendsNoEffortField() {
        let body = EffortFixtures.body(AIHTTPConfiguration(
            provider: .openAI, baseURL: EffortFixtures.gatewayURL, model: "m", effort: "default"))
        #expect(body["reasoning_effort"] == nil)
    }

    // MARK: Declared levels never outlive their destination

    @Test func onlyAStillDeclaredLevelIsSent() {
        var gateway = EffortFixtures.declaredGateway
        #expect(gateway.offeredEffort("high", for: "m") == "high", "a declared level is sent")
        #expect(gateway.offeredEffort(nil, for: "m") == nil, "no saved effort sends none")
        gateway.declareLevels(["low"], for: "m")
        #expect(
            gateway.offeredEffort("high", for: "m") == nil,
            "a chat still holding an unticked level stops sending it")
    }

    @Test func levelsDeclaredForAGatewayAreNeitherOfferedNorSentToTheVendor() {
        var vendor = EffortFixtures.declaredGateway
        vendor.declareLevels(["low"], for: "m")
        vendor.baseURL = AIProviderKind.openAI.defaultBaseURL
        vendor.dropDeclaredLevels()
        #expect(vendor.reasoningOptions(for: "m") == nil)
        #expect(vendor.offeredEffort("low", for: "m") == nil)
    }

    @Test func openRoutersCatalogStillReachesItsDefaultURL() {
        let openRouter = EffortFixtures.openRouter
        #expect(openRouter.offeredEffort("high", for: "m") == "high")
        #expect(openRouter.offeredEffort("xhigh", for: "m") == nil, "a level its catalog dropped is not sent")
    }

    @Test func anOldOpenRouterEffortLeftOnAVendorConnectionIsNotSent() {
        #expect(AIConnection(provider: .openAI, models: ["m"]).offeredEffort("high", for: "m") == nil)
    }

    @Test func movingTheURLDropsADeclarationButKeepsOpenRoutersCatalog() {
        var retargeted = EffortFixtures.declaredGateway
        retargeted.dropDeclaredLevels()
        #expect(retargeted.reasoningOptions == nil, "levels declared for one gateway are dropped")
        var movedOpenRouter = EffortFixtures.openRouter
        movedOpenRouter.dropDeclaredLevels()
        #expect(
            movedOpenRouter.reasoningOptions == EffortFixtures.openRouter.reasoningOptions,
            "OpenRouter's catalog is no declaration, so a moved URL keeps it")
    }

    @Test func gatewaysAndVendorsTakeDeclaredLevelsButOpenRouterDoesNot() {
        #expect(EffortFixtures.declaredGateway.takesDeclaredLevels, "a gateway takes declared levels")
        var vendor = EffortFixtures.declaredGateway
        vendor.baseURL = AIProviderKind.openAI.defaultBaseURL
        vendor.dropDeclaredLevels()
        #expect(vendor.takesDeclaredLevels, "and so does a vendor's own URL")
        #expect(
            !AIConnection(provider: .openRouter, baseURL: "https://proxy.example/v1").takesDeclaredLevels,
            "OpenRouter at any URL does not, because its catalog names the levels")
    }

    // MARK: Vendors' own levels

    struct VendorLadder: CustomTestStringConvertible, Sendable {
        let provider: AIProviderKind
        let declared: Set<String>
        let offered: [String]
        var testDescription: String { "\(provider)" }
    }

    static let vendorLadders = [
        VendorLadder(
            provider: .openAI, declared: ["max", "none", "low", "xhigh", "bogus"],
            offered: ["default", "low", "xhigh", "max", "none"]),
        VendorLadder(
            provider: .anthropic, declared: ["minimal", "none", "low", "max"],
            offered: ["default", "low", "max"]),
        VendorLadder(
            provider: .gemini, declared: ["xhigh", "high", "none"], offered: ["default", "high", "none"])
    ]

    /// OpenAI takes its whole ladder; Anthropic has no minimal and no None; Gemini stops at high.
    @Test(arguments: vendorLadders)
    func aVendorOffersOnlyTheLevelsItDefines(_ ladder: VendorLadder) {
        var connection = AIConnection(provider: ladder.provider, models: ["m"])
        connection.declareLevels(ladder.declared, for: "m")
        #expect(connection.reasoningOptions(for: "m")?.efforts == ladder.offered)
    }

    @Test func aDeclaredNoneIsSentToAVendorThatDefinesIt() {
        var gemini = AIConnection(provider: .gemini, models: ["m"])
        gemini.declareLevels(["xhigh", "high", "none"], for: "m")
        #expect(gemini.offeredEffort("none", for: "m") == "none")
    }

    @Test func responsesCarriesTheEffortInItsReasoningObject() {
        let body = EffortFixtures.vendorBody(.openAI, effort: "high")
        #expect((body["reasoning"] as? [String: String])?["effort"] == "high")
    }

    @Test func anthropicCarriesTheEffortInOutputConfig() {
        let body = EffortFixtures.vendorBody(.anthropic, effort: "max")
        #expect((body["output_config"] as? [String: String])?["effort"] == "max")
    }

    @Test func aVendorsNoneIsItsOwnReasoningEffortNeverTheGatewaySwitch() {
        let body = EffortFixtures.vendorBody(.gemini, effort: "none")
        #expect(body["reasoning_effort"] as? String == "none")
        #expect(body["thinking"] == nil)
    }

    @Test(arguments: [
        (AIProviderKind.openAI, "reasoning"), (.anthropic, "output_config"), (.gemini, "reasoning_effort")
    ])
    func defaultSendsNoEffortFieldOnAnyVendor(_ provider: AIProviderKind, _ field: String) {
        #expect(EffortFixtures.vendorBody(provider, effort: "default")[field] == nil)
    }

    // MARK: Anthropic's catalog

    @Test func anthropicsCatalogNamesEachModelsEffortsAndCeiling() throws {
        let models = try AIModelDiscovery.decode(EffortFixtures.anthropicCatalog, shape: .openAI)
        try #require(models.count == 2)
        #expect(
            models[0].reasoningOptions?.efforts == ["low", "max"],
            "a model's supported efforts come in ladder order")
        #expect(models[1].reasoningOptions?.efforts == [], "a model without effort support names none")
        #expect(models.map(\.maxOutputTokens) == [128_000, nil], "each output ceiling where it states one")
    }

    @Test func adoptingACatalogFillsWhatTheReaderNeverDeclared() throws {
        let models = try AIModelDiscovery.decode(EffortFixtures.anthropicCatalog, shape: .openAI)
        var saved = AIConnection(provider: .anthropic, models: ["claude-a", "claude-b", "claude-c"])
        saved.declareLevels(["high"], for: "claude-c")
        saved.adoptCatalog(
            models + [.init(id: "claude-c", name: "C", reasoningOptions: .init(efforts: ["low"], defaultEffort: nil))])
        #expect(
            saved.declaredLevels(for: "claude-a") == ["low", "max"],
            "a model saved before its catalog was read takes the catalog's levels")
        #expect(saved.reasoningOptions?["claude-b"] == nil, "a model with no effort support takes none")
        #expect(saved.declaredLevels(for: "claude-c") == ["high"], "a reader's own declaration stays")
        #expect(saved.outputLimits == ["claude-a": 128_000], "only a stated ceiling is stored")
    }

    @Test func aKnownClaudeModelMayAnswerUpToItsCeiling() {
        let body = EffortFixtures.body(
            AIHTTPConfiguration(
                provider: .anthropic, baseURL: EffortFixtures.anthropicURL, model: "claude-a",
                maxOutputTokens: 128_000))
        #expect(body["max_tokens"] as? Int == 128_000)
    }

    @Test func anUnknownClaudeModelKeepsTheCapEveryModelAccepts() {
        let body = EffortFixtures.body(
            AIHTTPConfiguration(provider: .anthropic, baseURL: EffortFixtures.anthropicURL, model: "x"))
        #expect(body["max_tokens"] as? Int == AIRequest.defaultMaxOutputTokens)
    }
}

private enum EffortFixtures {
    static let gateway = "https://gateway.example/v1"
    static let gatewayURL = URL(string: gateway)!
    static let anthropicURL = URL(string: AIProviderKind.anthropic.defaultBaseURL)!
    static let turn = AIRequest(messages: [AIMessage(role: .user, text: "hi")])

    static let declaredGateway: AIConnection = {
        var connection = AIConnection(provider: .openAI, baseURL: gateway, models: ["m"])
        connection.declareLevels(["low", "high"], for: "m")
        return connection
    }()

    static let openRouter = AIConnection(
        id: UUID(), provider: .openRouter, models: ["m"],
        reasoningOptions: ["m": .init(efforts: ["high", "low"], defaultEffort: "high")])

    static let anthropicCatalog = Data(
        """
        {"data":[
            {"id":"claude-a","display_name":"Claude A","max_tokens":128000,"capabilities":{
                "effort":{"supported":true,"max":{"supported":true},
                          "low":{"supported":true},"xhigh":{"supported":false}}}},
            {"id":"claude-b","capabilities":{"effort":{"supported":false}}}
        ]}
        """.utf8)

    static func body(_ configuration: AIHTTPConfiguration) -> [String: Any] {
        AIRequestBody.make(turn, configuration: configuration)
    }

    static func vendorBody(_ provider: AIProviderKind, effort: String?) -> [String: Any] {
        body(
            AIHTTPConfiguration(
                provider: provider, baseURL: URL(string: provider.defaultBaseURL)!, model: "m",
                effort: effort))
    }
}
