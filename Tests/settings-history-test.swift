import Foundation

/// Pins the back/forward semantics of the Settings titlebar. Compiles the shipped `SettingsHistory`
/// and `SettingsTab`, so a pane added to the sidebar can't quietly change how navigation behaves.
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

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func startsEmpty() {
        let history = SettingsHistory(current: .general)
        expect(history.current == .general, "a fresh history shows the pane it was opened on")
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

    /// Clicking the row that is already selected — the commonest sidebar interaction — must not
    /// stack duplicate entries, or Back would walk through the same pane repeatedly.
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
    //
    // The sidebar renders groups, not `allCases`, so a pane left out of every group would be
    // unreachable while still compiling and still routable from a menu.

    static func sidebarCoversEveryPane() {
        let grouped = SettingsSection.allCases.flatMap(\.tabs)
        expect(
            Set(grouped) == Set(SettingsTab.allCases),
            "every pane appears in exactly one sidebar group")
        expect(grouped.count == SettingsTab.allCases.count, "and none appears twice")
    }

    /// A selectable `List` flattens section and row IDs into one namespace. When both were `Int`
    /// raw values the ranges overlapped, and SwiftUI dropped whole groups from the sidebar.
    static func sidebarIdentityNamespacesAreDisjoint() {
        let sections = Set(SettingsSection.allCases.map { AnyHashable($0.id) })
        let tabs = Set(SettingsTab.allCases.map { AnyHashable($0.id) })
        expect(
            sections.isDisjoint(with: tabs),
            "no sidebar group shares an identity with a pane")
        expect(tabs.count == SettingsTab.allCases.count, "and every pane's identity is its own")
    }
}
