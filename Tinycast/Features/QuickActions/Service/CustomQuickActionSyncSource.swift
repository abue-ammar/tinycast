import Foundation

extension RecordSyncSource where Record == CustomQuickAction {
    /// The action syncs; which model runs it stays with each Mac's route overrides.
    static func customQuickActions(_ store: CustomQuickActionStore) -> Self {
        Self(
            .quickActions,
            records: { store.isAvailable ? store.actions : nil },
            save: { action in
                do {
                    if store.action(id: action.id) == nil {
                        try store.add(action)
                    } else {
                        try store.update(action)
                    }
                    return true
                } catch CustomQuickActionError.storageUnavailable {
                    return false
                } catch {
                    return true
                }
            },
            remove: { (try? store.remove(id: $0)) != nil },
            isDuplicate: { $0.name == $1.name && $0.instructions == $1.instructions })
    }
}
