import Foundation

/// Owns every binding: persistence, registration with both engines, conflicts and dispatch.
@MainActor
@Observable
final class HotKeyManager {
    var onTogglePalette: (() -> Void)?
    var onToggleClipboard: (() -> Void)?
    var onToggleEmoji: (() -> Void)?
    var onSearchFiles: (() -> Void)?
    var onRunCustomCommand: ((UUID) -> Void)?
    var onRunSystemAction: ((SystemAction.ID) -> Void)?
    var onRunWindowCommand: ((WindowCommand.ID) -> Void)?
    var onOpenQuicklink: ((UUID) -> Void)?
    var onRunExtensionCommand: ((String) -> Void)?
    /// Names what only the stores know; the fixed catalogs resolve here. Set in `AppCore.start()`.
    var displayName: ((HotKeyAction) -> String?)?

    /// The recorder currently capturing, which also pauses both engines.
    var recordingAction: HotKeyAction? {
        didSet {
            guard recordingAction != oldValue else { return }
            let recording = recordingAction != nil
            center.isPaused = recording
            doubleTapMonitor.isPaused = recording
            if let recordingAction {
                capture.start(action: recordingAction, hotKeys: self)
            } else {
                capture.stop()
            }
        }
    }

    let doubleTapMonitor = DoubleTapMonitor()
    /// Live state of the open recorder, read by its callout.
    let capture = ShortcutCaptureSession()

    private let center = HotKeyCenter()
    private var doubleTaps: [DoubleTapModifier: HotKeyAction] = [:]
    /// Every binding, loaded once in `start()` and written through on change.
    private var bindings: [HotKeyAction: HotKeyBinding] = [:]
    @ObservationIgnored private var candidateActionsCache: [HotKeyAction]?
    // Reused: the startup load decodes once per candidate action.
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let boundKey = "boundAppBundleIDs"
    private let boundPaneKey = "boundPaneBundleIDs"
    private let boundCustomCommandKey = "boundCustomCommandIDs"
    private let boundQuicklinkKey = "boundQuicklinkIDs"
    private let boundExtensionCommandKey = "boundExtensionCommandEntryIDs"

    func start(customCommandIDs: Set<UUID>, quicklinkIDs: Set<UUID>) {
        LegacyHotKeyRecords.adopt(candidateActions, decoder: decoder, encoder: encoder)
        prune(key: boundCustomCommandKey, live: customCommandIDs) { .customCommand(id: $0) }
        prune(key: boundQuicklinkKey, live: quicklinkIDs) { .quicklink(id: $0) }
        // After the prunes, so a dropped record can't survive in memory this session.
        for action in candidateActions { bindings[action] = storedBinding(for: action) }

        // `register` no-ops on an unbound item, so the fixed catalogs need no index of their own.
        for action in candidateActions { register(action) }

        doubleTapMonitor.onDoubleTap = { [weak self] modifier in
            guard let self, let action = doubleTaps[modifier] else { return }
            perform(action)
        }
        doubleTapMonitor.start()
        syncDoubleTaps()
    }

    /// Entry ids holding an extension-command hotkey. Not pruned in `start()` like the UUID-keyed
    /// indexes are: the installed set is scanned asynchronously and only when extensions are on, so
    /// "not installed yet" is indistinguishable from "gone" at launch. Uninstalling clears its own.
    var boundExtensionCommandEntryIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundExtensionCommandKey) ?? []
    }

    /// Bundle IDs holding a per-app hotkey, so `start()` knows which records to load.
    var boundBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundKey) ?? []
    }

    /// Settings-pane bundle IDs with a hotkey — same role as `boundBundleIDs`, own namespace.
    var boundPaneBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundPaneKey) ?? []
    }

    /// Custom-command UUIDs with a binding, indexed separately so startup can re-register them.
    var boundCustomCommandIDs: [UUID] { boundIDs(key: boundCustomCommandKey) }

    /// Quicklink UUIDs with a binding — the same index, its own namespace.
    var boundQuicklinkIDs: [UUID] { boundIDs(key: boundQuicklinkKey) }

    func binding(for action: HotKeyAction) -> HotKeyBinding? { bindings[action] }

    private func storedBinding(for action: HotKeyAction) -> HotKeyBinding? {
        // The stored value is a JSON string; anything else reads as unbound.
        guard
            let json = UserDefaults.standard.string(forKey: action.defaultsKey),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? decoder.decode(HotKeyBinding.self, from: data)
    }

    /// Persists or clears the binding and swaps live registration.
    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        let previous = bindings[action]
        if let binding,
            let data = try? encoder.encode(binding),
            let json = String(data: data, encoding: .utf8)
        {
            bindings[action] = binding
            UserDefaults.standard.set(json, forKey: action.defaultsKey)
        } else {
            bindings[action] = nil
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        }
        // Unregister unconditionally: the previous binding may have been a combo.
        center.unregister(id: action.defaultsKey)
        register(action)

        switch action {
        case .app(let bundleID):
            var set = Set(boundBundleIDs)
            if binding == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundKey)
        case .settingsPane(let bundleID):
            var set = Set(boundPaneBundleIDs)
            if binding == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundPaneKey)
        case .customCommand(let id):
            index(id, bound: binding != nil, key: boundCustomCommandKey)
        case .quicklink(let id):
            index(id, bound: binding != nil, key: boundQuicklinkKey)
        case .extensionCommand(let entryID):
            var set = Set(boundExtensionCommandEntryIDs)
            if binding == nil { set.remove(entryID) } else { set.insert(entryID) }
            UserDefaults.standard.set(Array(set), forKey: boundExtensionCommandKey)
        case .togglePalette, .toggleClipboard, .toggleEmoji, .searchFiles, .systemAction,
            .windowCommand:
            break
        }
        candidateActionsCache = nil
        // A rebuild walks every candidate; only a double-tap entering or leaving changes the map.
        if previous?.doubleTapModifier != nil || binding?.doubleTapModifier != nil {
            syncDoubleTaps()
        }
    }

    /// Include Shift redefines the chord, and a stored combo has the old one baked in.
    func retargetHyperBindings(includesShift: Bool) {
        for action in candidateActions {
            guard let shortcut = bindings[action]?.shortcut else { continue }
            let retargeted = shortcut.retargetingHyper(includesShift: includesShift)
            guard retargeted != shortcut else { continue }
            let binding = HotKeyBinding.combo(retargeted)
            // Skip a collision rather than clobber it: the second registration would fail silently.
            guard conflictOwner(of: binding, excluding: action) == nil else { continue }
            setBinding(binding, for: action)
        }
    }

    /// What else holds `binding`, or nil. Whole-binding comparison covers both kinds alike.
    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        for candidate in candidateActions
        where candidate != action && self.binding(for: candidate) == binding {
            return displayName(of: candidate)
        }
        return nil
    }

    /// Every action that could hold a binding: the search space for conflicts and the map.
    private var candidateActions: [HotKeyAction] {
        if let candidateActionsCache { return candidateActionsCache }
        var actions: [HotKeyAction] = [
            .togglePalette, .toggleClipboard, .toggleEmoji, .searchFiles
        ]
        actions += boundBundleIDs.map { .app(bundleID: $0) }
        actions += boundPaneBundleIDs.map { .settingsPane(bundleID: $0) }
        actions += boundCustomCommandIDs.map { .customCommand(id: $0) }
        actions += boundQuicklinkIDs.map { .quicklink(id: $0) }
        actions += boundExtensionCommandEntryIDs.map { .extensionCommand(entryID: $0) }
        actions += SystemAction.ID.allCases.map { .systemAction(id: $0) }
        actions += WindowCommand.ID.allCases.map { .windowCommand(id: $0) }
        candidateActionsCache = actions
        return actions
    }

    private func displayName(of action: HotKeyAction) -> String {
        switch action {
        case .togglePalette:
            return "App Launcher"
        case .toggleClipboard:
            return "Clipboard History"
        case .toggleEmoji:
            return "Emoji & Symbols"
        case .searchFiles:
            return CommandID.searchFiles.name
        case .app(let bundleID), .settingsPane(let bundleID):
            return displayName?(action) ?? bundleID
        case .customCommand:
            return displayName?(action) ?? "Custom Command"
        case .systemAction(let id):
            return SystemActionCatalog.action(id: id).name
        case .windowCommand(let id):
            return WindowCommandCatalog.command(id: id)?.name ?? "Window Command"
        case .quicklink:
            return displayName?(action) ?? "Quicklink"
        case .extensionCommand:
            return displayName?(action) ?? "Extension Command"
        }
    }

    /// Hands a combo to Carbon; a double-tap has no per-action registration to make.
    private func register(_ action: HotKeyAction) {
        guard let shortcut = binding(for: action)?.shortcut else { return }
        center.register(id: action.defaultsKey, shortcut: shortcut) { [weak self] in
            self?.perform(action)
        }
    }

    /// Rebuilt wholesale, so the map can't drift from what is on disk.
    private func syncDoubleTaps() {
        doubleTaps = [:]
        for action in candidateActions {
            guard let modifier = binding(for: action)?.doubleTapModifier else { continue }
            doubleTaps[modifier] = action
        }
        doubleTapMonitor.update(bound: Set(doubleTaps.keys))
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .togglePalette: onTogglePalette?()
        case .toggleClipboard: onToggleClipboard?()
        case .toggleEmoji: onToggleEmoji?()
        case .searchFiles: onSearchFiles?()
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        case .settingsPane(let bundleID): AppLauncher.openSettingsPane(bundleID: bundleID)
        case .customCommand(let id): onRunCustomCommand?(id)
        case .systemAction(let id): onRunSystemAction?(id)
        case .windowCommand(let id): onRunWindowCommand?(id)
        case .quicklink(let id): onOpenQuicklink?(id)
        case .extensionCommand(let entryID): onRunExtensionCommand?(entryID)
        }
    }

    // MARK: - UUID-keyed indexes

    private func boundIDs(key: String) -> [UUID] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
    }

    private func index(_ id: UUID, bound: Bool, key: String) {
        var set = Set(boundIDs(key: key))
        if bound { set.insert(id) } else { set.remove(id) }
        persist(set, key: key)
    }

    /// Drops bindings whose item is gone, deleted while Tinycast wasn't running.
    private func prune(key: String, live: Set<UUID>, action: (UUID) -> HotKeyAction) {
        let stored = Set(boundIDs(key: key))
        for id in stored.subtracting(live) {
            UserDefaults.standard.removeObject(forKey: action(id).defaultsKey)
        }
        persist(stored.intersection(live), key: key)
    }

    private func persist(_ ids: Set<UUID>, key: String) {
        UserDefaults.standard.set(ids.map { $0.uuidString.lowercased() }.sorted(), forKey: key)
    }
}
