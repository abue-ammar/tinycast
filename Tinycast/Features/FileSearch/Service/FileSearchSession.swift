import Foundation

@MainActor
@Observable
final class FileSearchSession {
    enum State: Equatable {
        case idle
        case searching
        case ready
        case failed
    }

    private(set) var results: [FileSearchResult] = []
    private(set) var state: State = .idle
    private var query = ""
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    func search(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cancel()
            return
        }
        guard query != self.query || state == .failed else { return }
        searchTask?.cancel()
        self.query = query
        state = .searching
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
                guard let expression = FileSearchQuery.expression(for: query) else { return }
                let candidates = try await Task.detached(priority: .userInitiated) {
                    try FileSearchService.search(
                        query: query, expression: expression, homeDirectory: homeDirectory)
                }.value
                try Task.checkCancellation()
                guard let self, self.query == query else { return }
                results = candidates
                state = .ready
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.query == query else { return }
                results = []
                state = .failed
            }
        }
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        query = ""
        results = []
        state = .idle
    }
}
