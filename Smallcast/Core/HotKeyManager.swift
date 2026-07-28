import Foundation

/// Owns all global shortcut bindings: persistence, Carbon registration (via `HotKeyCenter`), conflict lookup, and dispatch.
@MainActor
final class HotKeyManager: ObservableObject {
    var onTogglePalette: (() -> Void)?
    var onToggleClipboard: (() -> Void)?
    var onToggleEmoji: (() -> Void)?

    /// The recorder currently capturing keystrokes, or `nil`; keeping this as plain app state makes recorders glitch-free, and any active recorder pauses Carbon so the typed combo can't fire a hotkey.
    @Published var recordingAction: HotKeyAction? {
        didSet { center.isPaused = recordingAction != nil }
    }

    private let center = HotKeyCenter()
    private let boundKey = "boundAppBundleIDs"
    private let boundPaneKey = "boundPaneBundleIDs"

    func start() {
        register(.togglePalette)
        register(.toggleClipboard)
        register(.toggleEmoji)
        for bundleID in boundBundleIDs { register(.app(bundleID: bundleID)) }
        for bundleID in boundPaneBundleIDs { register(.settingsPane(bundleID: bundleID)) }
    }

    /// Bundle IDs that currently have a per-app hotkey — lets `start()` know which records to load and lets launcher rows show keycaps.
    var boundBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundKey) ?? []
    }

    /// Settings-pane bundle IDs with a hotkey — same role as `boundBundleIDs`, own namespace.
    var boundPaneBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundPaneKey) ?? []
    }

    func shortcut(for action: HotKeyAction) -> KeyShortcut? {
        // The stored value is a JSON *string* (a legacy package format); anything else reads as unbound.
        guard
            let json = UserDefaults.standard.string(forKey: action.defaultsKey),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(KeyShortcut.self, from: data)
    }

    /// Persists (or clears, when `nil`) the binding, swaps the live Carbon registration, and publishes so the launcher and recorders re-render.
    func setShortcut(_ shortcut: KeyShortcut?, for action: HotKeyAction) {
        objectWillChange.send()
        if let shortcut,
            let data = try? JSONEncoder().encode(shortcut),
            let json = String(data: data, encoding: .utf8)
        {
            UserDefaults.standard.set(json, forKey: action.defaultsKey)
            register(action)
        } else {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
            center.unregister(id: action.defaultsKey)
        }
        switch action {
        case .app(let bundleID):
            var set = Set(boundBundleIDs)
            if shortcut == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundKey)
        case .settingsPane(let bundleID):
            var set = Set(boundPaneBundleIDs)
            if shortcut == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundPaneKey)
        case .togglePalette, .toggleClipboard, .toggleEmoji:
            break
        }
    }

    /// The display name of whatever else `shortcut` is bound to (or `nil` if free), driving the recorder's "Used by …" message.
    func conflictOwner(of shortcut: KeyShortcut, excluding action: HotKeyAction) -> String? {
        var candidates: [HotKeyAction] = [.togglePalette, .toggleClipboard, .toggleEmoji]
        candidates += boundBundleIDs.map { .app(bundleID: $0) }
        candidates += boundPaneBundleIDs.map { .settingsPane(bundleID: $0) }
        for candidate in candidates
        where candidate != action && self.shortcut(for: candidate) == shortcut {
            return displayName(of: candidate)
        }
        return nil
    }

    private func displayName(of action: HotKeyAction) -> String {
        switch action {
        case .togglePalette:
            return "App Launcher"
        case .toggleClipboard:
            return "Clipboard History"
        case .toggleEmoji:
            return "Emoji & Symbols"
        case .app(let bundleID):
            let apps = AppCore.shared.appIndex.apps
            return apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
                ?? bundleID
        case .settingsPane(let bundleID):
            let apps = AppCore.shared.appIndex.apps
            return apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?.name
                ?? bundleID
        }
    }

    private func register(_ action: HotKeyAction) {
        guard let shortcut = shortcut(for: action) else { return }
        center.register(id: action.defaultsKey, shortcut: shortcut) { [weak self] in
            self?.perform(action)
        }
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .togglePalette: onTogglePalette?()
        case .toggleClipboard: onToggleClipboard?()
        case .toggleEmoji: onToggleEmoji?()
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        case .settingsPane(let bundleID): AppLauncher.openSettingsPane(bundleID: bundleID)
        }
    }
}
