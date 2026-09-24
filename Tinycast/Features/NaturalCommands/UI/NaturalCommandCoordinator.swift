import Foundation

/// Coordinates an opt-in interpretation, its confidence gate, and the user's final confirmation.
@MainActor
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
    private var run: NaturalCommand.Run?
    private var progressID: UUID?

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

    func interpret(_ query: String) {
        cancel()
        guard settings.naturalCommandsEnabled else { return }

        let candidates = availableCandidates()
        guard !candidates.isEmpty else {
            core.showMessage("No Tinycast commands are available to interpret.", tone: .neutral)
            return
        }

        let apiKey: String
        do {
            apiKey = try connection.apiKey()
        } catch {
            core.showMessage("Add a TypeSafe API key in Settings → Natural Commands.", tone: .danger)
            return
        }

        let requestID = UUID()
        run = .init(id: requestID, query: query, candidates: Set(candidates.map(\.candidate)))
        progressID = requestID
        core.showProgress("Interpreting command…")
        interpretationTask = Task { [weak self, candidates, apiKey, requestID] in
            guard let self else { return }
            defer { self.hideProgress(for: requestID) }
            do {
                let answer = try await self.client.interpret(
                    query: query, candidates: candidates.map(\.candidate), apiKey: apiKey)
                guard !Task.isCancelled, self.isRequestCurrent(requestID)
                else {
                    self.cancelIfCurrent(requestID)
                    return
                }
                self.hideProgress(for: requestID)
                await self.present(
                    answer: answer, query: query, candidates: candidates, requestID: requestID)
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

    func cancelPendingIfContextChanged() {
        guard let run, run.shouldCancelPending(
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
        if let run { hideProgress(for: run.id) }
        run = nil
    }

    func prepareForTermination() { cancel() }

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

    private func present(
        answer: NaturalCommand.ChoiceAnswer, query: String, candidates: [CandidateEntry], requestID: UUID
    ) async {
        let resolution = NaturalCommand.resolve(answer, candidates: candidates.map(\.candidate))
        guard case .candidate(let id) = resolution,
            let target = candidates.first(where: { $0.candidate.id == id })
        else {
            finishInterpretation(for: requestID)
            core.showMessage("No confident Tinycast command matched that request.", tone: .neutral)
            return
        }

        run?.beginConfirmation()
        let shouldRun = await core.confirm(
            title: "Run “\(target.entry.name)”?",
            message: "Tinycast interpreted “\(query)” as this command.",
            symbol: symbol(for: target.entry),
            confirmTitle: "Run Command", tone: .neutral, confirmRole: .standard)
        guard shouldRun else {
            finishInterpretation(for: requestID)
            return
        }
        guard isCurrent(requestID), run?.mayExecute(
            enabled: settings.naturalCommandsEnabled, hasKey: connection.hasAPIKey,
            targetStillAvailable: availableCandidates().contains {
                $0.candidate == target.candidate
            }) == true
        else {
            cancelIfCurrent(requestID)
            return
        }
        finishInterpretation(for: requestID)
        core.launcherCoordinator.launch(target.entry)
    }

    private func isCurrent(_ requestID: UUID) -> Bool { run?.id == requestID }

    private func isRequestCurrent(_ requestID: UUID) -> Bool {
        isCurrent(requestID) && run?.mayPresent(
            currentQuery: core.palette.query,
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
