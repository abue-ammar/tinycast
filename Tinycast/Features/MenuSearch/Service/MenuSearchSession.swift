import Foundation

@MainActor
@Observable
final class MenuSearchSession {
    typealias WalkOperation = @Sendable (pid_t, _ showsAppleMenu: Bool) async -> [MenuSearchItem]

    enum State {
        case idle
        case reading
        case ready
    }

    private(set) var state: State = .idle
    private(set) var target: MenuSearchTarget = .noApplication
    private(set) var snapshot: [MenuSearchItem] = []
    /// The rows the list reads: filtered once per query change, so one keystroke ranks once.
    private(set) var filtered: [MenuSearchItem] = []
    /// Whether a query narrows the rows, so the list groups by menu only while browsing.
    private(set) var isSearching = false

    private var query = ""
    private var revision = 0
    @ObservationIgnored private var walkTask: Task<Void, Never>?
    @ObservationIgnored private let walkOperation: WalkOperation

    init() {
        walkOperation = { pid, showsAppleMenu in
            await Task.detached(priority: .userInitiated) {
                let deadline = ContinuousClock.now + AXMenuAccess.walkBudget
                let application = AXMenuAccess.application(for: pid)
                let bar = AXMenuAccess.readTopLevel(in: application, deadline: deadline)
                let roots = showsAppleMenu ? bar : MenuSnapshotPolicy.excludingAppleMenu(bar)
                return MenuSnapshotPolicy.collect(roots) { ContinuousClock.now >= deadline }
            }.value
        }
    }

    init(walkOperation: @escaping WalkOperation) {
        self.walkOperation = walkOperation
    }

    var targetName: String? {
        switch target {
        case .searchable(let name), .excluded(let name), .menuLess(let name): name
        case .selfTarget, .noApplication: nil
        }
    }

    func present(target: MenuSearchTarget, snapshot: [MenuSearchItem]) {
        revision &+= 1
        walkTask?.cancel()
        walkTask = nil
        self.target = target
        self.snapshot = snapshot
        state = .ready
        applyQuery()
    }

    func startWalk(target: MenuSearchTarget, pid: pid_t, showsAppleMenu: Bool) {
        revision &+= 1
        walkTask?.cancel()
        self.target = target
        snapshot = []
        filtered = []
        state = .reading
        let revision = self.revision
        walkTask = Task { [weak self] in
            let items = await self?.walkOperation(pid, showsAppleMenu) ?? []
            guard let self, self.revision == revision else { return }
            self.snapshot = items
            self.state = .ready
            self.applyQuery()
            self.walkTask = nil
        }
    }

    func reset() {
        revision &+= 1
        walkTask?.cancel()
        walkTask = nil
        target = .noApplication
        snapshot = []
        filtered = []
        query = ""
        isSearching = false
        state = .idle
    }

    func filter(_ query: String) {
        self.query = query
        applyQuery()
    }

    private func applyQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = !trimmed.isEmpty
        guard isSearching else {
            filtered = snapshot
            return
        }
        filtered = MenuSearchQuery.rank(snapshot, for: trimmed)
    }
}
