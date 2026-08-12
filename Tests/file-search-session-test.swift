import Foundation

actor FileSearchProbe {
    private var active = 0
    private var calls: [String] = []
    private var maximumActive = 0
    private let pausedQuery: String?
    private var pauseEnabled: Bool
    private var pausedContinuation: CheckedContinuation<Void, Never>?

    init(pausing query: String? = nil) {
        pausedQuery = query
        pauseEnabled = query != nil
    }

    func search(query: String, policy: FileSearchPolicy) async -> [FileSearchResult] {
        active += 1
        calls.append(query)
        maximumActive = max(maximumActive, active)
        if pauseEnabled, query == pausedQuery {
            await withCheckedContinuation { continuation in
                pausedContinuation = continuation
            }
        } else {
            try? await Task.sleep(for: .milliseconds(80))
        }
        active -= 1
        return [
            FileSearchResult(
                url: policy.homeDirectory.appending(path: query), isDirectory: false,
                homeDirectory: policy.homeDirectory)
        ]
    }

    func snapshot() -> (calls: [String], maximumActive: Int) {
        (calls, maximumActive)
    }

    func waitUntilPaused() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while pausedContinuation == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        guard pausedContinuation != nil else {
            pauseEnabled = false
            return false
        }
        return true
    }

    func resumePausedSearch() {
        pauseEnabled = false
        pausedContinuation?.resume()
        pausedContinuation = nil
    }
}

@main
@MainActor
struct FileSearchSessionTests {
    nonisolated(unsafe) static var failures = 0
    static let home = URL(fileURLWithPath: "/Users/test")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        await coalescesDebouncingQueries()
        await serializesRunningQueries()
        await cancellationPreventsPendingWork()
        await policyChangeDiscardsStaleResults()
        await unchangedPolicyKeepsResults()

        print(failures == 0 ? "File search session tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func coalescesDebouncingQueries() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(30))
        session.search("annual")
        session.search("annual report")
        await waitUntil { session.state == .ready }

        let snapshot = await probe.snapshot()
        expect(snapshot.calls == ["annual report"], "the debounce runs only the newest query")
        expect(session.results.first?.name == "annual report", "the newest query publishes")
    }

    static func serializesRunningQueries() async {
        let probe = FileSearchProbe(pausing: "first")
        let session = makeSession(probe: probe, debounce: .milliseconds(10))
        session.search("first")
        let firstStarted = await probe.waitUntilPaused()
        expect(firstStarted, "the first query starts")
        guard firstStarted else { return }
        session.search("second")
        await probe.resumePausedSearch()
        await waitUntil { session.state == .ready && session.results.first?.name == "second" }

        let snapshot = await probe.snapshot()
        expect(snapshot.calls == ["first", "second"], "the superseding query still runs")
        expect(snapshot.maximumActive == 1, "Spotlight operations never overlap")
    }

    static func cancellationPreventsPendingWork() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(30))
        session.search("cancelled")
        session.cancel()
        try? await Task.sleep(for: .milliseconds(60))

        let snapshot = await probe.snapshot()
        expect(snapshot.calls.isEmpty, "cancelling during the debounce prevents the search")
        expect(session.state == .idle && session.results.isEmpty, "cancellation clears the session")
    }

    static func policyChangeDiscardsStaleResults() async {
        let probe = FileSearchProbe(pausing: "report")
        let session = makeSession(probe: probe, debounce: .milliseconds(10))
        session.search("report")
        let oldSearchStarted = await probe.waitUntilPaused()
        expect(oldSearchStarted, "the old-policy query starts")
        guard oldSearchStarted else { return }
        session.apply(scopes: FileSearchScope.defaultScopes, ignorePatterns: ["*.log"])

        expect(
            session.state == .idle && session.results.isEmpty,
            "a result found under the old rules never publishes")
        session.search("report")
        await probe.resumePausedSearch()
        await waitUntil { session.state == .ready && session.results.first?.name == "report" }
        let snapshot = await probe.snapshot()
        expect(snapshot.calls == ["report", "report"], "the same query re-runs under the new rules")
    }

    static func unchangedPolicyKeepsResults() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(10))
        session.search("report")
        await waitUntil { session.state == .ready }
        session.apply(scopes: FileSearchScope.defaultScopes, ignorePatterns: [])

        expect(
            session.state == .ready && session.results.first?.name == "report",
            "re-applying identical settings leaves the published results alone")
    }

    static func makeSession(probe: FileSearchProbe, debounce: Duration) -> FileSearchSession {
        let policy = FileSearchPolicy(
            scopes: FileSearchScope.defaultScopes, ignorePatterns: [], homeDirectory: home)
        return FileSearchSession(policy: policy, debounce: debounce) { query, _, policy in
            await probe.search(query: query, policy: policy)
        }
    }

    static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        expect(condition(), "the async operation completed before the timeout")
    }
}
