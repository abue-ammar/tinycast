import Foundation

/// Window management's shortcuts, aliases and lists in settings.json, each kept with its record.
@MainActor
struct WindowManagementSettingsFile {
    let sizes: CustomWindowSizeStore
    let layouts: WindowLayoutStore
    let rooms: RoomStore
    let aliases: AliasStore
    let shortcuts: HotKeySettingsFile

    private var hotKeys: HotKeyManager { shortcuts.hotKeys }

    func commandShortcutsBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: {
                let spelling = shortcuts.spelling
                var texts: [WindowCommand.ID: String] = [:]
                for id in WindowCommand.ID.allCases {
                    texts[id] = shortcuts.text(for: .windowCommand(id: id), spelling)
                }
                return WindowManagementFileFormat.json(commandShortcuts: texts)
            },
            write: { json in
                guard let decoded = WindowManagementFileFormat.commandShortcuts(from: json) else {
                    return [.invalidValue(key)]
                }
                let wanted = WindowCommand.ID.allCases.compactMap { id in
                    decoded.texts[id].map { text in
                        HotKeySettingsFile.Wanted(
                            action: .windowCommand(id: id), text: text, label: "“\(id.rawValue)”")
                    }
                }
                return decoded.problems.map { .invalidEntry(key, $0) }
                    + shortcuts.apply(wanted, key: key)
            })
    }

    func commandAliasesBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: {
                var texts: [WindowCommand.ID: String] = [:]
                for command in WindowCommandCatalog.all {
                    texts[command.id] = aliases.alias(for: command.entryID)
                }
                return WindowManagementFileFormat.json(commandAliases: texts)
            },
            write: { json in
                guard let decoded = WindowManagementFileFormat.commandAliases(from: json) else {
                    return [.invalidValue(key)]
                }
                for command in WindowCommandCatalog.all {
                    guard let alias = decoded.texts[command.id] else { continue }
                    aliases.setAlias(alias ?? "", for: command.entryID)
                }
                return decoded.problems.map { .invalidEntry(key, $0) }
            })
    }

    func customSizesBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: {
                let spelling = shortcuts.spelling
                return .array(
                    sizes.sizes.map { size in
                        WindowManagementFileFormat.json(
                            size,
                            shortcut: shortcuts.text(for: .customWindowSize(id: size.id), spelling),
                            alias: aliases.alias(for: size.entryID))
                    })
            },
            write: { json in
                guard let decoded = WindowManagementFileFormat.customSizes(from: json) else {
                    return [.invalidValue(key)]
                }
                let previous = Set(sizes.sizes.map(\.entryID))
                let kept = sizes.replace(with: decoded.records)
                let rule = "a name is empty or used twice"
                return report(decoded, kept: kept, kind: "custom size", rule: rule, key: key)
                    + follow(
                        decoded,
                        records: sizes.sizes.map { Record(id: $0.id, name: $0.name, entryID: $0.entryID) },
                        previous: previous, bound: hotKeys.boundCustomWindowSizeIDs,
                        kind: "custom size", action: HotKeyAction.customWindowSize, key: key)
            })
    }

    func layoutsBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: {
                let spelling = shortcuts.spelling
                return .array(
                    layouts.layouts.map { layout in
                        WindowManagementFileFormat.json(
                            layout,
                            shortcut: shortcuts.text(for: .windowLayout(id: layout.id), spelling),
                            alias: aliases.alias(for: layout.entryID))
                    })
            },
            write: { json in
                guard let decoded = WindowManagementFileFormat.layouts(from: json) else {
                    return [.invalidValue(key)]
                }
                let previous = Set(layouts.layouts.map(\.entryID))
                let kept = layouts.replace(with: decoded.records)
                let rule = "a name is empty or used twice, or it has no apps"
                return report(decoded, kept: kept, kind: "layout", rule: rule, key: key)
                    + follow(
                        decoded,
                        records: layouts.layouts.map {
                            Record(id: $0.id, name: $0.name, entryID: $0.entryID)
                        },
                        previous: previous, bound: hotKeys.boundWindowLayoutIDs, kind: "layout",
                        action: HotKeyAction.windowLayout, key: key)
            })
    }

    func roomsBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: {
                let spelling = shortcuts.spelling
                return .array(
                    rooms.rooms.map { room in
                        WindowManagementFileFormat.json(
                            room, shortcut: shortcuts.text(for: .windowRoom(id: room.id), spelling),
                            alias: aliases.alias(for: room.entryID))
                    })
            },
            write: { json in
                guard let decoded = WindowManagementFileFormat.rooms(from: json) else {
                    return [.invalidValue(key)]
                }
                let learned = Dictionary(
                    rooms.rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let previous = Set(rooms.rooms.map(\.entryID))
                let kept = rooms.replace(
                    with: decoded.records.map { room in learned[room.id].map(room.keepingRuntime) ?? room })
                let rule = "a name is empty or used twice, or it has no windows"
                return report(decoded, kept: kept, kind: "room", rule: rule, key: key)
                    + follow(
                        decoded,
                        records: rooms.rooms.map { Record(id: $0.id, name: $0.name, entryID: $0.entryID) },
                        previous: previous, bound: hotKeys.boundWindowRoomIDs, kind: "room",
                        action: HotKeyAction.windowRoom, key: key)
            })
    }

    // MARK: - Records

    private struct Record {
        let id: UUID
        let name: String
        let entryID: String
    }

    private func report<Value>(
        _ decoded: WindowManagementFileFormat.Decoded<Value>, kept: Int, kind: String,
        rule: String, key: SettingsFileKey
    ) -> [SettingsFileIssue] {
        var issues = decoded.problems.map { SettingsFileIssue.invalidEntry(key, $0) }
        let skipped = decoded.records.count - kept
        if skipped > 0 {
            let noun = skipped == 1 ? "1 \(kind) was" : "\(skipped) \(kind)s were"
            issues.append(.invalidEntry(key, "\(noun) skipped: \(rule)"))
        }
        return issues
    }

    /// A record the file dropped takes its shortcut and alias with it; the rest take what it set.
    private func follow<Value>(
        _ decoded: WindowManagementFileFormat.Decoded<Value>, records: [Record],
        previous: Set<String>, bound: [UUID], kind: String, action: (UUID) -> HotKeyAction,
        key: SettingsFileKey
    ) -> [SettingsFileIssue] {
        let live = Set(records.map(\.id))
        for id in bound where !live.contains(id) {
            hotKeys.setBinding(nil, for: action(id))
        }
        aliases.removeKeys(previous.subtracting(records.map(\.entryID)))
        for record in records {
            guard let alias = decoded.aliases[record.id] else { continue }
            aliases.setAlias(alias ?? "", for: record.entryID)
        }
        let wanted = records.compactMap { record in
            decoded.shortcuts[record.id].map { text in
                HotKeySettingsFile.Wanted(
                    action: action(record.id), text: text, label: "\(kind) “\(record.name)”")
            }
        }
        return shortcuts.apply(wanted, key: key)
    }
}
