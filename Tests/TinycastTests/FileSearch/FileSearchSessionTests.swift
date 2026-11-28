import Foundation
import Testing

@testable import Tinycast

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct FileSearchSessionTests {
    @Test func exactRootCanPublishBeforeThereIsAnIndexSnapshot() async throws {
        let index = FileIndex()
        let policy = FileSearchPolicy(
            scopes: [], ignorePatterns: [], includesHiddenFiles: false, homeDirectory: URL(filePath: "/"))
        index.replace(with: nil, policy: policy)
        let session = FileSearchSession(index: index)
        let search = try #require(session.search("/"))
        await search.value

        #expect(session.state == .ready)
        #expect(session.results.map(\.id) == ["/"])
    }

    @Test func aRunningSearchKeepsOnlyTheNewestPendingQuery() async throws {
        let paused = PausedSearch()
        defer { paused.resume() }
        let log = SearchLog(pausedQuery: "a", pause: paused)
        let session = FileSearchSession(searchOperation: log.search)
        let first = try #require(session.search("a"))
        await paused.waitForStart()
        session.search("an")
        let newest = try #require(session.search("annual"))
        paused.resume()
        await first.value
        await newest.value

        #expect(await log.calls == ["a", "annual"])
        #expect(session.state == .ready)
        #expect(session.results.first?.name == "annual")
    }

    @Test func aSupersedingSearchWaitsForTheWorker() async throws {
        let paused = PausedSearch()
        defer { paused.resume() }
        let log = SearchLog(pausedQuery: "first", pause: paused)
        let session = FileSearchSession(searchOperation: log.search)
        let first = try #require(session.search("first"))
        await paused.waitForStart()
        let second = try #require(session.search("second"))
        paused.resume()
        await first.value
        await second.value

        #expect(await log.calls == ["first", "second"])
        #expect(await log.maximumActive == 1)
        #expect(session.state == .ready)
        #expect(session.results.first?.name == "second")
    }

    @Test func cancelDropsPendingWorkAndDiscardsTheRunningResult() async throws {
        let paused = PausedSearch()
        defer { paused.resume() }
        let log = SearchLog(pausedQuery: "running", pause: paused)
        let session = FileSearchSession(searchOperation: log.search)
        let running = try #require(session.search("running"))
        await paused.waitForStart()
        session.search("queued")
        session.cancel()
        paused.resume()
        await running.value

        #expect(await log.calls == ["running"])
        #expect(session.state == .idle)
        #expect(session.results.isEmpty)
    }

    @Test func cancelIsIdempotentAndTheSameQueryCanRunAgain() async throws {
        let log = SearchLog()
        let session = FileSearchSession(searchOperation: log.search)
        session.cancel()
        #expect(session.state == .idle)
        #expect(session.results.isEmpty)

        let first = try #require(session.search("report"))
        await first.value
        #expect(session.state == .ready)
        #expect(session.results.first?.name == "report")
        session.cancel()
        session.cancel()
        #expect(session.state == .idle)
        #expect(session.results.isEmpty)

        let second = try #require(session.search("report"))
        await second.value
        #expect(session.state == .ready)
        #expect(session.results.first?.name == "report")
        #expect(await log.calls == ["report", "report"])
    }

    @Test func refreshPreparesRecentsAndRerunsTheVisibleQueryBeforeUpdatingRecents() async throws {
        let log = SearchLog()
        let session = FileSearchSession(searchOperation: log.search)
        await session.refresh().value
        let search = try #require(session.search("report"))
        await search.value
        #expect(session.state == .ready)
        await session.refresh().value
        #expect(session.state == .ready)

        #expect(await log.calls == ["", "report", "report", ""])
    }

    @Test func aNewerRecentRefreshSupersedesOneWaitingForTheVisibleQuery() async throws {
        let paused = PausedSearch()
        defer { paused.resume() }
        let log = SearchLog(pausedQuery: "report", pause: paused)
        let session = FileSearchSession(searchOperation: log.search)
        let search = try #require(session.search("report"))
        await paused.waitForStart()
        let delayed = session.refresh()
        await session.refreshRecent().value
        paused.resume()
        await search.value
        await delayed.value

        #expect(await log.calls == ["report", "", "report"])
        session.cancel()
        let recents = try #require(session.search(""))
        #expect(!session.results.isEmpty)
        await recents.value
    }

    @Test func keptRecentsOpenImmediatelyEvenAfterCancel() async throws {
        let paused = PausedSearch()
        defer { paused.resume() }
        let log = SearchLog(pausedQuery: "report", pause: paused)
        let session = FileSearchSession(searchOperation: log.search)
        await session.refresh().value

        let first = try #require(session.search(""))
        #expect(session.state == .ready)
        #expect(!session.results.isEmpty)
        await first.value
        session.cancel()

        let reopened = try #require(session.search(""))
        #expect(!session.results.isEmpty)
        let typed = try #require(session.search("report"))
        await paused.waitForStart()
        #expect(session.results.first?.name != "report")
        paused.resume()
        await reopened.value
        await typed.value
    }

    @Test func refreshingRecentsLeavesTheOpenResultsAlone() async throws {
        let log = SearchLog()
        let session = FileSearchSession(searchOperation: log.search)
        let search = try #require(session.search("report"))
        await search.value
        #expect(session.state == .ready)

        await session.refreshRecent().value
        #expect(session.results.first?.name == "report")
        session.cancel()
        let recents = try #require(session.search(""))
        #expect(!session.results.isEmpty)
        await recents.value
    }

    @Test func aBlankQueryRequestsRecentsBeforeTheTypedQuery() async throws {
        let log = SearchLog()
        let session = FileSearchSession(searchOperation: log.search)
        let blank = try #require(session.search(""))
        await blank.value
        #expect(session.state == .ready)
        let typed = try #require(session.search("report"))
        await typed.value
        #expect(session.state == .ready)
        #expect(session.results.first?.name == "report")
        #expect(await log.calls == ["", "report"])
    }

    @Test func changingOnlyTheFilterRerunsTheQueryOnce() async throws {
        let log = SearchLog()
        let session = FileSearchSession(searchOperation: log.search)
        let all = try #require(session.search("report"))
        await all.value
        #expect(session.state == .ready)
        let images = try #require(session.search("report", filter: .images))
        await images.value
        #expect(session.state == .ready)

        let repeated = session.search("report", filter: .images)
        await repeated?.value
        #expect(await log.calls == ["report", "report [Images]"])
    }

    private actor SearchLog {
        let pausedQuery: String?
        let pause: PausedSearch?
        private var active = 0
        private var didPause = false
        private(set) var calls: [String] = []
        private(set) var maximumActive = 0

        init(pausedQuery: String? = nil, pause: PausedSearch? = nil) {
            self.pausedQuery = pausedQuery
            self.pause = pause
        }

        func search(_ query: String, _ filter: FileSearchFilter) async -> [FileSearchResult] {
            active += 1
            defer { active -= 1 }
            maximumActive = max(maximumActive, active)
            calls.append(filter == .all ? query : "\(query) [\(filter.title)]")
            if query == pausedQuery, let pause, !didPause {
                didPause = true
                await pause.suspend()
            }
            let home = URL(filePath: "/Users/test")
            return [
                FileSearchResult(url: home.appending(path: query), isDirectory: false, homeDirectory: home)
            ]
        }
    }

    private struct PausedSearch: Sendable {
        private let started = AsyncStream<Void>.makeStream()
        private let released = AsyncStream<Void>.makeStream()

        func waitForStart() async {
            var iterator = started.stream.makeAsyncIterator()
            _ = await iterator.next()
        }

        func suspend() async {
            started.continuation.yield()
            started.continuation.finish()
            var iterator = released.stream.makeAsyncIterator()
            _ = await iterator.next()
        }

        func resume() {
            released.continuation.finish()
        }
    }
}
