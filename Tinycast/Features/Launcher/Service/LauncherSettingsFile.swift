import Foundation

/// Launcher items in settings.json: each app, pane, system action and built-in command as a record.
@MainActor
final class LauncherSettingsFile {
    private typealias Record = LauncherFileFormat.Record

    /// Per-Mac bundles, keyed in the file by bundle ID.
    private enum Bundle {
        case app, pane

        var kind: AppEntry.Kind { self == .app ? .application : .systemSettings }
        var noun: String { self == .app ? "app" : "settings pane" }

        func action(_ bundleID: String) -> HotKeyAction {
            self == .app ? .app(bundleID: bundleID) : .settingsPane(bundleID: bundleID)
        }
    }

    private struct Item {
        let name: String
        let preferenceKey: String
        let action: HotKeyAction?
    }

    private let appIndex: AppIndex
    private let aliases: AliasStore
    private let visibility: VisibilityStore
    private let shortcuts: HotKeySettingsFile
    /// Records for a bundle this Mac lacks: written back as read, so a shared file keeps them.
    private var waiting: [SettingsFileKey: (bundle: Bundle, records: [String: Record])] = [:]

    init(
        appIndex: AppIndex, aliases: AliasStore, visibility: VisibilityStore,
        shortcuts: HotKeySettingsFile
    ) {
        self.appIndex = appIndex
        self.aliases = aliases
        self.visibility = visibility
        self.shortcuts = shortcuts
    }

    func appsBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        bundlesBinding(for: key, .app)
    }

    func panesBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        bundlesBinding(for: key, .pane)
    }

    func systemActionsBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        let items = SystemActionCatalog.all.map { action in
            Item(
                name: action.id.rawValue, preferenceKey: action.entryID,
                action: .systemAction(id: action.id))
        }
        return catalogBinding(for: key, items: items, noun: "system action")
    }

    /// The built-in commands `owner` lists; nil is the Commands pane's own.
    func commandsBinding(for key: SettingsFileKey, owner: SettingsTab?) -> SettingsFileBinding {
        let items = CommandID.allCases.filter { $0.owner == owner && !$0.isQueryDriven }.map { id in
            Item(
                name: String(id.rawValue.drop { $0 != ":" }.dropFirst()), preferenceKey: id.rawValue,
                action: id.hotKeyAction)
        }
        return catalogBinding(for: key, items: items, noun: "command")
    }

    func kindBinding(for key: SettingsFileKey, kind: AppEntry.Kind) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: { [visibility] in .bool(visibility.isKindEnabled(kind)) },
            write: { [visibility] json in
                guard let enabled = json.bool else { return [.invalidValue(key)] }
                visibility.setKindEnabled(enabled, for: kind)
                return []
            })
    }

    /// Applies each waiting record whose bundle has since been installed.
    func applyInstalled() -> [SettingsFileIssue] {
        var issues: [SettingsFileIssue] = []
        for (key, held) in waiting {
            let ready = held.records.filter { isInstalled($0.key, held.bundle) }
            guard !ready.isEmpty else { continue }
            let rest = held.records.filter { ready[$0.key] == nil }
            waiting[key] = rest.isEmpty ? nil : (held.bundle, rest)
            let items = ready.keys.sorted().map { item($0, held.bundle) }
            issues += apply(ready, to: items, noun: held.bundle.noun, key: key)
        }
        return issues
    }

    // MARK: - Bindings

    private func catalogBinding(
        for key: SettingsFileKey, items: [Item], noun: String
    ) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: { [self] in LauncherFileFormat.json(customized(items)) },
            write: { [self] json in
                guard let decoded = LauncherFileFormat.records(from: json) else {
                    return [.invalidValue(key)]
                }
                let known = Set(items.map(\.name))
                let unknown = decoded.records.keys.filter { !known.contains($0) }.sorted().map {
                    SettingsFileIssue.invalidEntry(key, "no \(noun) in this section is called “\($0)”")
                }
                return decoded.problems.map { .invalidEntry(key, $0) } + unknown
                    + apply(decoded.records, to: items, noun: noun, key: key)
            })
    }

    private func bundlesBinding(for key: SettingsFileKey, _ bundle: Bundle) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: { [self] in
                let live = customized(liveItems(bundle))
                let liveNames = Set(live.map(\.name))
                let held = (waiting[key]?.records ?? [:]).filter { !liveNames.contains($0.key) }
                let records = live + held.map { (name: $0.key, record: $0.value) }
                return LauncherFileFormat.json(records.sorted { $0.name < $1.name })
            },
            write: { [self] json in
                guard let decoded = LauncherFileFormat.records(from: json) else {
                    return [.invalidValue(key)]
                }
                let present = decoded.records.filter { isInstalled($0.key, bundle) }
                let absent = decoded.records.filter { present[$0.key] == nil }
                waiting[key] = absent.isEmpty ? nil : (bundle, absent)
                let names = Set(customized(liveItems(bundle)).map(\.name)).union(present.keys)
                return decoded.problems.map { .invalidEntry(key, $0) }
                    + apply(present, to: names.sorted().map { item($0, bundle) }, noun: bundle.noun, key: key)
            })
    }

    // MARK: - Items

    private func item(_ bundleID: String, _ bundle: Bundle) -> Item {
        Item(name: bundleID, preferenceKey: bundleID, action: bundle.action(bundleID))
    }

    /// Bound ones too, since an app outside the search scopes keeps its shortcut.
    private func liveItems(_ bundle: Bundle) -> [Item] {
        let hotKeys = shortcuts.hotKeys
        var bundleIDs = Set(bundle == .app ? hotKeys.boundBundleIDs : hotKeys.boundPaneBundleIDs)
        for entry in appIndex.apps where entry.kind == bundle.kind {
            if let bundleID = entry.bundleID { bundleIDs.insert(bundleID) }
        }
        return bundleIDs.map { item($0, bundle) }
    }

    private func isInstalled(_ bundleID: String, _ bundle: Bundle) -> Bool {
        switch bundle {
        case .app: !appIndex.isUninstalled(bundleID: bundleID)
        case .pane: appIndex.apps.contains { $0.kind == .systemSettings && $0.bundleID == bundleID }
        }
    }

    /// Only an item with something set, so the file lists what was customized.
    private func customized(_ items: [Item]) -> [(name: String, record: Record)] {
        let spelling = shortcuts.spelling
        return items.compactMap { item in
            let record = Record(
                shortcut: item.action.flatMap { shortcuts.text(for: $0, spelling) },
                alias: aliases.alias(for: item.preferenceKey),
                showInLauncher: visibility.isItemVisible(key: item.preferenceKey))
            return record.isEmpty ? nil : (item.name, record)
        }
    }

    /// An item the records leave out gets the empty one, so a line the file drops clears its row.
    private func apply(
        _ records: [String: Record], to items: [Item], noun: String, key: SettingsFileKey
    ) -> [SettingsFileIssue] {
        var issues: [SettingsFileIssue] = []
        var wanted: [HotKeySettingsFile.Wanted] = []
        for item in items {
            let record = records[item.name] ?? Record()
            aliases.setAlias(record.alias ?? "", for: item.preferenceKey)
            visibility.setItemVisible(record.showInLauncher, forKey: item.preferenceKey)
            let label = "\(noun) “\(item.name)”"
            if let action = item.action {
                wanted.append(HotKeySettingsFile.Wanted(action: action, text: record.shortcut, label: label))
            } else if record.shortcut != nil {
                issues.append(.invalidEntry(key, "\(label) can't have a shortcut"))
            }
        }
        return issues + shortcuts.apply(wanted, key: key)
    }
}
