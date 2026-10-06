import AppKit

@main
@MainActor
struct CommandDispatchTests {
    static var failures = 0
    static var passes = 0

    static func check(_ name: String, _ condition: Bool) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(name)")
        }
    }

    static func main() {
        let core = AppCore()
        let palette = PaletteCoordinator()
        let feature = DispatchProbe()
        let notes = NotesCoordinator()
        let coordinator = LauncherCoordinator(
            ranking: LauncherRankingStore(), windowController: PaletteWindowController(),
            paletteCoordinator: palette, settingsCoordinator: feature,
            customCommandCoordinator: feature, systemActionCoordinator: feature,
            quicklinkCoordinator: feature, windowCommandCoordinator: feature,
            windowLayoutCoordinator: feature, snippetCoordinator: feature,
            fileSearchCoordinator: feature, menuSearchCoordinator: feature,
            windowSwitchCoordinator: feature, notesCoordinator: notes,
            extensionCoordinator: feature, calendarCoordinator: feature, core: core)

        for (command, mode) in [
            (CommandID.calculatorHistory, PaletteMode.calculatorHistory), (.clipboardHistory, .clipboard),
            (.searchEmoji, .emoji), (.searchQuicklinks, .quicklinks)
        ] {
            palette.calls = []
            coordinator.runCommand(command)
            coordinator.runCommand(command)
            check("\(command) retains hotkey toggling", palette.calls == [.toggle(mode), .toggle(mode)])
            palette.calls = []
            coordinator.runCommand(command, reveal: true)
            coordinator.runCommand(command, reveal: true)
            check("\(command) reveals on repeated links", palette.calls == [.show(mode), .show(mode)])
        }

        for command in [CommandID.searchFiles, .searchMenuItems, .switchWindows, .define, .quickAI] {
            feature.calls = []
            core.dictionaryCoordinator.calls = []
            core.quickAICoordinator.calls = []
            coordinator.runCommand(command)
            coordinator.runCommand(command, reveal: true)
            let probe = switch command {
            case .define: core.dictionaryCoordinator
            case .quickAI: core.quickAICoordinator
            default: feature
            }
            check("\(command) forwards its invocation policy", probe.calls == ["show:false", "show:true"])
        }
        for command in [CommandID.mySchedule, .searchSnippets, .switchRoom] {
            let probe = command == .switchRoom ? core.roomCoordinator : feature
            probe.calls = []
            coordinator.runCommand(command)
            coordinator.runCommand(command, reveal: true)
            check("\(command) forwards reveal", probe.calls == ["show:false", "show:true"])
        }
        core.aiChatCoordinator.calls = []
        coordinator.runCommand(.aiChat)
        coordinator.runCommand(.aiChat)
        check("AI Chat retains hotkey toggling", core.aiChatCoordinator.calls == ["toggleWindow", "toggleWindow"])
        core.aiChatCoordinator.calls = []
        coordinator.runCommand(.aiChat, reveal: true)
        coordinator.runCommand(.aiChat, reveal: true)
        check("AI Chat reveals on repeated links", core.aiChatCoordinator.calls == ["showWindow", "showWindow"])
        notes.calls = []
        coordinator.runCommand(.showNotes)
        coordinator.runCommand(.showNotes, reveal: true)
        check("Notes links show rather than toggle", notes.calls == ["toggle", "show"])
        core.quickActionCoordinator.calls = []
        coordinator.runCommand(.fixGrammar, reveal: true)
        check("a built-in quick action uses its coordinator", core.quickActionCoordinator.calls == ["fixGrammar"])

        for command in [CommandID.searchEmoji, .openCamera, .fixGrammar] {
            let entry = AppEntry(id: command.rawValue, kind: command == .fixGrammar ? .quickAction : .command)
            check("native row copies its matching command", coordinator.deeplink(for: entry) == CommandDeepLink.url(for: command))
        }
        check("application rows have no command link", coordinator.deeplink(for: AppEntry(id: "app", kind: .application)) == nil)
        check(
            "custom quick actions have no native link",
            coordinator.deeplink(for: AppEntry(id: "quickAction:custom", kind: .quickAction)) == nil)
        let extensionEntry = AppEntry(id: "extension:demo/search", kind: .extensionCommand)
        check("uninstalled extension has no link", coordinator.deeplink(for: extensionEntry) == nil)
        core.extensions.installed = true
        let extensionURL = coordinator.deeplink(for: extensionEntry)
        check(
            "installed extension copies a scoped address",
            extensionURL?.absoluteString == "tinycast://extensions/owner/demo/search")
        check("installed extension stays outside native routing", extensionURL.map { !CommandDeepLink.claims($0) } == true)

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}

enum HotKeyAction: Equatable { case command(CommandID) }
enum PaletteMode: Equatable { case calculatorHistory, clipboard, emoji, quicklinks }

struct AppEntry {
    enum Kind {
        case application, systemSettings, command, quickAction, customCommand, systemAction, windowCommand
        case windowRoom, windowLayout, extensionCommand, meeting, quicklink, appleShortcut, snippet
        static func named(by query: String) -> Kind? { nil }
    }
    let id: String
    let kind: Kind
    var preferenceKey: String { id }
    var bundleID: String? { nil }
    var url: URL { URL(filePath: "/") }
}

enum CommandCatalog {
    static func command(for entry: AppEntry) -> CommandID? { CommandID(rawValue: entry.id) }
    static func isQueryDriven(_ entry: AppEntry) -> Bool { command(for: entry)?.isQueryDriven == true }
}

enum EntryID {
    static let sfSymbol = "link"
    static func id(fromEntryID id: String) -> UUID? { UUID(uuidString: id) }
}
typealias CustomQuickAction = EntryID
typealias CustomCommand = EntryID
typealias CustomWindowSize = EntryID
typealias Room = EntryID
typealias WindowLayout = EntryID
typealias MeetingEvent = EntryID
typealias Quicklink = EntryID
typealias AppleShortcut = EntryID
typealias StoredSnippet = EntryID

enum ActionCatalog {
    struct Action { let id: String }
    static func action(forEntryID id: String) -> Action? { nil }
    static func command(forEntryID id: String) -> Action? { nil }
}
typealias SystemActionCatalog = ActionCatalog
typealias WindowCommandCatalog = ActionCatalog

@MainActor
final class LauncherRankingStore {
    func visit(itemKey: String, query: String?) {}
    func reset(itemKey: String) {}
}

@MainActor
final class PaletteWindowController {
    var previousTarget: Int? { nil }
    var previousApp: NSRunningApplication? { nil }
}

@MainActor
final class PaletteCoordinator {
    enum Call: Equatable { case show(PaletteMode), toggle(PaletteMode) }
    var calls: [Call] = []
    var isVisible = false
    func showPalette(mode: PaletteMode) { calls.append(.show(mode)) }
    func togglePalette(mode: PaletteMode) { calls.append(.toggle(mode)) }
    func hidePalette(restoreFocus: Bool) {}
}

@MainActor
final class DispatchProbe {
    var calls: [String] = []
    func show(reveal: Bool = false) { calls.append("show:\(reveal)") }
    func showSchedule(reveal: Bool) { show(reveal: reveal) }
    func showSnippets(reveal: Bool) { show(reveal: reveal) }
    func showRooms(reveal: Bool) { show(reveal: reveal) }
    func toggle() { calls.append("toggle") }
    func run(_ action: BuiltInQuickAction) { calls.append(action.rawValue) }
    func run(id: UUID) {}
    func showWindow() { calls.append("showWindow") }
    func toggleWindow() { calls.append("toggleWindow") }
    func showSupport() {}
    func pasteNextInSequence() {}
    func checkForUpdates() {}
    func runCustomCommand(id: UUID, values: [String: String]) {}
    func runSystemAction(id: String) {}
    func runWindowCommand(id: String) {}
    func runCustomWindowSize(id: UUID) {}
    func enterRoom(id: UUID) {}
    func runWindowLayout(id: UUID) {}
    func runExtensionCommand(_ entry: AppEntry, arguments: [String: String]) {}
    func activateMeeting(id: UUID) {}
    func openQuicklink(id: UUID, values: [String: String]) {}
    func expandSnippet(id: UUID, target: Int?) {}
    func joinNextMeeting() {}
    func copyNextMeetingLink() {}
    func openNextMeetingInCalendar() {}
    func createEvent() {}
    func createNote() {}
    func searchNotes() {}
    func editSnippet(_ record: Int?) {}
    func editWindowLayout(_ record: Int?) {}
    func captureWindowLayout() {}
    func createRoom() {}
    func editQuicklink(_ record: Int?) {}
    func importQuicklinks() async {}
    func exportQuicklinks() async {}
    func showBackupSettings() {}
    func showSettings() {}
    func showAbout() {}
}
typealias SettingsCoordinator = DispatchProbe
typealias CustomCommandCoordinator = DispatchProbe
typealias SystemActionCoordinator = DispatchProbe
typealias QuicklinkCoordinator = DispatchProbe
typealias WindowCommandCoordinator = DispatchProbe
typealias WindowLayoutCoordinator = DispatchProbe
typealias SnippetCoordinator = DispatchProbe
typealias FileSearchCoordinator = DispatchProbe
typealias MenuSearchCoordinator = DispatchProbe
typealias WindowSwitchCoordinator = DispatchProbe
typealias ExtensionCoordinator = DispatchProbe
typealias CalendarCoordinator = DispatchProbe

@MainActor
final class NotesCoordinator {
    var calls: [String] = []
    func show() { calls.append("show") }
    func toggle() { calls.append("toggle") }
    func createNote() {}
    func searchNotes() {}
}

@MainActor
final class ExtensionManager {
    struct Manifest { let name: String }
    struct Installed { let manifest: Manifest }
    struct Command { let name: String }
    var installed = false
    func resolve(_ entry: AppEntry) -> (Installed, Command)? {
        installed ? (Installed(manifest: Manifest(name: "owner/demo")), Command(name: "search")) : nil
    }
}

@MainActor
final class AppCore {
    let quickAICoordinator = DispatchProbe()
    let aiChatCoordinator = DispatchProbe()
    let quickActionCoordinator = DispatchProbe()
    let clipboardCoordinator = DispatchProbe()
    let cameraCoordinator = DispatchProbe()
    let dictionaryCoordinator = DispatchProbe()
    let roomCoordinator = DispatchProbe()
    let appleShortcutCoordinator = DispatchProbe()
    let updateCoordinator = DispatchProbe()
    let supportCoordinator = DispatchProbe()
    let extensions = ExtensionManager()
    enum Tone { case success }
    func showMessage(_ message: String, tone: Tone) {}
}

enum AppLauncher {
    static func open(_ url: URL) {}
    static func launch(_ url: URL) {}
    static func showInFinder(_ url: URL) {}
    static func openSettingsPane(bundleID: String) {}
    static func quit(bundleID: String, force: Bool) -> Bool { false }
    static func restart(bundleID: String, url: URL) async {}
}

enum BackupActions {
    static func runExportCommand(core: AppCore) async {}
    static func runImportCommand(core: AppCore) async {}
}
