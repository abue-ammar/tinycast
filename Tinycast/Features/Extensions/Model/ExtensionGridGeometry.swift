/// Flat-index navigation over a `Grid`'s sections, so ↑/↓ move a whole row and keep their column.
struct ExtensionGridGeometry {
    /// Selectable cells per section, in visible order. An empty section is never included.
    let counts: [Int]
    let columns: Int
    /// Flat index each section begins at.
    private let starts: [Int]

    init(counts: [Int], columns: Int) {
        self.counts = counts
        self.columns = max(1, columns)
        var starts: [Int] = []
        var running = 0
        for count in counts {
            starts.append(running)
            running += count
        }
        self.starts = starts
    }

    var cellCount: Int { counts.reduce(0, +) }

    func down(from index: Int) -> Int {
        guard let section = section(of: index) else { return index }
        let local = index - starts[section]
        let below = local + columns
        if below < counts[section] { return starts[section] + below }
        // A shorter last row keeps the selection in this section rather than skipping past it.
        if local / columns < (counts[section] - 1) / columns {
            return starts[section] + counts[section] - 1
        }
        guard section + 1 < counts.count else { return index }
        return starts[section + 1] + min(local % columns, counts[section + 1] - 1)
    }

    func up(from index: Int) -> Int {
        guard let section = section(of: index) else { return index }
        let local = index - starts[section]
        if local >= columns { return starts[section] + local - columns }
        guard section > 0 else { return index }
        let previous = counts[section - 1]
        let lastRowStart = ((previous - 1) / columns) * columns
        return starts[section - 1] + min(lastRowStart + local % columns, previous - 1)
    }

    private func section(of index: Int) -> Int? {
        for (position, start) in starts.enumerated().reversed() where index >= start {
            return index < start + counts[position] ? position : nil
        }
        return nil
    }
}
