import Foundation

/// Compiles the shipped `SettingsHistory`, so a new pane can't change navigation.
@main
@MainActor
struct SettingsHistoryTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        startsEmpty()
        selectingPushes()
        reselectingIsNotANavigation()
        roundTrips()
        aNewBranchDiscardsTheOldOne()
        clampsAtBothEnds()
        sidebarCoversEveryPane()
        sidebarIdentityNamespacesAreDisjoint()
        catalogCoversEveryPane()
        catalogIdentitiesAreUnique()
        catalogFindsKnownRows()
        catalogRanksTitlesFirst()
        catalogAnchorsMatchTheirPane()
        revealingRecordsANewRequestEachTime()
        flashOutlivesThePaneThatLitIt()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func startsEmpty() {
        let history = SettingsHistory(current: .general)
        expect(!history.canGoBack, "and has nowhere to go back to")
        expect(!history.canGoForward, "or forward to")
    }

    static func selectingPushes() {
        var history = SettingsHistory(current: .general)
        history.select(.clipboard)
        expect(history.current == .clipboard, "selecting shows the new pane")
        expect(history.canGoBack, "and leaves the old one behind us")
        expect(!history.canGoForward, "with nothing ahead")
    }

    /// Reselecting must not stack entries, or Back walks the same pane repeatedly.
    static func reselectingIsNotANavigation() {
        var history = SettingsHistory(current: .general)
        history.select(.general)
        expect(!history.canGoBack, "re-selecting the current pane pushes nothing")

        history.select(.backup)
        history.select(.backup)
        history.goBack()
        expect(history.current == .general, "and one Back still reaches the pane before it")
    }

    static func roundTrips() {
        var history = SettingsHistory(current: .general)
        history.select(.snippets)
        history.select(.emoji)

        history.goBack()
        expect(history.current == .snippets, "Back walks one entry at a time")
        expect(history.canGoForward, "and what we left becomes reachable again")

        history.goBack()
        expect(history.current == .general, "Back reaches the pane we opened on")

        history.goForward()
        history.goForward()
        expect(history.current == .emoji, "Forward retraces the same path")
        expect(!history.canGoForward, "and stops where we had got to")
    }

    static func aNewBranchDiscardsTheOldOne() {
        var history = SettingsHistory(current: .general)
        history.select(.snippets)
        history.select(.emoji)
        history.goBack()
        history.goBack()

        history.select(.about)
        expect(history.current == .about, "selecting after going back moves there")
        expect(!history.canGoForward, "and drops the branch we had backed out of")

        history.goBack()
        expect(history.current == .general, "while Back still reaches where we branched from")
    }

    static func clampsAtBothEnds() {
        var history = SettingsHistory(current: .general)
        history.goBack()
        expect(history.current == .general, "Back at the start is a no-op")
        history.goForward()
        expect(history.current == .general, "Forward with nothing ahead is a no-op")

        history.select(.about)
        history.goForward()
        expect(history.current == .about, "Forward at the tip is a no-op too")
    }

    // MARK: - Sidebar taxonomy
    // The sidebar renders groups, so a pane in none is unreachable but still compiles.

    static func sidebarCoversEveryPane() {
        let grouped = SettingsSection.allCases.flatMap(\.tabs)
        expect(
            Set(grouped) == Set(SettingsTab.allCases),
            "every pane appears in exactly one sidebar group")
        expect(grouped.count == SettingsTab.allCases.count, "and none appears twice")
    }

    /// A selectable `List` flattens section and row IDs into one namespace.
    static func sidebarIdentityNamespacesAreDisjoint() {
        let sections = Set(SettingsSection.allCases.map { AnyHashable($0.id) })
        let tabs = Set(SettingsTab.allCases.map { AnyHashable($0.id) })
        expect(
            sections.isDisjoint(with: tabs),
            "no sidebar group shares an identity with a pane")
        expect(tabs.count == SettingsTab.allCases.count, "and every pane's identity is its own")
    }

    // MARK: - Search catalog
    // A `Form` can't be asked what rows it holds, so the catalog is hand-written and can drift.

    static func catalogCoversEveryPane() {
        let covered = Set(SettingsSearchCatalog.entries.map(\.tab))
        expect(
            covered == Set(SettingsTab.allCases),
            "every pane is reachable from Settings search")
    }

    /// The results `List` is keyed by `id`; a duplicate would make two rows select as one.
    static func catalogIdentitiesAreUnique() {
        let ids = SettingsSearchCatalog.entries.map(\.id)
        expect(Set(ids).count == ids.count, "no two catalog entries share an identity")
    }

    static func catalogFindsKnownRows() {
        let cases: [(String, SettingsTab)] = [
            ("hyper", .general),
            ("caps lock", .general),
            ("launch at login", .general),
            ("paste history", .clipboard),
            ("window manage", .windowManagement),
            ("skin tone", .emoji),
            ("mcp", .ai)
        ]
        for (query, tab) in cases {
            let found = SettingsSearchCatalog.results(for: query).first
            expect(found?.tab == tab, "“\(query)” lands on \(tab.title)")
        }
    }

    /// The anchor carries the pane, so a row filed under the wrong one cannot be written.
    static func catalogAnchorsMatchTheirPane() {
        for entry in SettingsSearchCatalog.entries {
            guard let anchor = entry.anchor else { continue }
            expect(anchor.tab == entry.tab, "“\(entry.title)” is filed under its anchor's pane")
        }
        let panes = SettingsSearchCatalog.entries.filter { $0.anchor == nil }.map(\.tab)
        expect(Set(panes).count == panes.count, "and each pane is listed as a result exactly once")
    }

    /// A term found in the title has to beat the same term found only in a breadcrumb.
    static func catalogRanksTitlesFirst() {
        let results = SettingsSearchCatalog.results(for: "extensions")
        expect(results.first?.tab == .extensions, "“extensions” opens on its own pane")
        expect(
            SettingsSearchCatalog.results(for: "nothing here matches at all").isEmpty,
            "and an unmatched query returns nothing")
    }

    // MARK: - Revealing a section

    /// Picking the same result twice has to scroll and pulse again, not compare equal and do nothing.
    static func revealingRecordsANewRequestEachTime() {
        let navigation = SettingsNavigationState(tab: .general)
        expect(navigation.scrollRequest == nil, "a fresh window has nothing to reveal")

        navigation.select(.clipboard)
        expect(navigation.scrollRequest == nil, "and a plain pane selection asks for no scroll")

        navigation.select(.general, revealing: .section(.generalHyperKey))
        let first = navigation.scrollRequest
        expect(first?.target == .section(.generalHyperKey), "a result records what it wants revealed")
        expect(navigation.tab == .general, "and navigates to that section's pane")

        navigation.select(.general, revealing: .section(.generalHyperKey))
        expect(navigation.scrollRequest != first, "asking twice is two distinct requests")

        // A stale request must not clear the one that replaced it.
        if let first { navigation.clear(first) }
        expect(navigation.scrollRequest != nil, "clearing a superseded request is a no-op")
        if let live = navigation.scrollRequest { navigation.clear(live) }
        expect(navigation.scrollRequest == nil, "clearing the live one releases it")
    }

    /// The pulse outlives the pane that started it, and only its own owner may put it out.
    static func flashOutlivesThePaneThatLitIt() {
        let navigation = SettingsNavigationState(tab: .general)
        navigation.select(.clipboard, revealing: .row(.clipboardHistory, "Keep history for"))
        navigation.beginFlash(.row(.clipboardHistory, "Keep history for"))
        expect(navigation.flashing == .row(.clipboardHistory, "Keep history for"), "the revealed row is lit")

        navigation.endFlash(.section(.generalHyperKey))
        expect(navigation.flashing != nil, "another target can't put it out")
        navigation.endFlash(.row(.clipboardHistory, "Keep history for"))
        expect(navigation.flashing == nil, "its own owner can")

        // A jump that lands elsewhere must not leave the old light burning behind it.
        navigation.beginFlash(.row(.clipboardHistory, "Keep history for"))
        navigation.select(.general)
        expect(navigation.flashing == nil, "navigating away clears a stale pulse")
    }
}
