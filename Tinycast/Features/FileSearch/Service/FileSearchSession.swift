import Foundation

@MainActor
@Observable
final class FileSearchSession {
    typealias SearchOperation = @Sendable (String, FileSearchFilter) async -> [FileSearchResult]

    enum State: Equatable {
        case idle
        case searching
        case ready
    }

    private(set) var results: [FileSearchResult] = []
    private(set) var state: State = .idle
    /// The published search: the filter belongs to it, so narrowing re-runs the same words.
    private var request: Request?
    private var revision = 0
    @ObservationIgnored private var pending: (request: Request, revision: Int)?
    @ObservationIgnored private var workerTask: Task<Void, Never>?
    @ObservationIgnored private let searchOperation: SearchOperation
    /// Kept across closes, so the blank screen opens on its rows instead of on nothing.
    @ObservationIgnored private var recent: [FileSearchResult]?
    @ObservationIgnored private var recentStamp = 0
    /// The revision an index swap re-ran; Recent reloads once the worker gets past it.
    @ObservationIgnored private var recentRefreshDue: Int?

    private struct Request: Equatable {
        static let recent = Request(query: "", filter: .all)

        let query: String
        let filter: FileSearchFilter
    }

    /// No debounce: a search costs milliseconds, and the worker already runs only the newest.
    init(index: FileIndex) {
        searchOperation = { query, filter in
            await Task.detached(priority: .userInitiated) {
                guard let prepared = FileSearchQuery.prepare(query) else {
                    return index.recent(filter: filter)
                }
                return index.search(prepared, filter: filter)
            }.value
        }
    }

    init(searchOperation: @escaping SearchOperation) {
        self.searchOperation = searchOperation
    }

    /// An empty query is a request too: the blank screen lists what changed recently.
    @discardableResult
    func search(_ rawQuery: String, filter: FileSearchFilter = .all) -> Task<Void, Never>? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = Request(query: query, filter: filter)
        guard request != self.request else { return nil }
        let task = enqueue(request)
        if request == .recent, let recent {
            results = recent
            state = .ready
        }
        return task
    }

    /// Re-runs the published request; Recent's kept rows follow even behind a typed query.
    @discardableResult
    func refresh() -> Task<Void, Never> {
        guard let request else { return refreshRecent() }
        let search = enqueue(request)
        if request != .recent { recentRefreshDue = revision }
        return search
    }

    /// Only the kept rows move, so a list on screen never shifts under the pointer.
    @discardableResult
    func refreshRecent() -> Task<Void, Never> {
        recentRefreshDue = nil
        recentStamp &+= 1
        let stamp = recentStamp
        return Task { [weak self] in
            _ = await self?.loadRecent(stamp: stamp)
        }
    }

    /// Idle already means no results and nothing that can publish, so it notifies no observer.
    func cancel() {
        guard request != nil else { return }
        revision &+= 1
        pending = nil
        request = nil
        results = []
        state = .idle
    }

    /// A trashed row names a file that is gone, so it leaves the published results with it.
    func remove(_ result: FileSearchResult) {
        results.removeAll { $0.id == result.id }
        recent?.removeAll { $0.id == result.id }
    }

    private func enqueue(_ request: Request) -> Task<Void, Never> {
        revision &+= 1
        self.request = request
        state = .searching
        pending = (request, revision)
        if let workerTask { return workerTask }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runWorker()
        }
        workerTask = task
        return task
    }

    private func runWorker() async {
        while let next = pending {
            pending = nil
            let found = await run(next.request)
            if revision == next.revision, request == next.request {
                if results != found { results = found }
                state = .ready
            }
            if let due = recentRefreshDue, next.revision >= due || pending == nil {
                _ = await run(.recent)
            }
        }
        workerTask = nil
    }

    /// Recent's rows are kept whoever asked; stamped, so a late finisher never replaces newer rows.
    private func run(_ request: Request) async -> [FileSearchResult] {
        guard request == .recent else { return await searchOperation(request.query, request.filter) }
        recentRefreshDue = nil
        recentStamp &+= 1
        return await loadRecent(stamp: recentStamp)
    }

    private func loadRecent(stamp: Int) async -> [FileSearchResult] {
        let found = await searchOperation("", .all)
        if stamp == recentStamp { recent = found }
        return found
    }
}
