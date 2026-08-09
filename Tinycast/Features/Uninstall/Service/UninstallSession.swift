import Foundation

/// One scan, its plan and the checked set; the checked-set invariant lives elsewhere.
@MainActor
@Observable
final class UninstallSession {
    enum State: Equatable {
        case idle
        case scanning
        case ready(UninstallPlan)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var selection: UninstallSelection?
    private(set) var isTrashing = false
    /// Kept for the confirmation copy and the post-uninstall cleanup.
    private(set) var app: AppEntry?

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    var plan: UninstallPlan? {
        if case .ready(let plan) = state { return plan }
        return nil
    }

    var candidates: [UninstallCandidate] { plan?.candidates ?? [] }
    var selectedCount: Int { selection?.count ?? 0 }
    var selectedBytes: Int64 {
        guard let plan, let selection else { return 0 }
        return selection.bytes(in: plan)
    }
    var selectedCandidates: [UninstallCandidate] {
        guard let plan, let selection else { return [] }
        return selection.candidates(in: plan)
    }
    var canConfirm: Bool { selectedCount > 0 && !isTrashing }

    func begin(app: AppEntry, otherAppNames: [String], otherBundleIDs: [String], isRunning: Bool) {
        cancel()
        self.app = app
        state = .scanning
        selection = nil
        let url = app.url
        let name = app.name
        let bundleID = app.bundleID
        scanTask = Task(priority: .userInitiated) { [weak self] in
            let result = await Self.runDiscovery(
                url: url, name: name, bundleID: bundleID, otherAppNames: otherAppNames,
                otherBundleIDs: otherBundleIDs, isRunning: isRunning)
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let plan):
                state = .ready(plan)
                selection = plan.defaultSelection
                await measurePending(in: plan)
            case .failure(let error):
                state = .failed(
                    (error as? UninstallScanner.Failure)?.errorDescription
                        ?? error.localizedDescription)
            }
        }
    }

    /// Releases an in-flight scan; called whenever the palette leaves the screen.
    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        state = .idle
        selection = nil
        app = nil
    }

    func toggle(_ id: UninstallCandidate.ID) {
        guard let plan else { return }
        selection?.toggle(id, in: plan)
    }

    func setTrashing(_ trashing: Bool) {
        isTrashing = trashing
    }

    /// Rows are already on screen, so each walk writes its own row rather than gating the list.
    private func measurePending(in plan: UninstallPlan) async {
        let paths = plan.candidates.filter { $0.size == nil }.map(\.path)
        guard !paths.isEmpty else { return }
        await UninstallScanner.measure(paths: paths) { [weak self] path, size in
            guard let self, case .ready(var plan) = state else { return }
            plan.setSize(size, forPath: path)
            state = .ready(plan)
        }
    }

    /// Off-main, and `scanTask`'s own child: that is what makes `cancel()` release the scan itself.
    private nonisolated static func runDiscovery(
        url: URL, name: String, bundleID: String?, otherAppNames: [String],
        otherBundleIDs: [String], isRunning: Bool
    ) async -> Result<UninstallPlan, Error> {
        do {
            return .success(
                try await UninstallScanner.discover(
                    target: makeTarget(url: url, name: name, bundleID: bundleID),
                    otherAppNames: otherAppNames, otherBundleIDs: otherBundleIDs,
                    isTargetRunning: isRunning))
        } catch {
            return .failure(error)
        }
    }

    /// Off-main: it opens a file.
    private nonisolated static func makeTarget(
        url: URL, name: String, bundleID: String?
    )
        -> UninstallTarget
    {
        let info = Bundle(url: url)?.infoDictionary
        return UninstallTarget(
            bundleURL: url, bundleID: bundleID,
            displayName: (info?["CFBundleDisplayName"] as? String) ?? name,
            bundleName: info?["CFBundleName"] as? String)
    }
}
