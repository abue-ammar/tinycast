import Foundation

@MainActor
@Observable
final class WindowSwitchSession {
    private(set) var snapshot: [WindowSwitchEntry] = []
    /// The rows the list reads: ranked once per query change, so one keystroke ranks once.
    private(set) var filtered: [WindowSwitchEntry] = []

    private var query = ""
    /// Live AX handles, so they are never observed and never outlive the show.
    @ObservationIgnored private var elements: [Int: WindowSwitchSweep.Element] = [:]

    func present(_ snapshot: WindowSwitchSweep.Snapshot) {
        self.snapshot = WindowSwitchOrder.sorted(snapshot.entries)
        elements = snapshot.elements
        applyQuery()
    }

    func element(for handle: Int) -> WindowSwitchSweep.Element? { elements[handle] }

    func reset() {
        snapshot = []
        filtered = []
        elements = [:]
        query = ""
    }

    func filter(_ query: String) {
        self.query = query
        applyQuery()
    }

    private func applyQuery() {
        filtered = WindowSwitchQuery.rank(
            snapshot, for: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
