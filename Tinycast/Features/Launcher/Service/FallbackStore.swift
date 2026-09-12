import Foundation

/// The reader's fallback list: which of them are offered, and in what order.
@MainActor
@Observable
final class FallbackStore {
    private let defaults = UserDefaults.standard
    private let orderKey = "fallbackOrder"
    private let disabledKey = "disabledFallbacks"

    private(set) var orderedIDs: [String]
    private(set) var disabledIDs: Set<String>

    init() {
        orderedIDs = defaults.stringArray(forKey: orderKey) ?? []
        disabledIDs = Set(defaults.stringArray(forKey: disabledKey) ?? [])
    }

    func ordered(_ available: [Fallback]) -> [Fallback] {
        Fallback.ordered(available, by: orderedIDs)
    }

    func isEnabled(_ fallback: Fallback) -> Bool { !disabledIDs.contains(fallback.id) }

    func setEnabled(_ enabled: Bool, for fallback: Fallback) {
        if enabled {
            disabledIDs.remove(fallback.id)
        } else {
            disabledIDs.insert(fallback.id)
        }
        defaults.set(Array(disabledIDs), forKey: disabledKey)
    }

    /// Swaps two neighbours and stores the whole visible order, so no later row can drift.
    func exchange(_ fallback: Fallback, with other: Fallback, in order: [Fallback]) {
        guard let from = order.firstIndex(of: fallback), let to = order.firstIndex(of: other) else {
            return
        }
        var updated = order
        updated.swapAt(from, to)
        orderedIDs = updated.map(\.id)
        defaults.set(orderedIDs, forKey: orderKey)
    }
}
