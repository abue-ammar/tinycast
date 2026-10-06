import Foundation

/// Owns every binding: persistence, registration with both engines, conflicts and dispatch.
@MainActor
@Observable
final class HotKeyManager {
    var onTogglePalette: (() -> Void)?
    var onDictationPressed: (() -> Void)?
    var onDictationReleased: (() -> Void)?
    var onDictationCancelled: (() -> Void)?
    var dictationEnabled = false {
        didSet {
            guard dictationEnabled != oldValue else { return }
            if !dictationEnabled { onDictationCancelled?() }
            syncModifierTaps()
        }
    }
    var dictationHoldToTalk = false {
        didSet {
            guard dictationHoldToTalk != oldValue else { return }
            onDictationCancelled?()
            syncModifierTaps()
        }
    }
    /// The launcher's own command funnel, so a shortcut and a palette row run the same thing.
    var onRunCommand: ((CommandID) -> Void)?
    var onRunCustomCommand: ((UUID) -> Void)?
    var onRunSystemAction: ((SystemAction.ID) -> Void)?
    var onRunWindowCommand: ((WindowCommand.ID) -> Void)?
    var onRunWindowLayout: ((UUID) -> Void)?
    var onEnterRoom: ((UUID) -> Void)?
    var onRunCustomWindowSize: ((UUID) -> Void)?
    var onOpenQuicklink: ((UUID) -> Void)?
    var onRunQuickAction: ((UUID) -> Void)?
    var onRunAppleShortcut: ((UUID) -> Void)?
    var onExpandSnippet: ((StoredSnippet.ID) -> Void)?
    var onRunExtensionCommand: ((String) -> Void)?
    /// Names what only the stores know; the fixed catalogs resolve here. Set in `AppCore.start()`.
    var displayName: ((HotKeyAction) -> String?)?
    /// Whether the action's launcher category is switched on. Set in `AppCore.start()`.
    var allowsAction: ((HotKeyAction) -> Bool)?

    /// The recorder currently capturing, which also pauses both engines.
    var recordingAction: HotKeyAction? {
        didSet {
            guard recordingAction != oldValue else { return }
            let recording = recordingAction != nil
            if recording, dictationEnabled, dictationHoldToTalk { onDictationCancelled?() }
            center.isPaused = recording
            modifierTapMonitor.isPaused = recording
            if let recordingAction {
                capture.start(action: recordingAction, hotKeys: self)
            } else {
                capture.stop()
            }
        }
    }

    let modifierTapMonitor = ModifierTapMonitor()
    /// Live state of the open recorder, read by its callout.
    let capture = ShortcutCaptureSession()

    private let center = HotKeyCenter()
    var needsAccessibility: Bool { center.needsAccessibility || modifierTapMonitor.needsAccessibility }
    weak var healthTicker: HealthTicker? {
        didSet { center.healthTicker = healthTicker }
    }
    private var modifierTaps: [HotKeyBinding: HotKeyAction] = [:]
    /// Every binding, loaded once in `start()` and written through on change.
    private var bindings: [HotKeyAction: HotKeyBinding] = [:]
    /// Part of `AppIndex`'s cache key: a bound entry leaves the launcher's Suggestions.
    private(set) var revision = 0
    @ObservationIgnored private var candidateActionsCache: [HotKeyAction]?
    // Reused: the startup load decodes once per candidate action.
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let boundKey = "boundAppBundleIDs"
    private let boundPaneKey = "boundPaneBundleIDs"
    private let boundCustomCommandKey = "boundCustomCommandIDs"
    private let boundQuicklinkKey = "boundQuicklinkIDs"
    private let boundQuickActionKey = "boundQuickActionIDs"
    private let boundWindowLayoutKey = "boundWindowLayoutIDs"
    private let boundWindowRoomKey = "boundWindowRoomIDs"
    private let boundCustomWindowSizeKey = "boundCustomWindowSizeIDs"
    private let boundAppleShortcutKey = "boundAppleShortcutIDs"
    private let boundSnippetKey = "boundSnippetIDs"
    private let boundExtensionCommandKey = "boundExtensionCommandEntryIDs"

    func start(
        customCommandIDs: Set<UUID>, quicklinkIDs: Set<UUID>, windowLayoutIDs: Set<UUID>,
        windowRoomIDs: Set<UUID>, customWindowSizeIDs: Set<UUID>, quickActionIDs: Set<UUID>
    ) {
        prune(key: boundCustomCommandKey, live: customCommandIDs) { .customCommand(id: $0) }
        prune(key: boundQuicklinkKey, live: quicklinkIDs) { .quicklink(id: $0) }
        prune(key: boundWindowLayoutKey, live: windowLayoutIDs) { .windowLayout(id: $0) }
        prune(key: boundWindowRoomKey, live: windowRoomIDs) { .windowRoom(id: $0) }
        prune(key: boundCustomWindowSizeKey, live: customWindowSizeIDs) {
            .customWindowSize(id: $0)
        }
        prune(key: boundQuickActionKey, live: quickActionIDs) { .quickAction(id: $0) }
        // After the prunes, so a dropped record can't survive in memory this session.
        for action in candidateActions { bindings[action] = storedBinding(for: action) }
        revision &+= 1

        // `register` no-ops on an unbound item, so the fixed catalogs need no index of their own.
        for action in candidateActions { register(action) }

        modifierTapMonitor.onTrigger = { [weak self] binding in
            guard let self, let action = modifierTaps[binding] else { return }
            perform(action)
        }
        modifierTapMonitor.onHoldPressed = { [weak self] in self?.perform(.dictation) }
        modifierTapMonitor.onHoldReleased = { [weak self] in self?.onDictationReleased?() }
        modifierTapMonitor.onHoldCancelled = { [weak self] in self?.onDictationCancelled?() }
        modifierTapMonitor.start()
        syncModifierTaps()
    }

    /// Never pruned at launch: not-installed-yet and gone are indistinguishable there.
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

    /// Window-layout UUIDs with a binding; authored records, so they need an index of their own.
    var boundWindowLayoutIDs: [UUID] { boundIDs(key: boundWindowLayoutKey) }

    var boundWindowRoomIDs: [UUID] { boundIDs(key: boundWindowRoomKey) }

    var boundCustomWindowSizeIDs: [UUID] { boundIDs(key: boundCustomWindowSizeKey) }

    var boundQuickActionIDs: [UUID] { boundIDs(key: boundQuickActionKey) }

    /// Pruned by `AppleShortcutCoordinator` after a successful read, never here at launch.
    var boundAppleShortcutIDs: [UUID] { boundIDs(key: boundAppleShortcutKey) }

    /// Swept by `removeSnippetBindings` on each load, never at launch: the store may be off.
    var boundSnippetIDs: [StoredSnippet.ID] {
        UserDefaults.standard.stringArray(forKey: boundSnippetKey) ?? []
    }

    /// A deleted app takes its Settings row with it, so nothing else could ever clear its binding.
    func removeAppBindings(where isUninstalled: (String) -> Bool) {
        for bundleID in boundBundleIDs where isUninstalled(bundleID) {
            let action = HotKeyAction.app(bundleID: bundleID)
            if recordingAction == action { recordingAction = nil }
            setBinding(nil, for: action)
        }
    }

    /// Covers a file deleted or renamed outside Tinycast, which no Settings row is left to clear.
    func removeSnippetBindings(keeping liveIDs: Set<StoredSnippet.ID>) {
        for id in boundSnippetIDs where !liveIDs.contains(id) {
            let action = HotKeyAction.snippet(id: id)
            if recordingAction == action { recordingAction = nil }
            setBinding(nil, for: action)
        }
    }

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
        if action == .dictation, binding != self.binding(for: action) { onDictationCancelled?() }
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
        revision &+= 1
        // Unregister unconditionally: the previous binding may have been a combo.
        center.unregister(id: action.defaultsKey)
        register(action)

        switch action {
        case .app(let bundleID):
            index(bundleID, bound: binding != nil, key: boundKey)
        case .settingsPane(let bundleID):
            index(bundleID, bound: binding != nil, key: boundPaneKey)
        case .customCommand(let id):
            index(id, bound: binding != nil, key: boundCustomCommandKey)
        case .quicklink(let id):
            index(id, bound: binding != nil, key: boundQuicklinkKey)
        case .quickAction(let id):
            index(id, bound: binding != nil, key: boundQuickActionKey)
        case .windowLayout(let id):
            index(id, bound: binding != nil, key: boundWindowLayoutKey)
        case .windowRoom(let id):
            index(id, bound: binding != nil, key: boundWindowRoomKey)
        case .customWindowSize(let id):
            index(id, bound: binding != nil, key: boundCustomWindowSizeKey)
        case .appleShortcut(let id):
            index(id, bound: binding != nil, key: boundAppleShortcutKey)
        case .snippet(let id):
            index(id, bound: binding != nil, key: boundSnippetKey)
        case .extensionCommand(let entryID):
            index(entryID, bound: binding != nil, key: boundExtensionCommandKey)
        case .togglePalette, .dictation, .command, .systemAction, .windowCommand:
            break
        }
        candidateActionsCache = nil
        // A rebuild walks every candidate; only a modifier-only binding changes this map.
        if previous?.usesModifierTapMonitor == true || binding?.usesModifierTapMonitor == true {
            syncModifierTaps()
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

    /// A hold reserves its physical modifier across both tap gestures.
    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        for candidate in candidateActions where candidate != action {
            guard let other = self.binding(for: candidate) else { continue }
            let holdsModifier =
                dictationHoldToTalk
                && (action == .dictation && binding.holdKey != nil
                    || candidate == .dictation && other.holdKey != nil)
            let conflicts: Bool
            if let shortcut = binding.shortcut, let otherShortcut = other.shortcut {
                conflicts = shortcut.overlaps(with: otherShortcut) { keyCode, modifiers in
                    KeyShortcut.character(for: keyCode, carbonModifiers: modifiers)
                }
            } else {
                conflicts = binding.conflicts(with: other, holdsModifier: holdsModifier)
            }
            if conflicts { return displayName(of: candidate) }
        }
        return nil
    }

    /// Every action that could hold a binding: the search space for conflicts and the map.
    private var candidateActions: [HotKeyAction] {
        if let candidateActionsCache { return candidateActionsCache }
        var actions = HotKeyAction.builtInActions
        actions += boundBundleIDs.map { .app(bundleID: $0) }
        actions += boundPaneBundleIDs.map { .settingsPane(bundleID: $0) }
        actions += boundCustomCommandIDs.map { .customCommand(id: $0) }
        actions += boundQuicklinkIDs.map { .quicklink(id: $0) }
        actions += boundQuickActionIDs.map { .quickAction(id: $0) }
        actions += boundWindowLayoutIDs.map { .windowLayout(id: $0) }
        actions += boundWindowRoomIDs.map { .windowRoom(id: $0) }
        actions += boundCustomWindowSizeIDs.map { .customWindowSize(id: $0) }
        actions += boundAppleShortcutIDs.map { .appleShortcut(id: $0) }
        actions += boundSnippetIDs.map { .snippet(id: $0) }
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
        case .dictation:
            return "Dictation"
        case .command(let id):
            return id.name
        case .app(let bundleID), .settingsPane(let bundleID):
            return displayName?(action) ?? bundleID
        case .customCommand:
            return displayName?(action) ?? "Custom Command"
        case .systemAction(let id):
            return SystemActionCatalog.action(id: id).name
        case .windowCommand(let id):
            return WindowCommandCatalog.command(id: id)?.name ?? "Window Command"
        case .windowLayout:
            return displayName?(action) ?? "Window Layout"
        case .windowRoom:
            return displayName?(action) ?? "Room"
        case .customWindowSize:
            return displayName?(action) ?? "Custom Size"
        case .quicklink:
            return displayName?(action) ?? "Quicklink"
        case .quickAction:
            return displayName?(action) ?? "Quick Action"
        case .appleShortcut:
            return displayName?(action) ?? "Apple Shortcut"
        case .snippet:
            return displayName?(action) ?? "Snippet"
        case .extensionCommand:
            return displayName?(action) ?? "Extension Command"
        }
    }

    /// Hands a combo to Carbon; a modifier-only binding has no per-action registration.
    private func register(_ action: HotKeyAction) {
        guard let shortcut = binding(for: action)?.shortcut else { return }
        center.register(
            id: action.defaultsKey, shortcut: shortcut,
            onKeyDown: { [weak self] in
                if shortcut.requiresEventTap {
                    self?.modifierTapMonitor.process(
                        isFlagsChanged: false, flagsRaw: 0, keyCode: shortcut.carbonKeyCode)
                }
                self?.perform(action)
            },
            onKeyUp: action == .dictation ? { [weak self] in self?.onDictationReleased?() } : nil)
    }

    /// Rebuilt wholesale, so the map can't drift from what is on disk.
    private func syncModifierTaps() {
        modifierTaps = [:]
        let dictationBinding = binding(for: .dictation)
        let holdKey = dictationHoldToTalk ? dictationBinding?.holdKey : nil
        for action in candidateActions {
            guard let binding = binding(for: action), binding.usesModifierTapMonitor else { continue }
            if action == .dictation, !dictationEnabled { continue }
            if action == .dictation, dictationHoldToTalk {
                guard holdKey != nil, conflictOwner(of: binding, excluding: action) == nil else {
                    continue
                }
            }
            modifierTaps[binding] = action
        }
        modifierTapMonitor.update(
            bound: Set(modifierTaps.keys),
            holdKey: dictationBinding.flatMap { modifierTaps[$0] == .dictation ? holdKey : nil })
    }

    private func perform(_ action: HotKeyAction) {
        // The category switch, the way each feature switch already guards its own funnel.
        guard allowsAction?(action) ?? true else { return }
        switch action {
        case .togglePalette: onTogglePalette?()
        case .dictation: onDictationPressed?()
        case .command(let id): onRunCommand?(id)
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        case .settingsPane(let bundleID): AppLauncher.openSettingsPane(bundleID: bundleID)
        case .customCommand(let id): onRunCustomCommand?(id)
        case .systemAction(let id): onRunSystemAction?(id)
        case .windowCommand(let id): onRunWindowCommand?(id)
        case .windowLayout(let id): onRunWindowLayout?(id)
        case .windowRoom(let id): onEnterRoom?(id)
        case .customWindowSize(let id): onRunCustomWindowSize?(id)
        case .quicklink(let id): onOpenQuicklink?(id)
        case .quickAction(let id): onRunQuickAction?(id)
        case .appleShortcut(let id): onRunAppleShortcut?(id)
        case .snippet(let id): onExpandSnippet?(id)
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

    private func index(_ id: String, bound: Bool, key: String) {
        var set = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if bound { set.insert(id) } else { set.remove(id) }
        UserDefaults.standard.set(Array(set), forKey: key)
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
