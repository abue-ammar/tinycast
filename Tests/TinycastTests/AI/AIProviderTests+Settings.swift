import Foundation
import Synchronization
import Testing

@testable import Tinycast

extension AIProviderTests {
    // MARK: Conversations

    struct OpenCase: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let opensTo: AIOpensTo
        let after: AINewChatAfter
        /// Seconds since the conversation was last active; `nil` when there is none to resume.
        let idle: TimeInterval?
        let decision: AIConversationOpenPolicy.Decision
    }

    static let openCases: [OpenCase] = [
        OpenCase(
            testDescription: "A New Conversation always starts fresh",
            opensTo: .newConversation, after: .never, idle: 0, decision: .startNew),
        OpenCase(
            testDescription: "Never means no amount of idling starts a new chat",
            opensTo: .recent, after: .never, idle: 400 * 86_400, decision: .resume),
        OpenCase(
            testDescription: "nothing to resume is new",
            opensTo: .recent, after: .fiveMinutes, idle: nil, decision: .startNew),
        OpenCase(
            testDescription: "inside the window the conversation resumes",
            opensTo: .recent, after: .fiveMinutes, idle: 299, decision: .resume),
        OpenCase(
            testDescription: "past the window the next summon starts fresh",
            opensTo: .recent, after: .fiveMinutes, idle: 301, decision: .startNew),
        OpenCase(
            testDescription: "the boundary itself starts fresh, so the window is exclusive at its end",
            opensTo: .recent, after: .fiveMinutes, idle: 300, decision: .startNew),
        // A backwards clock yields a negative interval; it must not strand a reader in a chat.
        OpenCase(
            testDescription: "a clock that moved backwards resumes rather than misreading the idle time",
            opensTo: .recent, after: .twoMinutes, idle: -3_600, decision: .resume)
    ]

    @Test(arguments: openCases)
    func theOpenPolicyDecidesFromTheIdleTime(_ open: OpenCase) {
        let now = SettingsFixtures.now
        let decision = AIConversationOpenPolicy.decide(
            opensTo: open.opensTo, newAfter: open.after,
            lastActiveAt: open.idle.map { now.addingTimeInterval(-$0) }, now: now)
        #expect(decision == open.decision)
    }

    @Test(arguments: AIRetention.allCases)
    func everyRetentionNamesItself(_ retention: AIRetention) {
        #expect(!retention.title.isEmpty)
    }

    @Test func aWeeksCutoffIsSevenDaysBack() {
        let now = SettingsFixtures.now
        #expect(AIRetention.week.cutoff(from: now) == now.addingTimeInterval(-7 * 86_400))
    }

    /// An unset key reads as 0, which would swallow a timeout before the default applied.
    @Test(arguments: AINewChatAfter.allCases)
    func noNewChatTimeoutUsesZero(_ after: AINewChatAfter) {
        #expect(after.rawValue != 0)
    }

    @MainActor
    @Test func conversationSettingsStartFromTheirDefaults() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let fresh = AISettingsStore(defaults: scratch.defaults)
        #expect(fresh.retention == .forever, "retention defaults to Forever, so upgrading deletes nothing")
        #expect(fresh.opensTo == .recent, "chat reopens on the recent conversation by default")
        #expect(fresh.newChatAfter == .fiveMinutes, "the idle window defaults to five minutes")
        #expect(fresh.toolRounds == .twentyFive, "a reply's tool rounds default to 25")
        #expect(!fresh.expandsReasoning, "thinking starts folded by default")
    }

    @MainActor
    @Test func conversationSettingsSurviveARestart() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        store.retention = .week
        store.opensTo = .newConversation
        store.newChatAfter = .never
        store.toolRounds = .fifty
        store.expandsReasoning = true

        let reopened = AISettingsStore(defaults: scratch.defaults)
        #expect(reopened.toolRounds == .fifty, "the tool round cap persists")
        #expect(reopened.retention == .week)
        #expect(reopened.opensTo == .newConversation)
        #expect(reopened.newChatAfter == .never, "Never persists rather than reading as the default")
        #expect(reopened.expandsReasoning)
    }

    @MainActor
    @Test func unlimitedToolRoundsSurviveARestart() throws {
        let scratch = try ScratchDefaults("ai-settings")
        AISettingsStore(defaults: scratch.defaults).toolRounds = .unlimited
        #expect(AISettingsStore(defaults: scratch.defaults).toolRounds == .unlimited)
    }

    @Test func aToolRoundStepHandsTheLoopItsOwnCapAndUnlimitedNone() {
        #expect(AIToolRounds.unlimited.limit == nil)
        #expect(AIToolRounds.fifty.limit == 50)
    }

    /// A 0 is neither a step nor Unlimited, and 7 is no step at all.
    @MainActor
    @Test(arguments: [7, 0])
    func aStoredToolRoundCapNoCaseCarriesReadsAsTheDefault(_ stored: Int) throws {
        let scratch = try ScratchDefaults("ai-settings")
        scratch.defaults.set(stored, forKey: AppSettingsKey.aiToolRounds.rawValue)
        #expect(AISettingsStore(defaults: scratch.defaults).toolRounds == .twentyFive)
    }

    // MARK: On-device selections

    @Test func theOnDeviceSelectionRoundTripsAndNamesItself() throws {
        let encoded = try JSONEncoder().encode(AIModelSelection.appleIntelligence)
        #expect(try JSONDecoder().decode(AIModelSelection.self, from: encoded) == .appleIntelligence)
        #expect(AIModelSelection.appleIntelligence.model == AppleIntelligence.modelID)
        #expect(AIModelSelection.appleIntelligence.source == .appleIntelligence)
        #expect(AIModelSelection.appleIntelligence.isOnDevice)
        #expect(!AIModelSelection.codex(model: "gpt-5", effort: nil).isOnDevice)
    }

    @Test func theOldChatGPTSelectionMigratesToTheInstalledCodexRoute() throws {
        let legacy = Data(#"{"chatGPT":{"model":"gpt-5","effort":"high"}}"#.utf8)
        let decoded = try JSONDecoder().decode(AIModelSelection.self, from: legacy)
        #expect(decoded == .codex(model: "gpt-5", effort: "high"))
    }

    @MainActor
    @Test func theOnDeviceRouteIsTheDefaultOnAnUnconfiguredMac() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults, isAppleIntelligenceAvailable: { true })
        #expect(store.defaultModel == .appleIntelligence)
    }

    /// A configured connection must not be displaced by resolution running a second time.
    @MainActor
    @Test func resolutionNeverOverridesASelectionTheReaderMade() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults, isAppleIntelligenceAvailable: { true })
        let connectionID = SettingsFixtures.chooseLocalConnection(in: store)
        store.resolveDefaultModel()
        #expect(store.defaultModel == .api(connection: connectionID, model: "m", effort: nil))
    }

    @MainActor
    @Test func aRemovedConnectionFallsForwardToTheOnDeviceRoute() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults, isAppleIntelligenceAvailable: { true })
        store.removeConnection(id: SettingsFixtures.chooseLocalConnection(in: store))
        #expect(store.defaultModel == .appleIntelligence)
    }

    @MainActor
    @Test func anUnavailableModelDoesNotSilentlyRerouteAStoredOnDeviceSelection() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults, isAppleIntelligenceAvailable: { true })
        store.removeConnection(id: SettingsFixtures.chooseLocalConnection(in: store))
        let without = AISettingsStore(defaults: scratch.defaults, isAppleIntelligenceAvailable: { false })
        without.resolveDefaultModel()
        #expect(without.defaultModel == .appleIntelligence)
    }

    // MARK: Connections

    @MainActor
    @Test func savedConnectionsAreNormalizedAndTheFirstModelLeads() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        let (firstID, _) = SettingsFixtures.saveTwoConnections(in: store)
        #expect(store.connections.first?.name == "Work", "connection names are normalized")
        #expect(
            store.connections.first?.models == ["model-a", "model-b"], "models are trimmed and deduplicated")
        #expect(store.defaultModel == .api(connection: firstID, model: "model-a", effort: nil))
    }

    @MainActor
    @Test func connectionsAndTheDefaultModelSurviveARestart() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        let (firstID, _) = SettingsFixtures.saveTwoConnections(in: store)
        store.select(.api(connection: firstID, model: "model-b", effort: "low"))
        let reopened = AISettingsStore(defaults: scratch.defaults)
        #expect(reopened.connections == store.connections)
        #expect(reopened.defaultModel == store.defaultModel)
    }

    @MainActor
    @Test func removingTheDefaultConnectionFallsForwardToAnotherAPIModel() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        let (firstID, secondID) = SettingsFixtures.saveTwoConnections(in: store)
        store.select(.api(connection: firstID, model: "model-b", effort: "low"))
        let reopened = AISettingsStore(defaults: scratch.defaults)
        reopened.removeConnection(id: firstID)
        #expect(reopened.defaultModel == .api(connection: secondID, model: "gemini-model", effort: nil))
    }

    // MARK: Installed providers

    @MainActor
    @Test func installedProvidersAreDisabledByDefault() throws {
        let scratch = try ScratchDefaults("ai-settings")
        #expect(AISettingsStore(defaults: scratch.defaults).enabledInstalledProviders.isEmpty)
    }

    @MainActor
    @Test func anInstalledProviderToggleSurvivesARestart() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        store.setInstalledProviderEnabled(true, for: .claude)
        store.setInstalledProviderEnabled(false, for: .openCode)
        let reopened = AISettingsStore(defaults: scratch.defaults)
        #expect(reopened.enabledInstalledProviders == [.claude])
        #expect(!reopened.enabledInstalledProviders.contains(.openCode))
    }

    @MainActor
    @Test func aCommandPathIsKeptTrimmedAndCountsOnceAsALaunchChange() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults, environmentStore: KeptVariables().store)
        #expect(store.launch(for: .codex) == InstalledAILaunch(), "a tool left alone has no override")
        store.setCommandPath("  ~/bin/codex \n", for: .codex)
        #expect(store.override(for: .codex).commandPath == "~/bin/codex")
        #expect(store.launchRevisions[.codex] == 1, "setting it counts as a change to the launch")
        store.setCommandPath("~/bin/codex", for: .codex)
        #expect(store.launchRevisions[.codex] == 1, "the same path again is no change")
    }

    @MainActor
    @Test func variablesKeepTheirOrderAndNoValueReachesSettings() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults, environmentStore: KeptVariables().store)
        try SettingsFixtures.overrideCodex(in: store)
        #expect(
            store.override(for: .codex).environmentNames == ["HTTPS_PROXY", "CODEX_HOME"],
            "without a repeated or an unusable name")
        let stored = try #require(scratch.defaults.data(forKey: AppSettingsKey.aiInstalledOverrides.rawValue))
        #expect(String(bytes: stored, encoding: .utf8)?.contains("127.0.0.1") == false)
    }

    @MainActor
    @Test func aLaunchAfterARestartHasThePathAndTheValuesInTheirOrder() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let kept = KeptVariables()
        try SettingsFixtures.overrideCodex(
            in: AISettingsStore(defaults: scratch.defaults, environmentStore: kept.store))
        let reopened = AISettingsStore(defaults: scratch.defaults, environmentStore: kept.store)
        #expect(
            reopened.launch(for: .codex)
                == InstalledAILaunch(
                    commandPath: "~/bin/codex",
                    environment: ["HTTPS_PROXY": "http://127.0.0.1:9", "CODEX_HOME": "/tmp/home"]))
        #expect(try reopened.environment(for: .codex).map(\.name) == ["HTTPS_PROXY", "CODEX_HOME"])
    }

    @MainActor
    @Test func clearingThePathAndTheVariablesLeavesNothingStored() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let kept = KeptVariables()
        try SettingsFixtures.overrideCodex(
            in: AISettingsStore(defaults: scratch.defaults, environmentStore: kept.store))
        let reopened = AISettingsStore(defaults: scratch.defaults, environmentStore: kept.store)
        reopened.setCommandPath("", for: .codex)
        try reopened.setEnvironment([], for: .codex)
        #expect(scratch.defaults.object(forKey: AppSettingsKey.aiInstalledOverrides.rawValue) == nil)
        #expect(kept[.codex]?.isEmpty == true)
    }

    struct CommandCase: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let path: String
        /// Otherwise only `~/bin/codex` is runnable.
        let everythingRuns: Bool
        let command: InstalledAILaunch.Command
    }

    static let commandCases: [CommandCase] = [
        CommandCase(
            testDescription: "no path looks up", path: "", everythingRuns: false, command: .automatic),
        CommandCase(
            testDescription: "a path under the home folder may be written with a tilde",
            path: "~/bin/codex", everythingRuns: false,
            command: .executable(URL(filePath: NSHomeDirectory() + "/bin/codex"))),
        CommandCase(
            testDescription: "a path with nothing to run is reported, never replaced by a lookup",
            path: "/opt/none/codex", everythingRuns: false, command: .missing(path: "/opt/none/codex")),
        CommandCase(
            testDescription: "a bare name is not a path",
            path: "codex", everythingRuns: true, command: .missing(path: "codex"))
    ]

    @Test(arguments: commandCases)
    func aCommandPathResolvesToWhatItNames(_ command: CommandCase) {
        let runnable = NSHomeDirectory() + "/bin/codex"
        let everythingRuns = command.everythingRuns
        let resolved = InstalledAILaunch(commandPath: command.path)
            .command(isExecutable: { everythingRuns || $0 == runnable })
        #expect(resolved == command.command)
    }

    // MARK: Unreadable Keychain

    @MainActor
    @Test func aFailedKeychainReadIsAnErrorNeverNamesWithoutValues() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = try SettingsFixtures.lockedClaudeStore(scratch.defaults, kept: KeptVariables())
        #expect(throws: (any Error).self) { try store.environment(for: .claude) }
    }

    @MainActor
    @Test func savingOverValuesThatCouldNotBeReadFailsAndKeepsThem() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let kept = KeptVariables()
        let store = try SettingsFixtures.lockedClaudeStore(scratch.defaults, kept: kept)
        #expect(throws: (any Error).self) {
            try store.setEnvironment([InstalledAIVariable(name: "HTTPS_PROXY", value: "")], for: .claude)
        }
        #expect(kept[.claude] == ["HTTPS_PROXY": "http://127.0.0.1:9"])
    }

    @MainActor
    @Test func aLaunchThatCannotReadTheValuesStartsWithoutThem() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = try SettingsFixtures.lockedClaudeStore(scratch.defaults, kept: KeptVariables())
        #expect(store.launch(for: .claude).environment.isEmpty)
    }

    // MARK: Inherited variables

    @Test func theReadersVariablesLieOverTheAppsOwn() {
        let inherited = SettingsFixtures.readerLaunch.inherited(
            for: .openCode, base: SettingsFixtures.appEnvironment)
        #expect(inherited["PATH"] == "/reader/bin")
        #expect(inherited["HTTPS_PROXY"] == "proxy")
        #expect(inherited["HOME"] == "/Users/reader")
    }

    @Test func aLaunchNeverTakesAVariableTinycastSetsOrOneThatIsNoName() {
        let inherited = SettingsFixtures.readerLaunch.inherited(
            for: .openCode, base: SettingsFixtures.appEnvironment)
        #expect(inherited["OPENCODE_CONFIG_CONTENT"] == nil)
        #expect(inherited["TC_MCP_0_0"] == nil)
        #expect(inherited["NO_COLOR"] == "1")
        #expect(inherited["1BAD"] == nil)
    }

    @Test func aNameOnlyAnotherToolReservesIsAnOrdinaryVariable() {
        let inherited = SettingsFixtures.readerLaunch.inherited(for: .claude, base: [:])
        #expect(inherited["OPENCODE_CONFIG_CONTENT"] == "{}")
    }

    @Test(arguments: InstalledAIKind.allCases)
    func everyVariableAToolLaunchesWithIsOneTheReaderCannotReplace(_ kind: InstalledAIKind) {
        #expect(kind.managedEnvironment.keys.allSatisfy(kind.isManagedVariable))
    }

    // MARK: Routes

    @MainActor
    @Test func switchingTheDefaultsConnectionOffMovesTheDefaultToOneStillOn() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        let (first, second) = SettingsFixtures.saveRouteConnections(in: store)
        #expect(store.defaultModel?.source == .api(first.id))
        store.setRoute(.api(first.id), enabled: false)
        #expect(store.defaultModel?.source == .api(second.id))
    }

    @MainActor
    @Test func aSwitchedOffRouteStaysOffAfterARestart() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        let (first, second) = SettingsFixtures.saveRouteConnections(in: store)
        store.setRoute(.api(first.id), enabled: false)
        let reopened = AISettingsStore(defaults: scratch.defaults)
        #expect(!reopened.isRouteEnabled(.api(first.id)))
        #expect(reopened.isRouteEnabled(.api(second.id)))
        reopened.setRoute(.appleIntelligence, enabled: false)
        #expect(
            !reopened.isRouteEnabled(.appleIntelligence), "the on-device model switches off like a connection"
        )
    }

    @MainActor
    @Test func aConnectionSwitchedBackOnLeadsOnceTheOtherIsGoneAndForgetsBeingOff() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        let (first, second) = SettingsFixtures.saveRouteConnections(in: store)
        store.setRoute(.api(first.id), enabled: false)
        let reopened = AISettingsStore(defaults: scratch.defaults)
        reopened.setRoute(.appleIntelligence, enabled: false)
        reopened.setRoute(.api(first.id), enabled: true)
        reopened.removeConnection(id: second.id)
        #expect(reopened.defaultModel?.source == .api(first.id))
        reopened.removeConnection(id: first.id)
        #expect(
            !reopened.disabledRoutes.contains(AIModelSource.api(first.id).storageKey),
            "removing a connection forgets that it was switched off")
    }

    // MARK: Shown models

    @MainActor
    @Test func aRouteNobodyHasTrimmedListsEveryModel() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        #expect(SettingsFixtures.available.allSatisfy { store.isModelShown($0, in: .openCode) })
    }

    @MainActor
    @Test func anUntickedModelStaysOutOfThatRoutesPickerAfterARestart() throws {
        let scratch = try ScratchDefaults("ai-settings")
        AISettingsStore(defaults: scratch.defaults)
            .setModel("b", shown: false, in: .openCode, available: SettingsFixtures.available)
        let reopened = AISettingsStore(defaults: scratch.defaults)
        #expect(reopened.isModelShown("a", in: .openCode))
        #expect(!reopened.isModelShown("b", in: .openCode))
        #expect(
            !reopened.isModelShown("d", in: .openCode), "a trimmed route does not list a model it adds later")
        #expect(
            reopened.isModelShown("b", in: .claude), "trimming one route leaves the others listing everything"
        )
    }

    @MainActor
    @Test func tickingEveryModelBackListsAllAgainAndHideAllListsNone() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        let available = SettingsFixtures.available
        store.setModel("b", shown: false, in: .openCode, available: available)
        store.setModel("b", shown: true, in: .openCode, available: available)
        #expect(store.shownModels[AIModelSource.openCode.storageKey] == nil)
        #expect(store.isModelShown("d", in: .openCode), "later models included")
        store.hideAllModels(in: .openCode)
        #expect(available.allSatisfy { !store.isModelShown($0, in: .openCode) })
    }

    @MainActor
    @Test func removingAConnectionForgetsWhichOfItsModelsWereShown() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        let connection = AIConnection(provider: .openRouter, models: ["x", "y"])
        store.save(connection)
        store.setModel("y", shown: false, in: .api(connection.id), available: connection.models)
        store.removeConnection(id: connection.id)
        #expect(store.shownModels[AIModelSource.api(connection.id).storageKey] == nil)
    }

    // MARK: Subscriptions

    @MainActor
    @Test func aCodexSelectionReconcilesWithItsCatalog() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        let model = ChatGPTSubscription.Model(
            id: "gpt", name: "GPT",
            efforts: [.init(id: "low", detail: nil), .init(id: "high", detail: nil)],
            defaultEffort: "high", isDefault: true)
        store.select(.codex(model: "gpt", effort: "missing"))
        store.reconcile(codexModels: [model], isUnavailable: false)
        #expect(
            store.defaultModel == .codex(model: "gpt", effort: "high"),
            "a removed reasoning tier falls back to the model default")
        store.reconcile(codexModels: [], isUnavailable: true)
        #expect(store.defaultModel == nil, "signing out clears an unusable Codex default")
    }

    @MainActor
    @Test func aClaudeSelectionReconcilesWithItsCatalog() throws {
        let scratch = try ScratchDefaults("ai-settings")
        let store = AISettingsStore(defaults: scratch.defaults)
        store.select(.claude(model: "removed", effort: nil))
        store.reconcile(
            installed: .claude, models: [InstalledAIModel(id: "sonnet", name: "Claude Sonnet")],
            isUnavailable: false)
        #expect(
            store.defaultModel == .claude(model: "sonnet", effort: nil),
            "an installed catalog replaces a model alias that disappeared")
        store.reconcile(installed: .claude, models: [], isUnavailable: true)
        #expect(store.defaultModel == nil, "signing out clears an unusable Claude default")
    }
}

private enum SettingsFixtures {
    static let now = Date(timeIntervalSince1970: 1_000_000)
    static let available = ["a", "b", "c"]

    static let readerLaunch = InstalledAILaunch(
        environment: [
            "PATH": "/reader/bin", "HTTPS_PROXY": "proxy", "NO_COLOR": "0",
            "OPENCODE_CONFIG_CONTENT": "{}", "TC_MCP_0_0": "stolen", "1BAD": "x"
        ])
    static let appEnvironment = ["PATH": "/usr/bin", "HOME": "/Users/reader", "NO_COLOR": "1"]

    /// Saves a one-model connection and makes it the reader's choice.
    @MainActor
    static func chooseLocalConnection(in store: AISettingsStore) -> UUID {
        let id = UUID()
        store.save(AIConnection(id: id, name: "Local", models: ["m"]))
        store.select(.api(connection: id, model: "m", effort: nil))
        return id
    }

    @MainActor
    static func saveTwoConnections(in store: AISettingsStore) -> (first: UUID, second: UUID) {
        let firstID = UUID()
        let secondID = UUID()
        var first = AIConnection(
            id: firstID, name: "  Work  ", provider: .openRouter,
            models: [" model-a ", "model-a", "model-b"],
            reasoningOptions: ["model-b": .init(efforts: ["medium", "low"], defaultEffort: "medium")])
        first.baseURL = " https://openrouter.ai/api/v1 "
        store.save(first)
        store.save(AIConnection(id: secondID, provider: .gemini, models: ["gemini-model"]))
        return (firstID, secondID)
    }

    @MainActor
    static func saveRouteConnections(in store: AISettingsStore) -> (first: AIConnection, second: AIConnection)
    {
        let first = AIConnection(provider: .openRouter, models: ["first-model"])
        let second = AIConnection(provider: .gemini, models: ["second-model"])
        store.save(first)
        store.save(second)
        return (first, second)
    }

    /// A path, plus variables with a repeat and an unusable name the store must drop.
    @MainActor
    static func overrideCodex(in store: AISettingsStore) throws {
        store.setCommandPath("  ~/bin/codex \n", for: .codex)
        try store.setEnvironment(
            [
                InstalledAIVariable(name: "HTTPS_PROXY", value: "http://127.0.0.1:9"),
                InstalledAIVariable(name: "HTTPS_PROXY", value: "a second one"),
                InstalledAIVariable(name: "not a name", value: "x"),
                InstalledAIVariable(name: "CODEX_HOME", value: "/tmp/home")
            ], for: .codex)
    }

    /// Claude's proxy is saved through a working Keychain, then read through one that fails.
    @MainActor
    static func lockedClaudeStore(_ defaults: UserDefaults, kept: KeptVariables) throws -> AISettingsStore {
        try AISettingsStore(defaults: defaults, environmentStore: kept.store).setEnvironment(
            [InstalledAIVariable(name: "HTTPS_PROXY", value: "http://127.0.0.1:9")], for: .claude)
        return AISettingsStore(defaults: defaults, environmentStore: kept.lockedStore)
    }
}

/// Stands in for the Keychain: what a test saved, read back the way a launch would.
private final class KeptVariables: Sendable {
    private let values = Mutex<[InstalledAIKind: [String: String]]>([:])

    subscript(kind: InstalledAIKind) -> [String: String]? {
        values.withLock { $0[kind] }
    }

    var store: InstalledAIEnvironmentStore {
        InstalledAIEnvironmentStore(
            values: { kind in self.values.withLock { $0[kind] ?? [:] } },
            save: { saved, kind in self.values.withLock { $0[kind] = saved } })
    }

    /// Saves like `store`, but every read fails the way a locked Keychain does.
    var lockedStore: InstalledAIEnvironmentStore {
        InstalledAIEnvironmentStore(
            values: { _ in throw KeychainUnreadable() },
            save: { saved, kind in self.values.withLock { $0[kind] = saved } })
    }

    private struct KeychainUnreadable: Error {}
}
