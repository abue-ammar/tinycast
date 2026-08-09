import Observation

/// Not on `AppCore`: one window's session, released in `windowWillClose` so history never survives.
@MainActor
@Observable
final class SettingsNavigationState {
    private var history: SettingsHistory

    init(tab: SettingsTab) {
        history = SettingsHistory(current: tab)
    }

    var tab: SettingsTab { history.current }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    func select(_ tab: SettingsTab) { history.select(tab) }
    func goBack() { history.goBack() }
    func goForward() { history.goForward() }
}
