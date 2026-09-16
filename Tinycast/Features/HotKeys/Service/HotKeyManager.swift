import AppKit

/// Owns every binding: persistence, registration with both engines, conflicts and dispatch.
@MainActor
@Observable
final class HotKeyManager {
    var onTogglePalette: (() -> Void)?
    /// The launcher's own command funnel, so a shortcut and a palette row run the same thing.
    var onRunCommand: ((CommandID) -> Void)?
    var onRunCustomCommand: ((UUID) -> Void)?
    var onRunSystemAction: ((SystemAction.ID) -> Void)?
    var onRunWindowCommand: ((WindowCommand.ID) -> Void)?
    var onRunWindowLayout: ((UUID) -> Void)?
    var onOpenQuicklink: ((UUID) -> Void)?
    var onRunQuickAction: ((UUID) -> Void)?
    var onRunAppleShortcut: ((UUID) -> Void)?
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
    /// Every binding, loaded once in `start()` and written through on change.
    private var bindings: [HotKeyAction: HotKeyBinding] = [:]
    /// Cycle state per shared binding — which app fires next. Empty for a single-holder binding.
    private var cycles: [HotKeyBinding: HotKeyCycle] = [:]
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
    private let boundAppleShortcutKey = "boundAppleShortcutIDs"
    private let boundExtensionCommandKey = "boundExtensionCommandEntryIDs"

    func start(
        customCommandIDs: Set<UUID>, quicklinkIDs: Set<UUID>, windowLayoutIDs: Set<UUID>,
        quickActionIDs: Set<UUID>
    ) {
        prune(key: boundCustomCommandKey, live: customCommandIDs) { .customCommand(id: $0) }
        prune(key: boundQuicklinkKey, live: quicklinkIDs) { .quicklink(id: $0) }
        prune(key: boundWindowLayoutKey, live: windowLayoutIDs) { .windowLayout(id: $0) }
        prune(key: boundQuickActionKey, live: quickActionIDs) { .quickAction(id: $0) }
        // After the prunes, so a dropped record can't survive in memory this session.
        for action in candidateActions { bindings[action] = storedBinding(for: action) }

        // One Carbon registration per distinct combo, however many actions share it.
        registerAllCombos()

        doubleTapMonitor.onDoubleTap = { [weak self] modifier in
            self?.performBinding(.doubleTap(modifier))
        }
        doubleTapMonitor.start()
        syncDoubleTaps()
    }

    /// Never pruned at launch: not-installed-yet and gone are indistinguishable there.
    var boundExtensionCommandEntryIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundExtensionCommandKey) ?? []
    }

    /// Bundle IDs holding a per-app hotkey, in the order they were assigned — a shared chord
    /// cycles through this order, so it is never re-sorted into a set.
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

    var boundQuickActionIDs: [UUID] { boundIDs(key: boundQuickActionKey) }

    /// Pruned by `AppleShortcutCoordinator` after a successful read, never here at launch.
    var boundAppleShortcutIDs: [UUID] { boundIDs(key: boundAppleShortcutKey) }

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
        // Only the two combos that actually changed are touched — a join or a leave never
        // disturbs a chord some other action still holds.
        updateComboRegistration(previous: previous, action: action)

        switch action {
        case .app(let bundleID):
            // An ordered array, not a set: cycle order is assignment order.
            var order = boundBundleIDs
            if binding == nil {
                order.removeAll { $0 == bundleID }
            } else if !order.contains(bundleID) {
                order.append(bundleID)
            }
            UserDefaults.standard.set(order, forKey: boundKey)
        case .settingsPane(let bundleID):
            var set = Set(boundPaneBundleIDs)
            if binding == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundPaneKey)
        case .customCommand(let id):
            index(id, bound: binding != nil, key: boundCustomCommandKey)
        case .quicklink(let id):
            index(id, bound: binding != nil, key: boundQuicklinkKey)
        case .quickAction(let id):
            index(id, bound: binding != nil, key: boundQuickActionKey)
        case .windowLayout(let id):
            index(id, bound: binding != nil, key: boundWindowLayoutKey)
        case .appleShortcut(let id):
            index(id, bound: binding != nil, key: boundAppleShortcutKey)
        case .extensionCommand(let entryID):
            var set = Set(boundExtensionCommandEntryIDs)
            if binding == nil { set.remove(entryID) } else { set.insert(entryID) }
            UserDefaults.standard.set(Array(set), forKey: boundExtensionCommandKey)
        case .togglePalette, .command, .systemAction, .windowCommand:
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
    /// Two `.app` actions never conflict: a chord already held by one app just gains another
    /// member to cycle through, rather than being refused.
    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        for candidate in candidateActions
        where candidate != action && self.binding(for: candidate) == binding {
            if case .app = action, case .app = candidate { continue }
            return displayName(of: candidate)
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
        actions += boundAppleShortcutIDs.map { .appleShortcut(id: $0) }
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
        case .quicklink:
            return displayName?(action) ?? "Quicklink"
        case .quickAction:
            return displayName?(action) ?? "Quick Action"
        case .appleShortcut:
            return displayName?(action) ?? "Apple Shortcut"
        case .extensionCommand:
            return displayName?(action) ?? "Extension Command"
        }
    }

    /// One Carbon id per distinct combo — however many actions end up sharing it.
    private func registrationID(for binding: HotKeyBinding) -> String {
        guard let shortcut = binding.shortcut else { return "" }
        return "hotkey.combo.\(shortcut.carbonKeyCode).\(shortcut.carbonModifiers)"
    }

    /// Registers every distinct combo once, no matter how many actions hold it.
    private func registerAllCombos() {
        var seen: Set<HotKeyBinding> = []
        for action in candidateActions {
            guard let binding = bindings[action], let shortcut = binding.shortcut else { continue }
            guard seen.insert(binding).inserted else { continue }
            center.register(id: registrationID(for: binding), shortcut: shortcut) { [weak self] in
                self?.performBinding(binding)
            }
        }
    }

    /// Registers or unregisters only the two combos `action` actually left or joined; a chord
    /// still held by someone else is never touched, and one already held by someone else is
    /// never re-registered.
    private func updateComboRegistration(previous: HotKeyBinding?, action: HotKeyAction) {
        let new = bindings[action]
        func stillHeld(_ candidate: HotKeyBinding) -> Bool {
            candidateActions.contains { $0 != action && bindings[$0] == candidate }
        }
        if let previous, previous.shortcut != nil, previous != new, !stillHeld(previous) {
            center.unregister(id: registrationID(for: previous))
        }
        if let new, let shortcut = new.shortcut, new != previous, !stillHeld(new) {
            center.register(id: registrationID(for: new), shortcut: shortcut) { [weak self] in
                self?.performBinding(new)
            }
        }
    }

    /// Rebuilt wholesale, so the set can't drift from what is on disk.
    private func syncDoubleTaps() {
        var modifiers: Set<DoubleTapModifier> = []
        for action in candidateActions {
            if let modifier = binding(for: action)?.doubleTapModifier { modifiers.insert(modifier) }
        }
        doubleTapMonitor.update(bound: modifiers)
    }

    /// Resolves who actually fires for `binding` — one action runs directly, several `.app`
    /// holders advance the shared cycle instead.
    private func performBinding(_ binding: HotKeyBinding) {
        let holders = candidateActions.filter { bindings[$0] == binding }
        guard !holders.isEmpty else { return }
        let bundleIDs = holders.compactMap { holder -> String? in
            if case .app(let bundleID) = holder { return bundleID }
            return nil
        }
        guard bundleIDs.count > 1 else {
            perform(holders[0])
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        var cycle = cycles[binding] ?? HotKeyCycle()
        let target = cycle.next(
            members: bundleIDs, frontmost: frontmost, now: ProcessInfo.processInfo.systemUptime)
        cycles[binding] = cycle
        perform(.app(bundleID: target))
    }

    private func perform(_ action: HotKeyAction) {
        // The category switch, the way each feature switch already guards its own funnel.
        guard allowsAction?(action) ?? true else { return }
        switch action {
        case .togglePalette: onTogglePalette?()
        case .command(let id): onRunCommand?(id)
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        case .settingsPane(let bundleID): AppLauncher.openSettingsPane(bundleID: bundleID)
        case .customCommand(let id): onRunCustomCommand?(id)
        case .systemAction(let id): onRunSystemAction?(id)
        case .windowCommand(let id): onRunWindowCommand?(id)
        case .windowLayout(let id): onRunWindowLayout?(id)
        case .quicklink(let id): onOpenQuicklink?(id)
        case .quickAction(let id): onRunQuickAction?(id)
        case .appleShortcut(let id): onRunAppleShortcut?(id)
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
