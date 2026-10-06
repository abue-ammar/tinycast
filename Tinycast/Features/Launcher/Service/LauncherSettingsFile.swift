import Foundation

/// Launcher items in settings.json: each app, pane, system action and built-in command as a record.
@MainActor
final class LauncherSettingsFile {
    private typealias Record = LauncherFileFormat.Record

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

    private struct BundleRecords {
        let bundle: Bundle
        var applied: Set<String> = []
        var waiting: [String: Record] = [:]
    }

    private let appIndex: AppIndex
    private let aliases: AliasStore
    private let visibility: VisibilityStore
    private let shortcuts: HotKeySettingsFile
    private var bundleRecords: [SettingsFileKey: BundleRecords] = [:]

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

    func applyInstalled() -> [SettingsFileIssue] {
        var issues: [SettingsFileIssue] = []
        for (key, var held) in bundleRecords {
            guard !held.waiting.isEmpty else { continue }
            let known = knownBundleIDs(held.bundle)
            let ready = held.waiting.filter { known.contains($0.key) }
            guard !ready.isEmpty else { continue }
            held.applied.formUnion(ready.keys)
            for name in ready.keys { held.waiting[name] = nil }
            bundleRecords[key] = held
            let items = ready.keys.sorted().map { item($0, held.bundle) }
            issues += apply(ready, to: items, noun: held.bundle.noun, key: key)
        }
        return issues + shortcuts.commit()
    }

    // MARK: - Bindings

    private func catalogBinding(
        for key: SettingsFileKey, items: [Item], noun: String
    ) -> SettingsFileBinding {
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        return SettingsFileBinding(
            key,
            read: { [self] in LauncherFileFormat.json(customized(items)) },
            write: { [self] json in
                let spelling = shortcuts.spelling
                let read = LauncherFileFormat.records(from: json) { name in
                    byName[name].map { record(of: $0, spelling) } ?? Record()
                }
                guard let decoded = read else { return [.invalidValue(key)] }
                let unknown = decoded.records.keys.filter { byName[$0] == nil }.sorted().map {
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
                let state = bundleRecords[key]
                let known = knownBundleIDs(bundle).union(state?.applied ?? [])
                let live = customized(known.map { item($0, bundle) })
                let liveNames = Set(live.map(\.name))
                let held = (state?.waiting ?? [:]).filter { !liveNames.contains($0.key) }
                let records = live + held.map { (name: $0.key, record: $0.value) }
                return LauncherFileFormat.json(records.sorted { $0.name < $1.name })
            },
            write: { [self] json in
                let previous = bundleRecords[key]
                let spelling = shortcuts.spelling
                let read = LauncherFileFormat.records(from: json) { name in
                    previous?.waiting[name] ?? record(of: item(name, bundle), spelling)
                }
                guard let decoded = read else { return [.invalidValue(key)] }
                let known = knownBundleIDs(bundle).union(previous?.applied ?? [])
                let present = decoded.records.filter { known.contains($0.key) }
                bundleRecords[key] = BundleRecords(
                    bundle: bundle, applied: Set(present.keys),
                    waiting: decoded.records.filter { !known.contains($0.key) })
                let live = customized(known.map { item($0, bundle) }).map(\.name)
                let items = Set(live).union(present.keys).sorted().map { item($0, bundle) }
                return decoded.problems.map { .invalidEntry(key, $0) }
                    + apply(present, to: items, noun: bundle.noun, key: key)
            })
    }

    // MARK: - Items

    private func item(_ bundleID: String, _ bundle: Bundle) -> Item {
        Item(name: bundleID, preferenceKey: bundleID, action: bundle.action(bundleID))
    }

    /// What Settings lists, plus a bound app outside the search scopes, which keeps its shortcut.
    private func knownBundleIDs(_ bundle: Bundle) -> Set<String> {
        let hotKeys = shortcuts.hotKeys
        var bundleIDs = Set(bundle == .app ? hotKeys.boundBundleIDs : hotKeys.boundPaneBundleIDs)
        for entry in appIndex.apps where entry.kind == bundle.kind {
            if let bundleID = entry.bundleID { bundleIDs.insert(bundleID) }
        }
        return bundleIDs
    }

    private func record(of item: Item, _ spelling: HotKeySpelling) -> Record {
        Record(
            shortcut: item.action.flatMap { shortcuts.text(for: $0, spelling) },
            alias: aliases.alias(for: item.preferenceKey),
            showInLauncher: visibility.isItemVisible(key: item.preferenceKey))
    }

    private func customized(_ items: [Item]) -> [(name: String, record: Record)] {
        let spelling = shortcuts.spelling
        return items.compactMap { item in
            let record = self.record(of: item, spelling)
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
