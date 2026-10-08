struct ExtensionSearchState: Sendable {
    struct Screen: Equatable, Sendable {
        var query = ""
        var selection = 0
    }

    private var parents: [Screen] = []
    private var restored: Screen?
    private var depth = 1

    mutating func navigate(to depth: Int, current: Screen) -> Screen? {
        guard depth >= 1, depth != self.depth else { return nil }
        let oldDepth = self.depth
        self.depth = depth
        restored = nil
        if depth > oldDepth {
            parents.removeLast(max(0, parents.count - (oldDepth - 1)))
            parents.append(current)
            while parents.count < depth - 1 { parents.append(Screen()) }
            return Screen()
        }
        let parent = parents.indices.contains(depth - 1) ? parents[depth - 1] : Screen()
        parents.removeLast(max(0, parents.count - (depth - 1)))
        restored = parent
        return parent
    }

    mutating func queryChanged(to query: String) {
        if restored?.query != query { restored = nil }
    }

    func landingSelection(for query: String, rowCount: Int) -> Int {
        guard let restored, restored.query == query else { return 0 }
        return min(max(restored.selection, 0), max(rowCount - 1, 0))
    }
}
