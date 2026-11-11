import Foundation

enum CommandID: String, CaseIterable, Sendable {
    case sample
    var name: String { rawValue }
    var hotKeyAction: HotKeyAction? { .command(self) }
}
struct SystemAction {
    enum ID: String, CaseIterable, Sendable { case sample }
    let name: String
}
enum SystemActionCatalog {
    static func action(id: SystemAction.ID) -> SystemAction { SystemAction(name: id.rawValue) }
}
struct WindowCommand {
    enum ID: String, CaseIterable, Sendable { case sample }
    let name: String
}
enum WindowCommandCatalog {
    static func command(id: WindowCommand.ID) -> WindowCommand? { WindowCommand(name: id.rawValue) }
}
enum StoredSnippet { typealias ID = String }
@MainActor
enum AppLauncher {
    static func toggle(bundleID: String) {}
    static func openSettingsPane(bundleID: String) {}
}
@MainActor
final class ModifierTapMonitor {
    var isPaused = false
    var onTrigger: ((HotKeyBinding) -> Void)?
    var onHoldPressed: (() -> Void)?
    var onHoldReleased: (() -> Void)?
    var onHoldCancelled: (() -> Void)?
    func start() {}
    func update(bound: Set<HotKeyBinding>, holdKey: ModifierKey?) {}
}
@MainActor
final class ShortcutCaptureSession {
    func start(action: HotKeyAction, hotKeys: HotKeyManager) {}
    func stop() {}
}
@MainActor
final class HotKeyCenter {
    struct Entry {
        let shortcut: KeyShortcut
        let onKeyDown: (UInt64) -> Void
        let onKeyUp: (() -> Void)?
    }
    static weak var current: HotKeyCenter?
    var entries: [String: Entry] = [:]
    var isPaused = false
    init() { Self.current = self }
    func register(
        id: String, shortcut: KeyShortcut, onKeyDown: @escaping (UInt64) -> Void, onKeyUp: (() -> Void)? = nil
    ) {
        entries[id] = Entry(shortcut: shortcut, onKeyDown: onKeyDown, onKeyUp: onKeyUp)
    }
    func unregister(id: String) { entries[id] = nil }
}
