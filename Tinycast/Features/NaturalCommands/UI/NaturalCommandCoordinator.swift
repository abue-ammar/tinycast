import Foundation

/// Publishes bounded command choices after interpretation and confirms an explicit selection.
@MainActor
@Observable
final class NaturalCommandCoordinator {
    private struct CandidateEntry: Sendable {
        let candidate: NaturalCommand.Candidate
        let entry: AppEntry
    }

    private let settings: AppSettings
    private let connection: NaturalCommandSettingsStore
    private let appIndex: AppIndex
    private let visibility: VisibilityStore
    private let client = NaturalCommandClient()
    private unowned let core: AppCore
    @ObservationIgnored private var interpretationTask: Task<Void, Never>?
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?
    @ObservationIgnored private var run: NaturalCommand.Run?
    @ObservationIgnored private var progressID: UUID?
    private(set) var suggestions: [AppEntry] = []
    private(set) var suggestionRunID: UUID?

    init(
        settings: AppSettings, connection: NaturalCommandSettingsStore, appIndex: AppIndex,
        visibility: VisibilityStore, core: AppCore
    ) {
        self.settings = settings
        self.connection = connection
        self.appIndex = appIndex
        self.visibility = visibility
        self.core = core
    }

    func considerFallback(query: String, hasLocalAnswer: Bool) {
        guard NaturalCommand.shouldInterpret(
            query: query, hasLocalAnswer: hasLocalAnswer,
            enabled: settings.naturalCommandsEnabled, hasKey: connection.hasAPIKey)
        else {
            cancel()
            return
        }
        if run?.query == query { return }
        cancel()
        let candidates = availableCandidates()
        guard !candidates.isEmpty else { return }
        let requestID = UUID()
        run = .init(id: requestID, query: query, candidates: Set(candidates.map(\.candidate)))
        interpretationTask = Task { [weak self, candidates, requestID] in
            guard let self else { return }
            defer { self.hideProgress(for: requestID) }
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }
            guard !Task.isCancelled, self.isRequestCurrent(requestID) else {
                self.cancelIfCurrent(requestID)
                return
            }
            let apiKey: String
            do {
                apiKey = try self.connection.apiKey()
            } catch {
                self.finishInterpretation(for: requestID)
                self.core.showMessage("The TypeSafe API key could not be read.", tone: .danger)
                return
            }
            self.progressID = requestID
            self.core.showProgress("Interpreting command…")
            do {
                let answer = try await self.client.interpret(
                    query: query, candidates: candidates.map(\.candidate), apiKey: apiKey)
                guard !Task.isCancelled, self.isRequestCurrent(requestID)
                else {
                    self.cancelIfCurrent(requestID)
                    return
                }
                self.hideProgress(for: requestID)
                self.publish(answer: answer, candidates: candidates, requestID: requestID)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.isRequestCurrent(requestID)
                else {
                    self.cancelIfCurrent(requestID)
                    return
                }
                self.finishInterpretation(for: requestID)
                self.core.showMessage(
                    "Couldn't interpret command — \(error.localizedDescription)", tone: .danger)
            }
        }
    }

    func clearIfContextChanged() {
        guard let run, run.shouldClearForContext(
            currentQuery: core.palette.query,
            isLauncherVisible: core.paletteCoordinator.isShowing(.launcher),
            enabled: settings.naturalCommandsEnabled, hasKey: connection.hasAPIKey)
        else { return }
        cancel()
    }

    func cancelIfDisabled() {
        if !settings.naturalCommandsEnabled { cancel() }
    }

    func cancel() {
        interpretationTask?.cancel()
        interpretationTask = nil
        confirmationTask?.cancel()
        confirmationTask = nil
        if let run { hideProgress(for: run.id) }
        run = nil
        suggestions = []
        suggestionRunID = nil
    }

    func prepareForTermination() { cancel() }

    func choices(for query: String, hasLocalAnswer: Bool) -> [AppEntry] {
        guard !hasLocalAnswer, isChoiceCurrent(query: query) else { return [] }
        return suggestions
    }

    func select(_ id: String) {
        guard let run, run.phase == .choosing else { return }
        guard isChoiceCurrent(query: core.palette.query),
            suggestions.contains(where: { $0.id == id }),
            let target = availableCandidates().first(where: { $0.candidate.id == id })
        else {
            cancel()
            return
        }
        self.run?.beginConfirmation()
        confirmationTask = Task { [weak self, requestID = run.id, target] in
            guard let self else { return }
            let shouldRun = await self.core.confirm(
                title: "Run “\(target.entry.name)”?",
                message: "Tinycast interpreted “\(run.query)” as this command.",
                symbol: self.symbol(for: target.entry),
                confirmTitle: "Run Command", tone: .neutral, confirmRole: .standard)
            guard self.isCurrent(requestID) else { return }
            self.confirmationTask = nil
            guard shouldRun else {
                self.run?.resumeChoosing()
                self.clearIfContextChanged()
                return
            }
            guard self.run?.mayExecute(
                currentQuery: self.core.palette.query,
                enabled: self.settings.naturalCommandsEnabled,
                hasKey: self.connection.hasAPIKey,
                targetStillAvailable: self.availableCandidates().contains {
                    $0.candidate == target.candidate
                }) == true
            else {
                self.cancel()
                return
            }
            self.finishInterpretation(for: requestID)
            self.core.launcherCoordinator.launch(target.entry)
        }
    }

    private func availableCandidates() -> [CandidateEntry] {
        appIndex.apps.compactMap { entry in
            guard visibility.isVisible(entry), isBuiltInTarget(entry) else { return nil }
            return CandidateEntry(
                candidate: .init(
                    id: entry.id, name: entry.name, kind: entry.kind.descriptor.label,
                    meaning: WindowCommandCatalog.command(forEntryID: entry.id).map {
                        NaturalCommandWindowMeaning.describe($0.id)
                    }),
                entry: entry)
        }
    }

    private func isBuiltInTarget(_ entry: AppEntry) -> Bool {
        switch entry.kind {
        case .command:
            return !(CommandCatalog.command(for: entry)?.isQueryDriven ?? true)
        case .systemAction, .windowCommand:
            return SystemActionCatalog.action(forEntryID: entry.id) != nil
                || WindowCommandCatalog.command(forEntryID: entry.id) != nil
        default:
            return false
        }
    }

    private func publish(
        answer: NaturalCommand.ChoiceAnswer, candidates: [CandidateEntry], requestID: UUID
    ) {
        let ids = NaturalCommand.suggestedIDs(answer, candidates: candidates.map(\.candidate))
        guard !ids.isEmpty else {
            finishInterpretation(for: requestID)
            return
        }
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.candidate.id, $0.entry) })
        run?.beginChoosing()
        interpretationTask = nil
        suggestions = ids.compactMap { byID[$0] }
        suggestionRunID = requestID
    }

    private func isCurrent(_ requestID: UUID) -> Bool { run?.id == requestID }

    private func isRequestCurrent(_ requestID: UUID) -> Bool {
        isCurrent(requestID) && run?.mayPresent(
            currentQuery: core.palette.query,
            isLauncherVisible: core.paletteCoordinator.isShowing(.launcher),
            enabled: settings.naturalCommandsEnabled, hasKey: connection.hasAPIKey,
            currentCandidates: Set(availableCandidates().map(\.candidate))) == true
    }

    private func isChoiceCurrent(query: String) -> Bool {
        run?.mayChoose(
            currentQuery: query,
            isLauncherVisible: core.paletteCoordinator.isShowing(.launcher),
            enabled: settings.naturalCommandsEnabled, hasKey: connection.hasAPIKey,
            currentCandidates: Set(availableCandidates().map(\.candidate))) == true
    }

    private func cancelIfCurrent(_ requestID: UUID) {
        if isCurrent(requestID) { cancel() }
    }

    private func hideProgress(for requestID: UUID) {
        guard progressID == requestID else { return }
        progressID = nil
        core.hideProgress()
    }

    private func finishInterpretation(for requestID: UUID) {
        guard isCurrent(requestID) else { return }
        run = nil
        interpretationTask = nil
        confirmationTask = nil
        suggestions = []
        suggestionRunID = nil
        hideProgress(for: requestID)
    }

    private func symbol(for entry: AppEntry) -> String? {
        switch entry.kind {
        case .command: return CommandCatalog.command(for: entry)?.sfSymbol
        case .systemAction: return SystemActionCatalog.action(forEntryID: entry.id)?.sfSymbol
        case .windowCommand: return WindowCommandCatalog.command(forEntryID: entry.id)?.sfSymbol
        default: return nil
        }
    }
}
