import Foundation

/// Persists the per-extension icon overrides. Keyed by manifest name, the same key
/// `ExtensionStorage` uses for preferences, so uninstalling and reinstalling keeps the choice.
@MainActor
@Observable
final class ExtensionAppearanceStore {
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let key = "extensionAppearances"

    private(set) var overrides: [String: ExtensionAppearance]

    init() {
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: ExtensionAppearance].self, from: data)
        {
            overrides = decoded
        } else {
            overrides = [:]
        }
    }

    func appearance(for extensionName: String) -> ExtensionAppearance? {
        overrides[extensionName]
    }

    /// `nil` restores the extension's own icon.
    func set(_ appearance: ExtensionAppearance?, for extensionName: String) {
        if let appearance {
            overrides[extensionName] = appearance
        } else {
            overrides.removeValue(forKey: extensionName)
        }
        persist()
    }

    /// Replace the whole map at once (used when importing a settings backup).
    func replace(_ newOverrides: [String: ExtensionAppearance]) {
        overrides = newOverrides
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: key)
    }
}
