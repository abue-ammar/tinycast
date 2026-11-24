import AppKit
import Observation

@MainActor
@Observable
final class PlanUsageCoordinator {
    /// What the menu last pinned; menu state like a window's, so it has no settings key.
    private static let pinKey = "aiUsageMenuBarPin"

    let monitor: PlanUsageMonitor
    private(set) var pin: PlanUsagePin
    private let settings: AppSettings
    private let aiSettings: AISettingsStore
    private let installedAI: InstalledAIManager
    private let subscription: ChatGPTSubscriptionManager
    private unowned let core: AppCore
    @ObservationIgnored private var menuBar: PlanUsageMenuBarController?
    @ObservationIgnored private var trackedProviders: [PlanUsage.Provider]?
    @ObservationIgnored private var trackingGeneration = 0

    init(
        monitor: PlanUsageMonitor, settings: AppSettings, aiSettings: AISettingsStore,
        installedAI: InstalledAIManager, subscription: ChatGPTSubscriptionManager, core: AppCore
    ) {
        self.monitor = monitor
        self.settings = settings
        self.aiSettings = aiSettings
        self.installedAI = installedAI
        self.subscription = subscription
        self.core = core
        pin = PlanUsagePin(rawValue: UserDefaults.standard.string(forKey: Self.pinKey))
        monitor.providers = { [weak self] in self?.availableProviders ?? [] }
        monitor.reader = { [weak self] provider in await self?.read(provider) ?? .failed }
        monitor.onChange = { [weak self] provider, previous, usage in
            self?.alert(provider, from: previous, to: usage)
        }
        subscription.onUsage = { [weak monitor] usage in monitor?.apply(usage, for: .chatGPT) }
    }

    var availableProviders: [PlanUsage.Provider] {
        PlanUsage.Provider.allCases.filter { provider in
            switch provider {
            case .claude: return installedAI.status(for: .claude).isReady
            case .chatGPT: return subscription.isConnected && subscription.account?.usesAPIKey == false
            }
        }
    }

    var isCheckingProviders: Bool {
        installedAI.status(for: .claude).phase == .checking || subscription.phase == .starting
    }

    var target: PlanUsagePin.Target? { pin.target(in: monitor.usage) }

    func applyEnabled() {
        trackingGeneration += 1
        guard settings.aiEnabled, aiSettings.usageMenuBarEnabled else {
            menuBar?.remove()
            menuBar = nil
            trackedProviders = nil
            monitor.stop()
            return
        }
        guard menuBar == nil else { return }
        monitor.start()
        menuBar = PlanUsageMenuBarController(coordinator: self)
        trackProviders(generation: trackingGeneration)
    }

    func setPin(_ pin: PlanUsagePin) {
        self.pin = pin
        UserDefaults.standard.set(pin.rawValue, forKey: Self.pinKey)
    }

    func refresh() {
        monitor.refresh()
    }

    /// Claude's CLI reports no limits mid-chat, so its usage is read again once a reply lands.
    func replyFinished(on selection: AIModelSelection?) {
        guard case .claude? = selection else { return }
        monitor.refresh(.claude)
    }

    func showSettings() {
        core.settingsCoordinator.showSettings(tab: .ai, revealing: .section(.aiUsage))
    }

    func showProviders() {
        core.settingsCoordinator.showSettings(tab: .ai, revealing: .section(.aiProviders))
    }

    func useResetCredit() {
        let credits = monitor.usage[.chatGPT]?.resetCredits ?? 0
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Reset ChatGPT limits?"),
                    message: String(
                        localized: """
                            Uses one of your \(credits) free resets. Your 5-hour and weekly limits \
                            start over.
                            """),
                    symbol: "arrow.counterclockwise", confirmTitle: String(localized: "Reset"),
                    tone: .neutral, confirmRole: .standard)
            else { return }
            do {
                let outcome = try await subscription.consumeResetCredit()
                core.showMessage(outcome.message, tone: Self.tone(of: outcome))
            } catch {
                core.showMessage(String(localized: "Couldn't reset ChatGPT limits"), tone: .danger)
            }
            monitor.refresh(.chatGPT, force: true)
        }
    }

    private func trackProviders(generation: Int) {
        guard generation == trackingGeneration else { return }
        let providers = withObservationTracking {
            availableProviders
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackProviders(generation: generation) }
        }
        guard providers != trackedProviders else { return }
        trackedProviders = providers
        monitor.refresh()
    }

    private static func tone(of outcome: PlanUsage.ResetOutcome) -> DialogTone {
        switch outcome {
        case .reset, .alreadyRedeemed: return .success
        case .nothingToReset: return .neutral
        case .noCredit: return .danger
        }
    }

    private func read(_ provider: PlanUsage.Provider) async -> PlanUsage.Reading {
        switch provider {
        case .claude: return await installedAI.claudeUsage()
        case .chatGPT: return await subscription.readUsage()
        }
    }

    private func alert(_ provider: PlanUsage.Provider, from previous: PlanUsage?, to usage: PlanUsage) {
        guard aiSettings.usageAlertsEnabled,
            let alert = PlanUsageAlertPolicy.alert(for: provider, from: previous, to: usage)
        else { return }
        switch alert.kind {
        case .reached(.critical): core.showMessage(alert.message, tone: .danger)
        case .reached: core.showMessage(alert.message, tone: .neutral)
        case .reset: core.showMessage(alert.message, tone: .success)
        }
    }
}
