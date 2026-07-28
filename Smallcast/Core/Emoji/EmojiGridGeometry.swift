/// Pure flat-index navigation math over sectioned rows of `columns` cells; vertical moves keep the column and spill into the adjacent section. Foundation-free so the Tools harness can compile the real sources.
struct EmojiGridGeometry {
    let counts: [Int]
    let columns: Int
    private let starts: [Int]

    init(counts: [Int], columns: Int = 8) {
        self.counts = counts
        self.columns = columns
        var starts: [Int] = []
        var running = 0
        for count in counts {
            starts.append(running)
            running += count
        }
        self.starts = starts
    }

    private func section(of sel: Int) -> Int? {
        for (index, start) in starts.enumerated().reversed() where sel >= start {
            return counts[index] > 0 && sel < start + counts[index] ? index : nil
        }
        return nil
    }

    func down(from sel: Int) -> Int {
        guard let s = section(of: sel) else { return sel }
        let local = sel - starts[s]
        let candidate = local + columns
        if candidate < counts[s] { return starts[s] + candidate }
        // A lower partial row in this section clamps to its last cell before spilling over.
        if local / columns < (counts[s] - 1) / columns { return starts[s] + counts[s] - 1 }
        guard s + 1 < counts.count else { return sel }
        return starts[s + 1] + min(local % columns, counts[s + 1] - 1)
    }

    func up(from sel: Int) -> Int {
        guard let s = section(of: sel) else { return sel }
        let local = sel - starts[s]
        if local - columns >= 0 { return starts[s] + local - columns }
        guard s > 0 else { return sel }
        let previousCount = counts[s - 1]
        let lastRowStart = ((previousCount - 1) / columns) * columns
        return starts[s - 1] + min(lastRowStart + local % columns, previousCount - 1)
    }
}
