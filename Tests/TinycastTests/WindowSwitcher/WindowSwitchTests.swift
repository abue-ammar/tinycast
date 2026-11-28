import Testing

@testable import Tinycast

@MainActor
struct WindowSwitchTests {
    @Test func identityIsTheSweepHandle() {
        #expect(window(7).id == "7")
    }

    @Test(arguments: [("Safari", "Notes.md", "Notes.md"), ("Preview", "", "Preview"), ("Preview", "   ", "Preview")])
    func titleFallsBackToTheAppName(_ app: String, _ title: String, _ displayTitle: String) {
        #expect(window(0, app: app, title: title).displayTitle == displayTitle)
    }

    @Test func searchUsesTheTitleAsNameAndAppAsOwner() {
        let aliases = window(0, title: "Inbox").searchFields().aliases
        #expect(aliases.contains { $0.text == "Inbox" && $0.role == .name })
        #expect(aliases.contains { $0.text == "Safari" && $0.role == .owner })
    }

    @Test func activeWindowsSortByAppRankBeforeMinimizedWindows() {
        let entries = [
            window(0, app: "Mail", rank: 2),
            window(1, minimized: true),
            window(2),
            window(3),
            window(4, app: "Zed", rank: .max)
        ]
        #expect(WindowSwitchOrder.sorted(entries).map(\.handle) == [2, 3, 0, 4, 1])
    }

    @Test func orderingIsIndependentOfSweepOrderAndKeepsEveryWindow() {
        let apps = ["Mail", "Safari", "Zed"]
        let entries = (0..<12).map {
            window($0, app: apps[$0 % 3], minimized: $0 % 4 == 0, rank: $0 % 3)
        }
        let sorted = WindowSwitchOrder.sorted(entries)
        #expect(sorted.map(\.handle) == WindowSwitchOrder.sorted(entries.reversed()).map(\.handle))
        #expect(sorted.map(\.handle).sorted() == entries.map(\.handle).sorted())
        let firstMinimized = sorted.firstIndex(where: \.isMinimized) ?? sorted.count
        #expect(sorted[firstMinimized...].allSatisfy { $0.isMinimized })
    }

    @Test(arguments: [
        (true, false, true, true), (true, true, true, true), (false, true, true, true),
        (false, false, true, false), (false, true, false, false)
    ])
    func standardAndMinimizableMinimizedWindowsAreOffered(
        _ standard: Bool, _ minimized: Bool, _ canMinimize: Bool, _ offered: Bool
    ) {
        #expect(WindowSwitchPolicy.isSwitchable(
            isStandardWindow: standard, isMinimized: minimized, canMinimize: canMinimize) == offered)
    }

    @Test(arguments: [("", [0, 1, 2]), ("Safari", [1, 2]), ("zzz", [])])
    func searchKeepsSweepOrderForEqualMatches(_ query: String, _ handles: [Int]) {
        #expect(WindowSwitchQuery.rank(searchableWindows, for: query).map(\.handle) == handles)
    }

    @Test func exactTitleLeadsTheResults() throws {
        let first = try #require(WindowSwitchQuery.rank(searchableWindows, for: "Inbox").first)
        #expect(first.handle == 1)
    }

    @Test(arguments: ["", "Tab"])
    func resultLimitAppliesEvenWhenEveryWindowMatches(_ query: String) {
        let entries = (0..<(WindowSwitchQuery.resultLimit + 50)).map { window($0, title: "Tab \($0)") }
        #expect(WindowSwitchQuery.rank(entries, for: query).count == WindowSwitchQuery.resultLimit)
    }

    private var searchableWindows: [WindowSwitchEntry] {
        [window(0, app: "Mail", title: "Drafts"), window(1, title: "Inbox"), window(2, title: "Inbox archive")]
    }

    private func window(
        _ handle: Int, app: String = "Safari", title: String = "Window", minimized: Bool = false, rank: Int = 0
    ) -> WindowSwitchEntry {
        WindowSwitchEntry(
            handle: handle, appName: app, bundleID: "com.example.\(app.lowercased())",
            iconURL: nil, iconStamp: 0, title: title, isMinimized: minimized, appRank: rank)
    }
}
