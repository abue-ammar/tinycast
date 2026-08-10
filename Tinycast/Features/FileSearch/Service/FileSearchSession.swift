import Foundation

@MainActor
@Observable
final class FileSearchSession {
    typealias SearchOperation = @Sendable (String, String, URL) async throws -> [FileSearchResult]

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
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let searchOperation: SearchOperation

    private struct PendingSearch {
        let query: String
        let revision: Int
        let earliestStart: ContinuousClock.Instant
    }

    init() {
        homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        debounce = .milliseconds(120)
        searchOperation = { query, expression, homeDirectory in
            try await Task.detached(priority: .userInitiated) {
                try FileSearchService.search(
                    query: query, expression: expression, homeDirectory: homeDirectory)
            }.value
        }
    }

    init(
        homeDirectory: URL, debounce: Duration,
        searchOperation: @escaping SearchOperation
    ) {
        self.homeDirectory = homeDirectory
        self.debounce = debounce
        self.searchOperation = searchOperation
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
            guard let expression = FileSearchQuery.expression(for: request.query) else { continue }
            do {
                let candidates = try await searchOperation(
                    request.query, expression, homeDirectory)
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
