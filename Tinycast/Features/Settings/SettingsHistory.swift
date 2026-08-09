/// Browser semantics: choosing a pane truncates what was ahead, and re-choosing it is not a move.
struct SettingsHistory {
    private(set) var current: SettingsTab
    private var back: [SettingsTab] = []
    private var forward: [SettingsTab] = []

    init(current: SettingsTab) {
        self.current = current
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    mutating func select(_ tab: SettingsTab) {
        guard tab != current else { return }
        back.append(current)
        forward.removeAll()
        current = tab
    }

    mutating func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(current)
        current = previous
    }

    mutating func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(current)
        current = next
    }
}
