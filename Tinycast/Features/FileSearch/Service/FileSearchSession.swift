import Foundation

@MainActor
@Observable
final class FileSearchSession {
    typealias SearchOperation =
        @Sendable (String, String, FileSearchPolicy) async throws -> [FileSearchResult]

    enum State: Equatable {
        case idle
        case searching
        case ready
        case failed
    }

    private(set) var results: [FileSearchResult] = []
    private(set) var state: State = .idle
    private var query = ""
    private var revision = 0
    @ObservationIgnored private var pendingSearch: PendingSearch?
    @ObservationIgnored private var workerTask: Task<Void, Never>?
    @ObservationIgnored private let homeDirectory: URL
    @ObservationIgnored private var policy: FileSearchPolicy
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let searchOperation: SearchOperation

    private struct PendingSearch {
        let query: String
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
        searchOperation = { query, expression, policy in
            try await Task.detached(priority: .userInitiated) {
                try FileSearchService.search(
                    query: query, expression: expression, policy: policy)
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

    func search(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cancel()
            return
        }
        guard query != self.query || state == .failed else { return }
        revision &+= 1
        self.query = query
        state = .searching
        pendingSearch = PendingSearch(
            query: query, revision: revision,
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
        query = ""
        results = []
        state = .idle
    }

    private func runWorker() async {
        while let request = pendingSearch {
            let delay = ContinuousClock.now.duration(to: request.earliestStart)
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard pendingSearch?.revision == request.revision else { continue }
            pendingSearch = nil
            guard
                let expression = FileSearchQuery.expression(
                    for: request.query, excluding: policy.ignore.spotlightNameExclusions)
            else { continue }
            do {
                let candidates = try await searchOperation(request.query, expression, policy)
                guard revision == request.revision, query == request.query else { continue }
                results = candidates
                state = .ready
            } catch {
                guard revision == request.revision, query == request.query else { continue }
                results = []
                state = .failed
            }
        }
        workerTask = nil
    }
}
