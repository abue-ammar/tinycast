import Foundation

@MainActor
@Observable
final class FileSearchSession {
    typealias SearchOperation =
        @Sendable (String, String, FileSearchPolicy, FileSearchFilter) async throws ->
            [FileSearchResult]

    enum State: Equatable {
        case idle
        case searching
        case ready
        case failed
    }

    private(set) var results: [FileSearchResult] = []
    private(set) var state: State = .idle
    /// The published search: the filter belongs to it, so narrowing re-runs the same words.
    private var request: Request?
    private var revision = 0
    @ObservationIgnored private var pendingSearch: PendingSearch?
    @ObservationIgnored private var workerTask: Task<Void, Never>?
    @ObservationIgnored private let homeDirectory: URL
    @ObservationIgnored private var policy: FileSearchPolicy
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let searchOperation: SearchOperation

    private struct Request: Equatable {
        let query: String
        let filter: FileSearchFilter
    }

    private struct PendingSearch {
        let request: Request
        let revision: Int
        let earliestStart: ContinuousClock.Instant
    }

    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.homeDirectory = homeDirectory
        policy = FileSearchPolicy(
            scopes: FileSearchScope.defaultScopes, ignorePatterns: [],
            homeDirectory: homeDirectory)
        debounce = .milliseconds(120)
        searchOperation = { query, expression, policy, filter in
            try await Task.detached(priority: .userInitiated) {
                try FileSearchService.search(
                    query: query, expression: expression, policy: policy, filter: filter)
            }.value
        }
    }

    init(
        policy: FileSearchPolicy, debounce: Duration,
        searchOperation: @escaping SearchOperation
    ) {
        homeDirectory = policy.homeDirectory
        self.policy = policy
        self.debounce = debounce
        self.searchOperation = searchOperation
    }

    /// Resolved here rather than per search, so glob compilation stays off the keystroke path.
    func apply(scopes: [String], ignorePatterns: [String]) {
        let policy = FileSearchPolicy(
            scopes: scopes, ignorePatterns: ignorePatterns, homeDirectory: homeDirectory)
        guard policy != self.policy else { return }
        self.policy = policy
        // A result found under the old rules must not publish, and the same query has to re-run.
        cancel()
    }

    /// An empty query is a request too: the blank screen lists what was used recently.
    func search(_ rawQuery: String, filter: FileSearchFilter = .all) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = Request(query: query, filter: filter)
        guard request != self.request || state == .failed else { return }
        revision &+= 1
        self.request = request
        state = .searching
        pendingSearch = PendingSearch(
            request: request, revision: revision,
            earliestStart: ContinuousClock.now.advanced(by: debounce))
        guard workerTask == nil else { return }
        workerTask = Task { [weak self] in
            guard let self else { return }
            await runWorker()
        }
    }

    func cancel() {
        revision &+= 1
        pendingSearch = nil
        request = nil
        results = []
        state = .idle
    }

    /// A trashed row names a file that is gone, so it leaves the published results with it.
    func remove(_ result: FileSearchResult) {
        results.removeAll { $0.id == result.id }
    }

    private func runWorker() async {
        while let pending = pendingSearch {
            let delay = ContinuousClock.now.duration(to: pending.earliestStart)
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard pendingSearch?.revision == pending.revision else { continue }
            pendingSearch = nil
            let request = pending.request
            let exclusions = policy.ignore.spotlightNameExclusions
            let expression =
                request.query.isEmpty
                ? FileSearchQuery.recentExpression(excluding: exclusions, filter: request.filter)
                : FileSearchQuery.expression(
                    for: request.query, excluding: exclusions, filter: request.filter)
            guard let expression else { continue }
            do {
                let candidates = try await searchOperation(
                    request.query, expression, policy, request.filter)
                guard revision == pending.revision, self.request == request else { continue }
                results = candidates
                state = .ready
            } catch {
                guard revision == pending.revision, self.request == request else { continue }
                results = []
                state = .failed
            }
        }
        workerTask = nil
    }
}
