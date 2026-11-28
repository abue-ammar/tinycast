import Foundation
import Testing

@testable import Tinycast

@MainActor
struct RankingTests {
    private let scratch: ScratchDirectory
    private let clock = Clock()
    private let store: LauncherRankingStore
    private let file: URL
    private let safari = "com.apple.Safari"
    private let slack = "com.tinyspeck.slackmacgap"
    private let day: TimeInterval = 86_400

    init() throws {
        let scratch = try ScratchDirectory("ranking")
        let file = scratch.url.appending(path: "ranking.json")
        let clock = clock
        store = LauncherRankingStore(fileURL: file) { clock.now }
        self.file = file
        self.scratch = scratch
    }

    @Test(arguments: [
        (" wha \n", "wha"), ("WhA", "wha"), ("Café", "cafe"), ("ｃａｆｅ", "cafe"), ("微信", "wei xin")
    ])
    func learnedTermsUseTheSameFoldAsMatching(_ query: String, _ term: String) {
        #expect(LauncherRankingStore.normalize(query) == term)
    }

    @Test func foldingDoesNotUseTheCurrentLanguage() {
        let normalized = LauncherRankingStore.normalize("I")
        #expect(normalized == "i")
        #expect(normalized != "I".folding(options: .caseInsensitive, locale: Locale(identifier: "tr_TR")))
    }

    @Test func visitsAddOneHundredAndDecayWithATenDayHalfLife() async {
        #expect(usage(safari) == .unused)
        #expect(store.isEmpty)

        store.visit(itemKey: safari, query: "saf")
        #expect(abs(usage(safari).frecency - 101) < 0.001)
        #expect(store.hasRanking(for: safari))
        #expect(!store.isEmpty)

        clock.now += 10 * day
        #expect(abs(usage(safari).frecency - 50.5) < 0.001)
        store.visit(itemKey: safari, query: nil)
        #expect(abs(usage(safari).frecency - 150.5) < 0.001)

        clock.now += 200 * day
        #expect(usage(safari).frecency == 1)
        await store.flush()
    }

    @Test(arguments: [(0.0, true), (3, true), (30, false)])
    func laterAnchorScoresHigherUntilBothVisitsFloor(_ days: Double, _ laterWins: Bool) {
        let now = clock.now.addingTimeInterval(210 * day)
        let early = LauncherVisit(anchor: now + 5 * day, openedAt: now, searchTerms: [])
        let late = LauncherVisit(anchor: now + 6 * day, openedAt: now, searchTerms: [])
        let date = now + days * day
        let earlyScore = LauncherRankingStore.usage(of: early, at: date).frecency
        let lateScore = LauncherRankingStore.usage(of: late, at: date).frecency

        if laterWins {
            #expect(lateScore > earlyScore)
        } else {
            #expect(lateScore == earlyScore)
        }
    }

    @Test func theNewestThreeDistinctTermsStayUntilTheVisitAgesOut() async {
        store.visit(itemKey: slack, query: " Sa ")
        #expect(usage(slack).searchTerms == ["sa"])

        for term in ["sl", "slack", "sa", "s"] {
            store.visit(itemKey: slack, query: term)
        }
        #expect(usage(slack).searchTerms == ["slack", "sa", "s"])

        store.visit(itemKey: slack, query: "")
        store.visit(itemKey: slack, query: String(repeating: "x", count: 65))
        #expect(usage(slack).searchTerms == ["slack", "sa", "s"])

        clock.now += 18 * day
        #expect(usage(slack).searchTerms.isEmpty)
        #expect(usage(slack).frecency > 1)
        store.visit(itemKey: slack, query: "sl")
        #expect(usage(slack).searchTerms == ["sa", "s", "sl"])
        await store.flush()
    }

    @Test func reloadPrunesFlooredEntriesAndPreservesLiveVisits() async throws {
        seedVisitHistory()
        await store.flush()

        let clock = clock
        let reloaded = LauncherRankingStore(fileURL: file) { clock.now }
        let saved = try #require(store.visits[slack])
        let restored = try #require(reloaded.visits[slack])
        #expect(restored == saved)
        #expect(!reloaded.hasRanking(for: safari))
        #expect(reloaded.hasRanking(for: slack))
    }

    @Test func resettingEntriesInvalidatesRankingOnlyForAnActualChange() async {
        seedVisitHistory()
        let revision = store.revision
        store.reset(itemKey: slack)
        #expect(!store.hasRanking(for: slack))
        #expect(store.revision != revision)

        let updatedRevision = store.revision
        store.reset(itemKey: "missing")
        #expect(store.revision == updatedRevision)

        store.visit(itemKey: "a", query: nil)
        store.visit(itemKey: "b", query: nil)
        store.resetAll()
        #expect(store.isEmpty)
        await store.flush()
    }

    @Test func importKeepsOnlyLiveEntriesWithKeys() async {
        let now = clock.now.addingTimeInterval(228 * day)
        clock.now = now
        store.replace([
            "kept": LauncherVisit(anchor: now + day, openedAt: now, searchTerms: ["k"]),
            "stale": LauncherVisit(anchor: now - day, openedAt: now - 90 * day, searchTerms: []),
            "": LauncherVisit(anchor: now + day, openedAt: now, searchTerms: [])
        ])
        #expect(Array(store.visits.keys) == ["kept"])
        await store.flush()
    }

    private func usage(_ key: String) -> LauncherUsage {
        store.snapshot().usage(for: key)
    }

    private func seedVisitHistory() {
        store.visit(itemKey: safari, query: "saf")
        clock.now += 10 * day
        store.visit(itemKey: safari, query: nil)
        clock.now += 200 * day
        for term in [" Sa ", "sl", "slack", "sa", "s", "", String(repeating: "x", count: 65)] {
            store.visit(itemKey: slack, query: term)
        }
        clock.now += 18 * day
        store.visit(itemKey: slack, query: "sl")
    }

    private final class Clock {
        var now = Date(timeIntervalSince1970: 2_000_000_000)
    }
}
