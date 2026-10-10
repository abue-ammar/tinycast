import AppKit
import SwiftUI

@main
@MainActor
struct QuicklinkCoordinatorTests {
    static var failures = 0
    static var passes = 0

    static func main() async throws {
        try await missingSelection()
        try await readableSelection()
        try await clipboardFallback()
        try await combinedArguments()
        try await plainLink()
        try copying()
        try editing()
        try await deleting()
        try revealing()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func missingSelection() async throws {
        for token in ["selection", "selectedText"] {
            let fixture = try Fixture(link: "https://de.wikipedia.org/w/index.php?search={\(token)}")
            defer { fixture.cleanUp() }
            fixture.coordinator.openQuicklink(id: fixture.link.id, forcingDefaultApp: true)
            try await Task.sleep(for: .milliseconds(1))
            expect(QuicklinkLauncher.opened.isEmpty, "an unreadable \(token) never opens an empty search")
            expect(fixture.window.isVisible, "an unreadable \(token) shows Search Quicklinks")
            expect(fixture.core.palette.selection == 1, "the prompt selects the requested quicklink")
            expect(
                fixture.core.palette.pendingArgumentEntryID == fixture.link.entryID,
                "the prompt requests argument focus after showing the palette")
            expect(
                fixture.accessory()?.firstIncompleteField == "Selected Text",
                "the selection field receives focus")

            fixture.core.palette.pendingArgumentEntryID = nil
            fixture.coordinator.openQuicklink(id: fixture.link.id)
            try await Task.sleep(for: .milliseconds(1))
            expect(QuicklinkLauncher.opened.isEmpty, "submitting the empty selection field keeps prompting")
            fixture.coordinator.openQuicklink(id: fixture.link.id, values: ["Selected Text": "Swift & macOS"])
            await waitForOpen()
            expect(
                QuicklinkLauncher.opened.first?.link
                    == "https://de.wikipedia.org/w/index.php?search=Swift%20%26%20macOS",
                "manual selection is encoded once")
            expect(QuicklinkLauncher.opened.first?.app == nil, "the default-app override survives the prompt")
            expect(!fixture.window.isVisible, "a completed prompt closes the palette")
        }
    }

    static func readableSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.injector.selection = "selected text"
        expect(fixture.accessory()?.firstIncompleteField == nil, "a normal selection chip stays optional")
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        await waitForOpen()
        expect(
            QuicklinkLauncher.opened.first?.link == "https://example.com/?q=selected%20text",
            "a readable selection opens immediately")
        expect(fixture.palette.shows == 0, "a readable selection needs no prompt")
        expect(QuicklinkLauncher.opened.first?.app == "com.example.browser", "the saved handler is used")

        QuicklinkLauncher.opened = []
        fixture.window.isVisible = true
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        await waitForOpen()
        expect(fixture.injector.target == .previous, "palette activation reads the previous app")
    }

    static func clipboardFallback() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.quicklinkSelectionFallback = .clipboard
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        await waitForOpen()
        expect(
            QuicklinkLauncher.opened.first?.link == "https://example.com/?q=clipboard%20text",
            "clipboard fallback still opens without prompting")
        expect(fixture.palette.shows == 0, "clipboard fallback never requests selection input")
        expect(fixture.accessory() == nil, "clipboard fallback has no selection chip")
    }

    static func combinedArguments() async throws {
        let fixture = try Fixture(link: "https://example.com/?q={selection}&site={argument name=\"Site\"}")
        defer { fixture.cleanUp() }
        fixture.coordinator.openQuicklink(id: fixture.link.id, values: ["Site": "swift.org"])
        try await Task.sleep(for: .milliseconds(1))
        expect(QuicklinkLauncher.opened.isEmpty, "filled arguments cannot bypass a missing selection")
        expect(
            fixture.accessory()?.firstIncompleteField == "Selected Text",
            "filled arguments leave selection focused")
        expect(
            fixture.core.palette.commandArguments[PaletteState.argumentKey(fixture.link.entryID, "Site")]
                == "swift.org",
            "the selection prompt preserves entered arguments")

        fixture.coordinator.openQuicklink(id: fixture.link.id, values: ["Selected Text": "Swift"])
        expect(
            fixture.accessory()?.firstIncompleteField == "Site",
            "a required argument is focused before selection")
        fixture.coordinator.openQuicklink(
            id: fixture.link.id, values: ["Selected Text": "Swift", "Site": "swift.org"])
        await waitForOpen()
        expect(
            QuicklinkLauncher.opened.first?.link == "https://example.com/?q=Swift&site=swift.org",
            "selection and declared arguments resolve together")
    }

    static func plainLink() async throws {
        let fixture = try Fixture(link: "https://example.com/")
        defer { fixture.cleanUp() }
        fixture.settings.quicklinksEnabled = false
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        try await Task.sleep(for: .milliseconds(1))
        expect(
            QuicklinkLauncher.opened.isEmpty && fixture.palette.shows == 0, "disabled quicklinks remain inert"
        )
        fixture.settings.quicklinksEnabled = true
        fixture.coordinator.openQuicklink(id: fixture.link.id)
        await waitForOpen()
        expect(
            QuicklinkLauncher.opened.first?.link == fixture.link.link,
            "a plain link opens without selection input")
    }

    static func copying() throws {
        for succeeds in [true, false] {
            let fixture = try Fixture(link: "https://example.com/?q={argument}&selection={selection}")
            defer { fixture.cleanUp() }
            Paster.copies = []
            Paster.succeeds = succeeds
            fixture.window.isVisible = true
            fixture.coordinator.copyQuicklink(id: fixture.link.id)
            expect(Paster.copies == [fixture.link.link], "copying writes the saved template literally")
            expect(!fixture.window.isVisible, "copying dismisses the palette")
            expect(QuicklinkLauncher.opened.isEmpty, "copying never opens the destination")
            expect(
                fixture.core.messages == [succeeds ? "Link copied" : "Couldn’t copy link"],
                "copy feedback reflects whether the clipboard write succeeded")
        }
        Paster.succeeds = true
    }

    static func editing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.window.isVisible = true
        fixture.coordinator.editQuicklink(fixture.link)
        expect(
            fixture.window.isVisible && fixture.core.palette.mode == .quicklinkEditor,
            "editing opens the launcher form")
        expect(
            fixture.coordinator.editor?.original == fixture.link,
            "the editor opens on the chosen quicklink")
        fixture.coordinator.editor?.name = "Updated name"
        fixture.coordinator.setQuicklinkEnabled(false, id: fixture.link.id)
        fixture.coordinator.saveQuicklink()
        expect(
            fixture.store.quicklink(id: fixture.link.id)?.name == "Updated name"
                && fixture.store.quicklink(id: fixture.link.id)?.isEnabled == false,
            "saving an edit preserves the current enabled state from Settings")
        expect(
            fixture.coordinator.editor == nil && !fixture.window.isVisible,
            "saving closes a directly summoned editor")

        fixture.settings.quicklinksEnabled = false
        fixture.coordinator.editQuicklink(nil)
        expect(fixture.coordinator.editor == nil, "a disabled feature cannot open an editor")
        fixture.settings.quicklinksEnabled = true
        fixture.coordinator.editQuicklink(nil)
        fixture.coordinator.editor?.name = "New link"
        fixture.coordinator.editor?.link = "https://example.com/new"
        fixture.settings.quicklinksEnabled = false
        fixture.coordinator.saveQuicklink()
        expect(fixture.store.quicklinks.count == 2, "disabling the feature prevents saving a draft")
        fixture.settings.quicklinksEnabled = true
        fixture.coordinator.saveQuicklink()
        expect(fixture.store.quicklinks.count == 3, "creation resumes after re-enabling the feature")

        fixture.coordinator.editQuicklink(fixture.link)
        try fixture.store.remove(id: fixture.link.id)
        fixture.coordinator.saveQuicklink()
        expect(
            fixture.coordinator.editor?.errorMessage != nil
                && fixture.coordinator.editor?.original == fixture.link
                && fixture.store.quicklink(id: fixture.link.id) == nil,
            "saving a removed item reports the failure without losing the draft or recreating it")
    }

    static func deleting() async throws {
        for confirmsInSettings in [false, true] {
            let fixture = try Fixture()
            defer { fixture.cleanUp() }
            fixture.settings.quicklinkConfirmsBeforeDelete = confirmsInSettings
            await fixture.coordinator.deleteQuicklink(id: fixture.link.id, alwaysConfirm: true)
            expect(
                fixture.core.confirmations == 1 && fixture.store.quicklink(id: fixture.link.id) != nil,
                "Settings deletion always confirms and cancellation preserves the item")
            fixture.core.confirmations = 0
            await fixture.coordinator.deleteQuicklink(id: fixture.link.id)
            expect(
                fixture.core.confirmations == (confirmsInSettings ? 1 : 0)
                    && (fixture.store.quicklink(id: fixture.link.id) != nil) == confirmsInSettings,
                "launcher deletion still follows its confirmation setting")
        }
    }

    static func revealing() throws {
        let folder = try Fixture(link: "/Applications")
        defer { folder.cleanUp() }
        AppLauncher.revealed = []
        folder.window.isVisible = true
        expect(folder.coordinator.showQuicklinkInFinder(folder.link), "a folder link is revealed")
        expect(
            AppLauncher.revealed == [URL(fileURLWithPath: "/Applications")],
            "Finder is shown the folder itself")
        expect(!folder.window.isVisible, "revealing leaves the palette")

        for link in ["https://example.com/", "~/Notes/{date}.md"] {
            let fixture = try Fixture(link: link)
            defer { fixture.cleanUp() }
            fixture.window.isVisible = true
            expect(!fixture.coordinator.showQuicklinkInFinder(fixture.link), "\(link) has nothing to reveal")
            expect(fixture.window.isVisible, "\(link) leaves the palette open")
        }
        expect(AppLauncher.revealed.count == 1, "only the folder link reached Finder")
    }

    static func waitForOpen() async {
        let deadline = ContinuousClock.now + .seconds(2)
        while QuicklinkLauncher.opened.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        expect(QuicklinkLauncher.opened.count == 1, "one destination opens")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    @MainActor
    final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: QuicklinkStore
        let link: Quicklink
        let settings = AppSettings()
        let injector = TextInjector()
        let window = PaletteWindowController()
        let core = AppCore()
        let palette: PaletteCoordinator
        let coordinator: QuicklinkCoordinator

        init(link: String = "https://example.com/?q={selection}") throws {
            QuicklinkLauncher.opened = []
            store = QuicklinkStore(directory: directory)
            try store.add(Quicklink(name: "A different quicklink", link: "https://example.com/"))
            self.link = try store.add(
                Quicklink(name: "Wikipedia", link: link, openWithBundleID: "com.example.browser"))
            palette = PaletteCoordinator(window: window, state: core.palette)
            coordinator = QuicklinkCoordinator(
                store: store, settings: settings, appIndex: AppIndex(), injector: injector,
                hotKeys: HotKeyManager(), favorites: FavoritesStore(), visibility: VisibilityStore(),
                ranking: LauncherRankingStore(), aliases: AliasStore(), windowController: window,
                paletteCoordinator: palette,
                clipboardHistory: { ["clipboard text"] }, core: core)
            core.quicklinkCoordinator = coordinator
        }

        func accessory() -> PaletteHeaderAccessory? {
            QuicklinkArgumentsAccessory.make(
                quicklink: link, core: core, vm: core.palette,
                focus: FocusState<String?>().projectedValue, placement: .besideSearchField,
                onOpenOptions: { _ in }, onSubmit: {})
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }
}

// Platform collaborators are inert so the shipped coordinator never opens apps or reads selections.
@MainActor
final class AppSettings {
    var quicklinksEnabled = true
    var quicklinksShowInLauncher = true
    var quicklinkSelectionFallback = QuicklinkSelectionFallback.ask
    var quicklinkOpensNewWindow = false
    var quicklinkConfirmsBeforeDelete = false
    var interfaceSize = InterfaceSize()
}

struct InterfaceSize { var metrics: Int { 0 } }
enum CommandID { case createQuicklink, searchQuicklinks, importQuicklinks, exportQuicklinks }

@MainActor
final class AppIndex {
    func setQuicklinks(_ links: [Quicklink]) {}
    func setCommandsVisible(_ commands: Set<CommandID>, _ visible: Bool) {}
    func setCommandsListed(_ commands: Set<CommandID>, _ listed: Bool) {}
}

enum InjectionTarget: Equatable { case frontmost, previous; static func current() -> Self? { .frontmost } }

@MainActor
final class TextInjector {
    var selection = ""
    var target: InjectionTarget?
    func captureExpansionContext(
        target: InjectionTarget?, clipboardHistory: [String]
    ) -> SnippetTemplateEngine.ExpansionContext {
        self.target = target
        return .init(
            clipboardHistory: clipboardHistory, selection: selection, now: .distantPast,
            calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!)
    }
}

enum HotKeyAction: Equatable { case quicklink(id: UUID) }
@MainActor
final class HotKeyManager {
    var recordingAction: HotKeyAction?
    func setBinding(_ binding: String?, for action: HotKeyAction) {}
}
final class FavoritesStore { func remove(keys: Set<String>) {} }
final class VisibilityStore { func removeItemKeys(_ keys: Set<String>) {} }
final class LauncherRankingStore { func reset(itemKey: String) {} }
final class AliasStore { func removeKeys(_ keys: Set<String>) {} }

@MainActor
final class PaletteWindowController {
    var isVisible = false
    var previousTarget: InjectionTarget? = .previous
}

enum PaletteMode { case launcher, quicklinks, quicklinkEditor }
@MainActor
final class PaletteState {
    var mode = PaletteMode.launcher
    var selection = 0
    var commandArguments: [String: String] = [:]
    var pendingArgumentEntryID: String?
    func prepare(mode: PaletteMode) { self.mode = mode }
    func pop(preservingSelection: Bool) -> Bool { false }
    static func argumentKey(_ entryID: String, _ name: String) -> String { entryID + "\u{1}" + name }
}

@MainActor
final class PaletteCoordinator {
    let window: PaletteWindowController
    let state: PaletteState
    var shows = 0
    init(window: PaletteWindowController, state: PaletteState) { self.window = window; self.state = state }
    func showPalette(mode: PaletteMode) {
        state.prepare(mode: mode)
        shows += 1
        window.isVisible = true
        state.selection = 0
        state.commandArguments = [:]
        state.pendingArgumentEntryID = nil
    }
    var isVisible: Bool { window.isVisible }
    func hidePalette(restoreFocus: Bool = true) { window.isVisible = false }
}

@MainActor
enum Paster {
    static var copies: [String] = []
    static var succeeds = true
    static func copyPlainText(_ text: String) -> Bool {
        copies.append(text)
        return succeeds
    }
}

@MainActor
enum AppLauncher {
    static var revealed: [URL] = []
    static func showInFinder(_ url: URL) { revealed.append(url) }
}

enum DialogTone { case danger, neutral, success }
@MainActor
final class AppCore {
    let palette = PaletteState()
    let settings = AppSettings()
    lazy var quicklinkCoordinator: QuicklinkCoordinator = {
        fatalError("The fixture must wire the coordinator")
    }()
    var messages: [String] = []
    var confirmations = 0
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {}
    func reportFailure(title: String, message: String, symbol: String, recovery: String) async -> Bool {
        false
    }
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool {
        confirmations += 1
        return false
    }
    func showMessage(_ message: String) { messages.append(message) }
}

enum BackupActions {
    static func chooseSaveLocation(named: String) -> URL? { nil }
    static func chooseJSONFile() -> URL? { nil }
}

@MainActor
enum QuicklinkLauncher {
    struct Opened { let link: String; let app: String? }
    static var opened: [Opened] = []
    enum Failure: LocalizedError {
        case refused
        var missingApplicationBundleID: String? { nil }
    }
    static func open(_ link: String, openWithBundleID: String?, inNewWindow: Bool) async throws(Failure) {
        opened.append(Opened(link: link, app: openWithBundleID))
    }
}

struct InlineArgument { let id: String; let title: String; let options: [String]; let isOptional: Bool }
struct InlineArgumentFields: View {
    let arguments: [InlineArgument]
    let symbol: String?
    let value: (String) -> Binding<String>
    let focused: FocusState<String?>.Binding
    let openOptions: (String) -> Void
    let onSubmit: () -> Void
    var body: some View { EmptyView() }
    static func totalWidth(for arguments: [InlineArgument], hasIcon: Bool, metrics: Int) -> CGFloat { 0 }
}

struct PaletteHeaderAccessory {
    enum Placement { case afterQuery, besideSearchField }
    let width: CGFloat
    let fieldNames: [String]
    let firstIncompleteField: String?
    let optionsMenu: (String) -> PopoverMenuContent?
    let placement: Placement
    let view: AnyView
}

struct PopoverMenuContent { let header: String; let items: [PopoverMenuItem] }
struct PopoverMenuItem {
    enum Icon { case symbol(String), blank }
    let title: String
    let icon: Icon
    let action: () -> Void
}
