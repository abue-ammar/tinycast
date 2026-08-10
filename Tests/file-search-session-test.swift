import Foundation

actor FileSearchProbe {
    private var active = 0
    private var calls: [String] = []
    private var maximumActive = 0

    func search(query: String, homeDirectory: URL) async -> [FileSearchResult] {
        active += 1
        calls.append(query)
        maximumActive = max(maximumActive, active)
        try? await Task.sleep(for: .milliseconds(80))
        active -= 1
        return [
            FileSearchResult(
                url: homeDirectory.appending(path: query), isDirectory: false,
                homeDirectory: homeDirectory)
        ]
    }

    func snapshot() -> (calls: [String], maximumActive: Int) {
        (calls, maximumActive)
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

        print(failures == 0 ? "File search session tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func coalescesDebouncingQueries() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(30))
        session.search("annual")
        try? await Task.sleep(for: .milliseconds(10))
        session.search("annual report")
        await waitUntil { session.state == .ready }

        let snapshot = await probe.snapshot()
        expect(snapshot.calls == ["annual report"], "the debounce runs only the newest query")
        expect(session.results.first?.name == "annual report", "the newest query publishes")
    }

    static func serializesRunningQueries() async {
        let probe = FileSearchProbe()
        let session = makeSession(probe: probe, debounce: .milliseconds(10))
        session.search("first")
        try? await Task.sleep(for: .milliseconds(25))
        session.search("second")
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

    static func makeSession(probe: FileSearchProbe, debounce: Duration) -> FileSearchSession {
        FileSearchSession(homeDirectory: home, debounce: debounce) { query, _, homeDirectory in
            await probe.search(query: query, homeDirectory: homeDirectory)
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
