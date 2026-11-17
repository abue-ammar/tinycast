import Foundation

extension RecordSyncSource where Record == ChatPreset {
    /// Presets live only while AI is on, so they wait for it rather than read as deleted.
    static func chatPresets(_ store: ChatPresetStore, isActive: @escaping () -> Bool) -> Self {
        Self(
            .chatPresets,
            records: { isActive() && store.isAvailable ? store.presets : nil },
            save: { preset in
                do {
                    if store.preset(id: preset.id) == nil {
                        try store.add(preset)
                    } else {
                        try store.update(preset)
                    }
                    return true
                } catch ChatPresetError.storageUnavailable {
                    return false
                } catch {
                    return true
                }
            },
            remove: { (try? store.remove(id: $0)) != nil },
            isDuplicate: { $0.name == $1.name && $0.instructions == $1.instructions })
    }
}
