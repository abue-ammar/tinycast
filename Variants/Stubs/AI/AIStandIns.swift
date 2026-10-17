import SwiftUI

private let aiFeature = "AI"
private let quickActionsFeature = "Quick Actions"

// MARK: - Providers

protocol AIProvider: Sendable {}

/// In place of `SystemLanguageModel.Guardrails`, so FoundationModels stays unlinked.
enum ExcludedGuardrails { case permissiveContentTransformations }

enum AIProviderFactory {
    static func make(
        selection: AIModelSelection, settings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager, installedAI: InstalledAIManager,
        guardrails: ExcludedGuardrails
    ) throws -> any AIProvider {
        throw AIProviderError.unavailable(ExcludedFeature.message(aiFeature))
    }
}

enum AppleIntelligenceProvider {
    static func status() -> AppleIntelligenceStatus { .deviceNotEligible }
}

/// `.none`, so a slim build never reads the keychain.
extension InstalledAIEnvironmentStore {
    static var keychain: InstalledAIEnvironmentStore { .none }
}

@MainActor
@Observable
final class ChatGPTSubscriptionManager {
    @ObservationIgnored var launchSettings: () -> InstalledAILaunch = { InstalledAILaunch() }
    private(set) var phase = ChatGPTSubscription.Phase.idle

    @discardableResult
    func refresh() -> Task<Void, Never> { Task {} }
    func currentRefreshTask() -> Task<Void, Never> { Task {} }
    func stop() {}
}

@MainActor
@Observable
final class InstalledAIManager {
    @ObservationIgnored var launchSettings: (InstalledAIKind) -> InstalledAILaunch = { _ in
        InstalledAILaunch()
    }

    @discardableResult
    func refresh(kind: InstalledAIKind) -> Task<Void, Never> { Task {} }
    func ensure(enabledKinds: Set<InstalledAIKind>) -> Task<Void, Never> { Task {} }
    func stop() {}
}

// MARK: - Chats

@MainActor
@Observable
final class ChatHistoryStore {
    init(directory: URL) {}
}

struct ChatAttachment: Identifiable {
    let id: UUID
}

@MainActor
@Observable
final class AIChatState {
    private(set) var pendingAttachments: [ChatAttachment] = []
}

@MainActor
@Observable
final class AIChatSurfacesState {
    let quickAI = AIChatState()
    init(history: ChatHistoryStore) {}
    func reset() {}
}

@MainActor
@Observable
final class AIChatCoordinator {
    private let appIndex: AppIndex
    private let core: AppCore

    init(
        chats: AIChatSurfacesState, settings: AppSettings, appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator, settingsCoordinator: SettingsCoordinator,
        core: AppCore
    ) {
        self.appIndex = appIndex
        self.core = core
    }

    /// Ignores `aiEnabled`, so the commands and their shortcuts stay hidden.
    func applyEnabled() { appIndex.setCommandsVisible([.aiChat, .quickAI], false) }
    func applyRetention() {}
    func toggleWindow() { core.showMessage(ExcludedFeature.message(aiFeature), tone: .danger) }
    func focusExisting() -> Bool { false }
    func closeWindowIfKey() -> Bool { false }
    /// True, so `AppCore` never starts an MCP server for a chat.
    var everyChatRunsItsOwnTools: Bool { true }
    func selectedModelTitle(for chat: AIChatState) -> String { "" }
    func selectedModelIcon(for chat: AIChatState) -> PopoverMenuIcon { .symbol("sparkles") }
    func reasoningEfforts(for chat: AIChatState) -> [ChatGPTSubscription.Effort] { [] }
    func selectedReasoningTitle(for chat: AIChatState) -> String { "" }
    @discardableResult
    func prepareModelSwitcher() -> Task<Void, Never> { Task {} }
}

@MainActor
final class QuickAICoordinator {
    private let core: AppCore

    init(
        chats: AIChatSurfacesState, settings: AppSettings, palette: PaletteState,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.core = core
    }

    /// The AI fallback reads `settings.aiEnabled` itself, so it can still land here.
    func ask(_ prompt: String) { show() }
    func show() { core.showMessage(ExcludedFeature.message(aiFeature), tone: .danger) }
    func attachPastedFile(files: [URL]) -> Bool { false }
    func attachPastedFileFromLauncher(files: [URL]) -> Bool { false }
    func removeLastAttachment() -> Bool { false }
}

// MARK: - Palette screens

struct AIScreen: PaletteScreen {
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let chat: AIChatState
    let coordinator: QuickAICoordinator
    let chatCoordinator: AIChatCoordinator
    let openAttachments: () -> Void

    var rows: [ChatConversation] { [] }
    var primaryActionTitle: String { "" }
    func activate(at selection: Int) {}
    func secondary(at selection: Int) -> Bool { false }
    func body(selection: Int, scroll: ScrollIntent) -> AnyView { AnyView(EmptyView()) }
}

struct ChatHistoryScreen: PaletteScreen {
    let history: ChatHistoryStore
    let chat: AIChatState
    let coordinator: QuickAICoordinator
    let vm: PaletteState
    let openActions: () -> Void
    let metrics: InterfaceMetrics

    var rows: [ChatConversation] { [] }
    var primaryActionTitle: String { "" }
    func activate(at selection: Int) {}
    func secondary(at selection: Int) -> Bool { false }
    func body(selection: Int, scroll: ScrollIntent) -> AnyView { AnyView(EmptyView()) }
}

enum AIModelMenu {
    private static var empty: PopoverMenuContent { PopoverMenuContent(items: []) }

    static func models(coordinator: AIChatCoordinator, chat: AIChatState) -> PopoverMenuContent { empty }
    static func reasoning(coordinator: AIChatCoordinator, chat: AIChatState) -> PopoverMenuContent {
        empty
    }
    static func attachments(coordinator: AIChatCoordinator, chat: AIChatState) -> PopoverMenuContent {
        empty
    }
    static func modelHighlight(coordinator: AIChatCoordinator, chat: AIChatState) -> Int { 0 }
    static func reasoningHighlight(coordinator: AIChatCoordinator, chat: AIChatState) -> Int { 0 }
}

struct AIModelButton: View {
    let title: String
    let icon: PopoverMenuIcon
    let isOpen: Bool
    let action: () -> Void
    var body: some View { EmptyView() }
}

struct AIReasoningButton: View {
    let title: String
    let isOpen: Bool
    let action: () -> Void
    var body: some View { EmptyView() }
}

// MARK: - MCP

@MainActor
@Observable
final class MCPOAuthManager {
    func stop() {}
}

@MainActor
@Observable
final class MCPServerManager {
    init(oauth: MCPOAuthManager) {}
    func stop() {}
}

@MainActor
@Observable
final class MCPCoordinator {
    init(settings: AppSettings, store: MCPSettingsStore, manager: MCPServerManager, core: AppCore) {}
    func applyEnabled() {}
}

// MARK: - Quick Actions

@MainActor
@Observable
final class QuickActionCoordinator {
    private let appIndex: AppIndex
    private let core: AppCore

    init(
        settings: AppSettings, store: QuickActionSettingsStore,
        customActions: CustomQuickActionStore, injector: TextInjector,
        appIndex: AppIndex, hotKeys: HotKeyManager, favorites: FavoritesStore,
        visibility: VisibilityStore, ranking: LauncherRankingStore, aliases: AliasStore,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.appIndex = appIndex
        self.core = core
    }

    func applyEnabled() {
        appIndex.setCommandsVisible(Set(BuiltInQuickAction.allCases.map(CommandID.init)), false)
        applyCustomQuickActionsPresence()
    }

    func applyCustomQuickActionsPresence() { appIndex.setCustomQuickActions([]) }
    func run(id: UUID) { reportExcluded() }
    func run(_ action: QuickAction) { reportExcluded() }

    private func reportExcluded() {
        core.showMessage(ExcludedFeature.message(quickActionsFeature), tone: .danger)
    }
}

// MARK: - Settings panes

struct AISettingsView: View {
    var body: some View { ExcludedFeaturePane(feature: aiFeature, symbol: "sparkles") }
}

struct QuickActionsSettingsView: View {
    var body: some View {
        ExcludedFeaturePane(feature: quickActionsFeature, symbol: "wand.and.sparkles")
    }
}
