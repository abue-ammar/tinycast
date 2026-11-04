import Foundation

@MainActor
@Observable
final class FallbackStore {
    private let defaults = UserDefaults.standard
    private let orderKey = "fallbackOrder"
    private let disabledKey = "disabledFallbacks"
    private let learnsOrderKey = "fallbackLearnsOrder"
    private let usageKey = "fallbackUsage"

    private(set) var orderedIDs: [String]
    private(set) var disabledIDs: Set<String>
    private(set) var learnsOrder: Bool
    private(set) var usage: [String: FallbackUsage]

    init() {
        orderedIDs = defaults.stringArray(forKey: orderKey) ?? []
        disabledIDs = Set(defaults.stringArray(forKey: disabledKey) ?? [])
        learnsOrder = defaults.object(forKey: learnsOrderKey) as? Bool ?? true
        usage =
            defaults.data(forKey: usageKey)
            .flatMap { try? JSONDecoder().decode([String: FallbackUsage].self, from: $0) } ?? [:]
    }

    func ordered(_ available: [Fallback]) -> [Fallback] {
        Fallback.ordered(available, by: orderedIDs)
    }

    /// The launcher's order, where Settings keeps showing the one a reader arranged by hand.
    func ranked(_ ordered: [Fallback]) -> [Fallback] {
        learnsOrder ? Fallback.ranked(ordered, by: usage, at: Date()) : ordered
    }

    func setLearnsOrder(_ learns: Bool) {
        learnsOrder = learns
        defaults.set(learns, forKey: learnsOrderKey)
    }

    func recordRun(of fallback: Fallback) {
        guard learnsOrder else { return }
        setUsage(FallbackUsage.recordingRun(of: fallback.id, in: usage, at: Date()))
    }

    func resetUsage() {
        setUsage([:])
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

    private func setUsage(_ updated: [String: FallbackUsage]) {
        usage = updated
        defaults.set(try? JSONEncoder().encode(updated), forKey: usageKey)
    }
}
