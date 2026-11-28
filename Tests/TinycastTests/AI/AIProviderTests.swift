import Foundation
import Testing

@testable import Tinycast

struct AIProviderTests {
    static let cloud = AIModelSelection.codex(model: "gpt-5", effort: nil)

    // MARK: Instructions

    @Test(arguments: [nil, "", "   \n\t "] as [String?])
    func aBlankUserPromptWithChoicesOffSendsThePreambleAlone(_ prompt: String?) {
        let composed = AIInstructions.compose(
            userPrompt: prompt, isEnabled: true, offersChoices: false, model: Self.cloud)
        #expect(composed == AIPreamble.text)
    }

    @Test func instructionsPutThePreambleAndChoicesBeforeTheTrimmedUserPrompt() {
        let composed = AIInstructions.compose(
            userPrompt: "  Answer only in haiku.  ", isEnabled: true, offersChoices: true,
            model: Self.cloud)
        #expect(composed == AIPreamble.text + "\n\n" + AIPreamble.choices + "\n\nAnswer only in haiku.")
    }

    @Test(arguments: [nil, "Answer only in haiku."] as [String?])
    func disabledInstructionsWithholdEverything(_ prompt: String?) {
        let composed = AIInstructions.compose(
            userPrompt: prompt, isEnabled: false, offersChoices: true, model: Self.cloud)
        #expect(composed == nil, "disabled instructions withhold the preamble, choices and prompt")
    }

    @Test(arguments: [nil, "Answer only in haiku."] as [String?])
    func theOnDeviceModelGetsNoInstructions(_ prompt: String?) {
        let composed = AIInstructions.compose(
            userPrompt: prompt, isEnabled: true, offersChoices: true, model: .appleIntelligence)
        #expect(composed == nil, "the on-device model gets no preamble, choices or user prompt")
    }

    @Test func thePreambleStaysWithinItsPerTurnBudget() {
        #expect((AIPreamble.text + AIPreamble.choices).count < 1_800)
    }

    // MARK: Presets

    @Test func aPresetsTextFollowsThePreambleInPlaceOfTheUserPrompt() {
        let composed = AIInstructions.compose(
            presetInstructions: " Review for SEO. ", preambleEnabled: true, offersChoices: false,
            model: Self.cloud)
        #expect(composed == AIPreamble.text + "\n\nReview for SEO.")
    }

    @Test func withTheSystemPromptOffAPresetStillRidesAlone() {
        let composed = AIInstructions.compose(
            presetInstructions: "Review for SEO.", preambleEnabled: false, offersChoices: true,
            model: Self.cloud)
        #expect(composed == "Review for SEO.")
    }

    @Test func theOnDeviceModelGetsNoPreset() {
        let composed = AIInstructions.compose(
            presetInstructions: "Review for SEO.", preambleEnabled: true, offersChoices: true,
            model: .appleIntelligence)
        #expect(composed == nil)
    }

    @MainActor
    @Test func aPresetWithABlankNameOrBlankInstructionsIsRefused() throws {
        let scratch = try ScratchDirectory("presets")
        let store = ChatPresetStore(directory: scratch.url)
        #expect(throws: ChatPresetError.emptyName) {
            try store.add(ChatPreset(name: " ", instructions: "Review."))
        }
        #expect(throws: ChatPresetError.emptyInstructions) {
            try store.add(ChatPreset(name: "SEO", instructions: " \n"))
        }
    }

    @MainActor
    @Test func aSavedPresetIsTrimmedAndSurvivesARelaunchUntilDeleted() throws {
        let scratch = try ScratchDirectory("presets")
        let store = ChatPresetStore(directory: scratch.url)
        let saved = try store.add(ChatPreset(name: "  SEO  ", iconSymbol: " ", instructions: " Review. "))
        #expect(saved.name == "SEO")
        #expect(saved.iconSymbol == nil)
        #expect(saved.instructions == "Review.")

        let reopened = ChatPresetStore(directory: scratch.url)
        reopened.load()
        #expect(reopened.presets == store.presets, "presets survive a relaunch")

        try store.remove(id: saved.id)
        let afterDelete = ChatPresetStore(directory: scratch.url)
        afterDelete.load()
        #expect(afterDelete.presets.isEmpty, "a deleted preset stays deleted")
    }

    @MainActor
    @Test func anUnreadablePresetFileIsReportedNeverWrittenOver() throws {
        let scratch = try ScratchDirectory("presets")
        let file = scratch.url.appending(path: "chat-presets.json")
        try Data("not json".utf8).write(to: file)
        let store = ChatPresetStore(directory: scratch.url)
        store.load()
        #expect(!store.isAvailable)
        #expect(throws: ChatPresetError.storageUnavailable) {
            try store.add(ChatPreset(name: "SEO", instructions: "Review."))
        }
        #expect(try Data(contentsOf: file) == Data("not json".utf8))
    }

    // MARK: Documents

    static let pdf = AIDocument(data: Data("%PDF-1.4".utf8), mimeType: "application/pdf", name: "report.pdf")
    static let documentTurn = AIRequest(
        messages: [
            AIMessage(
                role: .user, text: "summarise",
                images: [AIImage(data: Data([0x89, 0x50]), mimeType: "image/png")], documents: [pdf])
        ])

    /// A wrong document shape must fail here rather than mid-conversation.
    @Test func anthropicTakesTheImageThenTheDocumentAsBase64WithTheTextLast() throws {
        let body = AIRequestBody.make(
            Self.documentTurn,
            configuration: AIHTTPConfiguration(
                provider: .anthropic, baseURL: URL(string: "https://api.anthropic.com")!, model: "claude"))
        let blocks = try #require(firstMessageParts(of: body))
        #expect(blocks.map { $0["type"] as? String } == ["image", "document", "text"])
        let document = try #require(blocks.first { $0["type"] as? String == "document" })
        let source = try #require(document["source"] as? [String: Any])
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "application/pdf")
        let data = try #require(source["data"] as? String)
        #expect(!data.contains("\n"), "the base64 carries no newlines")
    }

    @Test func openAIKeepsItsTextFirstAndAppendsTheDocumentAsADataURLFile() throws {
        let body = AIRequestBody.make(
            Self.documentTurn,
            configuration: AIHTTPConfiguration(
                provider: .openAICompatible, baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt"))
        let parts = try #require(firstMessageParts(of: body))
        #expect(parts.map { $0["type"] as? String } == ["text", "image_url", "file"])
        let part = try #require(parts.first { $0["type"] as? String == "file" })
        let file = try #require(part["file"] as? [String: Any])
        #expect(file["filename"] as? String == "report.pdf")
        let data = try #require(file["file_data"] as? String)
        #expect(data.hasPrefix("data:application/pdf;base64,"))
    }

    /// A turn that is only a document must not collapse to the plain-string fast path.
    @Test func aDocumentOnlyTurnStillSendsAsContentParts() throws {
        let body = AIRequestBody.make(
            AIRequest(messages: [AIMessage(role: .user, text: "", documents: [Self.pdf])]),
            configuration: AIHTTPConfiguration(
                provider: .openAICompatible, baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt"))
        let parts = try #require(firstMessageParts(of: body))
        #expect(parts.count == 1)
    }

    // MARK: Brands

    static let brands: [(model: String, brand: AIBrand?)] = [
        ("openai/gpt-oss-20b", .openAI), ("o4-mini", .openAI), ("o3", .openAI),
        ("anthropic/claude-sonnet-4", .claude), ("google/gemma-3-27b-it", .gemini),
        ("x-ai/grok-4", .x), ("deepseek/deepseek-r1", .deepSeek), ("qwen/qwq-32b", .qwen),
        ("mistralai/codestral-2501", .mistral), ("meta-llama/llama-3.3-70b", .meta),
        ("moonshotai/kimi-k2", .kimi), ("minimax/minimax-m1", .miniMax),
        ("perplexity/sonar-pro", .perplexity), ("z-ai/glm-4.5", .zai),
        ("openrouter/auto", .openRouter), ("cohere/command-r", nil), ("o10", nil)
    ]

    @Test(arguments: brands)
    func aModelIDResolvesToItsBrand(_ model: String, _ brand: AIBrand?) {
        #expect(AIBrand.resolve(model: model) == brand)
    }

    @Test func aVendorEndpointNamesItsBrandRegardlessOfTheModelID() {
        #expect(AIBrand.resolve(provider: .anthropic, model: "whatever") == .claude)
    }

    @Test func aCompatibleEndpointResolvesTheBrandFromTheModelID() {
        #expect(AIBrand.resolve(provider: .openAICompatible, model: "deepseek-chat") == .deepSeek)
    }
}

/// The content parts of a request body's first message.
private func firstMessageParts(of body: [String: Any]) -> [[String: Any]]? {
    (body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
}
