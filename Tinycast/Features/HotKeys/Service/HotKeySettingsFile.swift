import Foundation

/// Shortcuts as settings.json spells them, applied through `HotKeyManager` and its conflict rules.
@MainActor
struct HotKeySettingsFile {
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
    }

    let hotKeys: HotKeyManager

    /// Built per read, because the keyboard layout and the Hyper chord both change at run time.
    var spelling: HotKeySpelling {
        HotKeySpelling(
            characters: ASCIIKeyboardLayout.baseCharacters(for: 0..<128),
            hyperModifiers: KeyShortcut.displayedHyperChord().map(KeyShortcut.carbonModifiers(from:)))
    }

    func text(for action: HotKeyAction, _ spelling: HotKeySpelling) -> String? {
        hotKeys.binding(for: action).map(spelling.text(for:))
    }

    /// One action's chord, or `null` while it is unbound; `name` labels what the file reports.
    func binding(for key: SettingsFileKey, action: HotKeyAction, name: String) -> SettingsFileBinding {
        SettingsFileBinding(
            key,
            read: { text(for: action, spelling).settingsJSON },
            write: { json in
                guard let text = String?(settingsJSON: json) else { return [.invalidValue(key)] }
                return apply([Wanted(action: action, text: text, label: name)], key: key)
            })
    }

    /// Clears every changed binding first, so two shortcuts the file swaps never block each other.
    func apply(_ wanted: [Wanted], key: SettingsFileKey) -> [SettingsFileIssue] {
        let spelling = self.spelling
        var issues: [SettingsFileIssue] = []
        var changes: [Change] = []
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
            changes.append(
                Change(
                    action: item.action, binding: binding, previous: current, label: item.label,
                    text: text))
        }
        for change in changes {
            guard let owner = hotKeys.conflictOwner(of: change.binding, excluding: change.action) else {
                hotKeys.setBinding(change.binding, for: change.action)
                continue
            }
            issues.append(.invalidEntry(key, "\(change.label): “\(change.text)” already runs \(owner)"))
            // The old binding returns when it is still free, so a clash never costs a working one.
            if let previous = change.previous,
                hotKeys.conflictOwner(of: previous, excluding: change.action) == nil
            {
                hotKeys.setBinding(previous, for: change.action)
            }
        }
        return issues
    }
}
