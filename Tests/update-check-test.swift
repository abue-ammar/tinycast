import Foundation

@main
@MainActor
struct UpdateCheckTests {
    static var failures = 0
    static var passes = 0

    static func main() async throws {
        try await stopsBeforeFirstCheck()
        try await cancelsAndRestarts()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func stopsBeforeFirstCheck() async throws {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let fixture = FetchFixture()
        let store = makeStore(file: file, fixture: fixture)
        var offers = 0
        store.onUpdateAvailable = { _ in
            offers += 1
            return true
        }

        store.start(after: .milliseconds(10))
        store.stop()
        try await Task.sleep(for: .milliseconds(30))
        expect(fixture.requests == 0, "disabling during the startup delay makes no request")
        expect(offers == 0, "a stopped checker offers no update")
        expect(!FileManager.default.fileExists(atPath: file.path), "stopping creates no cache")
    }

    static func cancelsAndRestarts() async throws {
        let file = makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try seedCache(at: file)
        let originalCache = try Data(contentsOf: file)
        let fixture = FetchFixture()
        let store = makeStore(file: file, fixture: fixture)
        var offers = 0
        store.onUpdateAvailable = { _ in
            offers += 1
            return true
        }
        defer { store.stop() }

        store.start(after: .zero)
        await waitUntil { fixture.requests == 1 }
        expect(store.isChecking, "the automatic check is in flight")
        store.stop()
        fixture.respond(feed(version: "1.2.0"))
        await waitUntil { !store.isChecking }
        expect(fixture.wasCancelled, "stopping cancels the in-flight automatic check")
        expect(store.latest?.version == AppVersion("1.1.0"), "a cancelled response is discarded")
        expect(offers == 0, "cancellation cannot announce the cached pending update")
        expect(try Data(contentsOf: file) == originalCache, "a cancelled check leaves the cache intact")

        store.start(after: .zero)
        await waitUntil { fixture.requests == 2 }
        fixture.respond(feed(version: "1.2.0"))
        await waitUntil { offers == 1 }
        expect(!fixture.wasCancelled, "re-enabling starts a fresh check")
        expect(store.update?.version == AppVersion("1.2.0"), "the restarted check adopts the release")
        store.start(after: .zero)
        try await Task.sleep(for: .milliseconds(10))
        expect(fixture.requests == 2, "restarting respects the cached check time")
        expect(offers == 1, "restarting never repeats an announcement already shown")

        store.stop()
        let manual = Task { await store.check() }
        await waitUntil { fixture.requests == 3 }
        store.stop()
        fixture.respond(feed(version: "1.3.0"))
        let answered = await manual.value
        expect(answered, "manual checking still works with automatic checking stopped")
        expect(!fixture.wasCancelled, "stopping the pump does not cancel a manual check")
        expect(store.update?.version == AppVersion("1.3.0"), "manual checking receives a newer release")
        expect(offers == 1, "manual checking does not restart automatic announcements")

        let reopened = makeStore(file: file, fixture: fixture)
        expect(reopened.latest == store.latest, "manual checking persists the release")
    }

    static func seedCache(at file: URL) throws {
        guard let release = ReleaseFeed.newest(
            from: feed(version: "1.1.0"), channel: .stable, architecture: .current)
        else { fatalError("the fixture release must be installable") }
        let cache: [String: Any] = [
            "lastCheckedAt": Date.distantPast.timeIntervalSinceReferenceDate,
            "latest": try JSONSerialization.jsonObject(with: JSONEncoder().encode(release))
        ]
        try JSONSerialization.data(withJSONObject: cache).write(to: file)
    }

    static func makeStore(file: URL, fixture: FetchFixture) -> UpdateCheckStore {
        UpdateCheckStore(
            channel: .stable, runningVersion: AppVersion("1.0.0"), fileURL: file,
            fetch: { await fixture.fetch() })
    }

    static func makeFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("update-check-test-\(UUID().uuidString).json")
    }

    static func feed(version: String) -> Data {
        Data("""
            [{"tag_name":"v\(version)","prerelease":false,"draft":false,"assets":[
                {"name":"Tinycast-Universal-\(version).zip","size":100,
                 "browser_download_url":"https://example.com/update.zip"}
            ]}]
            """.utf8)
    }

    static func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        expect(condition(), "the check completes within the test deadline")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    @MainActor
    final class FetchFixture {
        var requests = 0
        var wasCancelled = false
        private var response: CheckedContinuation<Data?, Never>?

        func fetch() async -> Data? {
            requests += 1
            let data = await withCheckedContinuation { response = $0 }
            wasCancelled = Task.isCancelled
            return data
        }

        func respond(_ data: Data) {
            let pending = response
            response = nil
            pending?.resume(returning: data)
        }
    }
}
