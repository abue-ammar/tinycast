/// A few-slot LRU memo. The key must name every dependency, since nothing else invalidates a slot.
/// Multi-slot so backspacing through a mistyped query replays cached results instead of
/// re-scoring every entry on each keystroke.
struct Memo<Key: Equatable, Value> {
    private var slots: [(key: Key, value: Value)] = []
    private let capacity: Int

    init(capacity: Int = 8) { self.capacity = capacity }

    mutating func value(for key: Key, build: () -> Value) -> Value {
        if let index = slots.firstIndex(where: { $0.key == key }) {
            let hit = slots.remove(at: index)
            slots.append(hit)
            return hit.value
        }
        let built = build()
        if slots.count >= capacity { slots.removeFirst() }
        slots.append((key, built))
        return built
    }
}
