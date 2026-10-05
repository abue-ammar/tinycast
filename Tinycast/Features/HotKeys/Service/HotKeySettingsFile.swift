import Foundation

/// Shortcuts as settings.json spells them, applied through `HotKeyManager` and its conflict rules.
@MainActor
final class HotKeySettingsFile {
    struct Wanted {
        let action: HotKeyAction
        let text: String?
        let label: String
    }

    private struct Change {
        let action: HotKeyAction
        let binding: HotKeyBinding
        let previous: HotKeyBinding?
        let label: String
        let text: String
        let key: SettingsFileKey
    }

    let hotKeys: HotKeyManager
    private var pending: [Change] = []

    init(hotKeys: HotKeyManager) {
        self.hotKeys = hotKeys
    }

    /// Built per read, because the keyboard layout and the Hyper chord both change at run time.
    var spelling: HotKeySpelling {
        HotKeySpelling(
            characters: ASCIIKeyboardLayout.baseCharacters(for: 0..<128),
            hyperModifiers: KeyShortcut.displayedHyperChord().map(KeyShortcut.carbonModifiers(from:)))
    }

    func text(for action: HotKeyAction, _ spelling: HotKeySpelling) -> String? {
        hotKeys.binding(for: action).map(spelling.text(for:))
    }

    func binding(for key: SettingsFileKey, action: HotKeyAction, name: String) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: { [self] in text(for: action, spelling).settingsJSON },
            write: { [self] json in
                guard let text = String?(settingsJSON: json) else { return [.invalidValue(key)] }
                return apply([Wanted(action: action, text: text, label: name)], key: key)
            })
    }

    /// Clears changed bindings now and leaves setting them to `commit`, so a moved chord never collides.
    func apply(_ wanted: [Wanted], key: SettingsFileKey) -> [SettingsFileIssue] {
        let spelling = self.spelling
        var issues: [SettingsFileIssue] = []
        for item in wanted {
            let current = hotKeys.binding(for: item.action)
            guard let text = item.text else {
                if current != nil { hotKeys.setBinding(nil, for: item.action) }
                continue
            }
            guard let binding = spelling.binding(from: text) else {
                issues.append(
                    .invalidEntry(key, "\(item.label): “\(text)” isn't a shortcut Tinycast can bind"))
                continue
            }
            guard binding != current else { continue }
            if current != nil { hotKeys.setBinding(nil, for: item.action) }
            pending.append(
                Change(
                    action: item.action, binding: binding, previous: current, label: item.label,
                    text: text, key: key))
        }
        return issues
    }

    /// Sets what `apply` queued; a chord another action holds is reported, and the old one returns.
    func commit() -> [SettingsFileIssue] {
        let changes = pending
        pending.removeAll()
        var issues: [SettingsFileIssue] = []
        for change in changes {
            guard let owner = hotKeys.conflictOwner(of: change.binding, excluding: change.action) else {
                hotKeys.setBinding(change.binding, for: change.action)
                continue
            }
            issues.append(
                .invalidEntry(change.key, "\(change.label): “\(change.text)” already runs \(owner)"))
            if let previous = change.previous,
                hotKeys.conflictOwner(of: previous, excluding: change.action) == nil
            {
                hotKeys.setBinding(previous, for: change.action)
            }
        }
        return issues
    }
}
