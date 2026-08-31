import AppKit
import Observation

/// The single funnel for every Quick Action, however it was started.
@MainActor
@Observable
final class QuickActionCoordinator {
    private let settings: AppSettings
    private let store: QuickActionSettingsStore
    private let injector: TextInjector
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    private let panels = QuickActionPanelController()
    private unowned let core: AppCore

    private static let launcherCommands = Set(QuickAction.allCases.map(CommandID.init))

    /// One at a time: two runs race for one selection, and the second overwrites the first's work.
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        settings: AppSettings, store: QuickActionSettingsStore, injector: TextInjector,
        appIndex: AppIndex, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.store = store
        self.injector = injector
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// Launcher rows come and go with the switch; the Carbon bindings stay registered.
    func applyEnabled() {
        appIndex.setCommandsVisible(Self.launcherCommands, settings.quickActionsEnabled)
        guard settings.quickActionsEnabled else {
            cancel()
            return
        }
        store.resolveModel(
            appleIntelligenceAvailable: core.aiSettings.isAppleIntelligenceAvailable(),
            fallback: core.aiSettings.defaultModel)
        loadLanguages()
    }

    /// Enabling is consent: reading a selection and typing over it both need Accessibility.
    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.quickActionsEnabled else { return }
        guard enabled else {
            settings.quickActionsEnabled = false
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable Quick Actions?",
                    message:
                        "Tinycast needs the Accessibility permission to read the text you have "
                        + "selected in other apps and replace it. Nothing is read until you press "
                        + "a shortcut.",
                    symbol: "wand.and.sparkles", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }
            settings.quickActionsEnabled = true
            // The one prompt for this feature, raised from the gesture that asked for it.
            Permissions.ensureAccessibility()
        }
    }

    func run(_ action: QuickAction) {
        guard settings.quickActionsEnabled, running == nil else { return }
        let target = paletteCoordinator.targetApp
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        start { [weak self] in await self?.begin(action, target: target) }
    }

    func cancel() {
        generation += 1
        running?.cancel()
        running = nil
        panels.dismiss()
    }

    /// The generation stops a superseded task from clearing the newer handle as it finishes.
    private func start(_ work: @escaping @MainActor () async -> Void) {
        generation += 1
        let mine = generation
        running?.cancel()
        running = Task { [weak self] in
            await work()
            guard let self, mine == self.generation else { return }
            self.running = nil
        }
    }

    private func begin(_ action: QuickAction, target: NSRunningApplication?) async {
        let selection: String
        do {
            selection = try await QuickActionRunner.selection(in: target, using: injector)
        } catch let failure as QuickActionFailure {
            reportRefusal(failure)
            return
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
            return
        }
        let state = QuickActionPanelState(
            action: action, original: selection, targetLanguage: targetLanguage)
        let previews = store.settings.previewsResult(action)
        if previews { present(state, target: target) }
        await perform(state, target: target, previewing: previews)
    }

    /// A missing permission cannot be fixed from a pill that fades, so it earns a dialog instead.
    private func reportRefusal(_ failure: QuickActionFailure) {
        guard failure.opensAccessibilitySettings else {
            core.showMessage(failure.localizedDescription, tone: .danger)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.reportFailure(
                    title: "Quick Actions can't read your selection",
                    message:
                        "Tinycast needs the Accessibility permission to read the text you have "
                        + "selected and replace it. If Tinycast is already listed, switch it off "
                        + "and on again — a rebuilt app keeps a stale entry.",
                    symbol: "wand.and.sparkles", recovery: "Open System Settings")
            else { return }
            Permissions.openAccessibilitySettings()
        }
    }

    private func perform(
        _ state: QuickActionPanelState, target: NSRunningApplication?, previewing: Bool
    ) async {
        do {
            let text = try await produce(state, previewing: previewing)
            guard !Task.isCancelled else { return }
            state.finish(text)
            if previewing { return }
            deliver(text, to: target, action: state.action)
        } catch is CancellationError {
            return
        } catch let error as TextTranslator.Failure where error.needsDownload {
            // Only SwiftUI's `translationTask` can fetch a pair, so this has to become a panel.
            if !previewing { present(state, target: target) }
            state.requireLanguageDownload()
        } catch {
            report(error, state: state, previewing: previewing)
        }
    }

    /// Without a panel there is nothing on screen saying the model is working, so the pill says it.
    private func produce(
        _ state: QuickActionPanelState, previewing: Bool
    ) async throws -> String {
        guard !previewing else { return try await generate(state, streaming: true) }
        core.showProgress(state.action.progressTitle)
        defer { core.hideProgress() }
        return try await generate(state, streaming: false)
    }

    private func generate(
        _ state: QuickActionPanelState, streaming: Bool
    ) async throws -> String {
        if state.action.usesTranslationFramework {
            return try await TextTranslator.translate(state.original, to: state.targetLanguage)
        }
        let provider = try core.quickActionProvider()
        return try await QuickActionRunner.run(
            state.action, selection: state.original, using: provider,
            instructionOverride: store.settings.instructionOverride(for: state.action),
            onDelta: { delta in
                guard streaming else { return }
                state.append(delta)
            })
    }

    /// A replacement that never lands would otherwise lose the reply, so the clipboard keeps it.
    private func deliver(_ text: String, to target: NSRunningApplication?, action: QuickAction) {
        injector.replaceSelection(
            with: text, in: target,
            onDelivered: { [weak self] in self?.core.showMessage("\(action.title) applied") },
            onFailed: { [weak self] in
                Paster.copyPlainText(text)
                self?.core.showMessage(
                    "\(action.title) couldn't replace the selection — copied instead",
                    tone: .danger)
            })
    }

    /// A failure the reader cannot see is a hotkey that silently did nothing.
    private func report(_ error: Error, state: QuickActionPanelState, previewing: Bool) {
        guard previewing else {
            core.showMessage(error.localizedDescription, tone: .danger)
            return
        }
        state.fail(error.localizedDescription)
    }

    private func present(_ state: QuickActionPanelState, target: NSRunningApplication?) {
        panels.present(
            state,
            languages: offeredLanguages,
            onRetranslate: { [weak self] language in
                state.targetLanguage = language
                self?.rerun(state, target: target)
            },
            onDownloaded: { [weak self] in self?.rerun(state, target: target) },
            onReplace: { [weak self] text in
                self?.deliver(text, to: target, action: state.action)
            })
    }

    private func rerun(_ state: QuickActionPanelState, target: NSRunningApplication?) {
        state.restart()
        start { [weak self] in await self?.perform(state, target: target, previewing: true) }
    }

    private var targetLanguage: Locale.Language {
        let stored = store.settings.targetLanguage
        guard !stored.isEmpty else { return Locale.current.language }
        return Locale.Language(identifier: stored)
    }

    /// Observed, not ignored: it arrives after the pane has painted, and the picker has to notice.
    private(set) var offeredLanguages: [Locale.Language] = []
    @ObservationIgnored private var languageLoad: Task<Void, Never>?

    func loadLanguages() {
        guard offeredLanguages.isEmpty, languageLoad == nil else { return }
        languageLoad = Task { [weak self] in
            let languages = await TextTranslator.supportedLanguages()
            self?.offeredLanguages = languages
        }
    }
}

extension TextTranslator.Failure {
    var needsDownload: Bool {
        if case .notInstalled = self { return true }
        return false
    }
}
