import AppKit
import Observation
import Synchronization

private let receivedWorkspaceLaunch = Mutex(false)

@main
@MainActor
struct AppInstallationTest {
    private static var failures = 0

    static func main() {
        Task {
            do {
                try await runTests()
                exit(failures == 0 ? 0 : 1)
            } catch {
                print("FAIL: \(error)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }

    private static func runTests() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-installations-\(UUID())").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if let argument = CommandLine.arguments.firstIndex(of: "--localized-index") {
            try await testLocalizedIndex(root, language: CommandLine.arguments[argument + 1])
        } else {
            try await testIndex(root)
            try await testLanguageOverride(root)
            if ProcessInfo.processInfo.environment["TINYCAST_TEST_APP_LAUNCH"] == "1"
                || CommandLine.arguments.contains("--launch")
            {
                try await testLaunch(root)
            }
        }
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
    }

    private static func check(_ name: String, _ condition: Bool) {
        if !condition { failures += 1; print("FAIL: \(name)") }
    }

    private static func makeApp(_ url: URL, id: String, version: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": id, "CFBundleShortVersionString": version,
            "CFBundleVersion": "1", "CFBundleName": url.deletingPathExtension().lastPathComponent,
            "CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture", "LSUIElement": true,
            "NSPrincipalClass": "NSApplication"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }

    private static func testIndex(_ root: URL) async throws {
        let id = "com.example.android-studio"
        let stable = root.appendingPathComponent("Stable/Android Studio.app", isDirectory: true)
        let old = root.appendingPathComponent("Old/Android Studio.app", isDirectory: true)
        let backup = root.appendingPathComponent("Backup/Android Studio.app", isDirectory: true)
        let preview = root.appendingPathComponent("Beta/Android Studio Preview.app", isDirectory: true)
        let utility = root.appendingPathComponent("Utility.app", isDirectory: true)
        for (url, version) in [(stable, "2026.1"), (old, "2025.2"), (backup, "2026.1"), (preview, "2026.2")] {
            try makeApp(url, id: id, version: version)
        }
        try makeApp(utility, id: "com.example.utility", version: "1.0")
        let alias = root.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: stable)
        let domain = "tinycast.installation-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let aliases = AliasStore(defaults: defaults)
        let visibility = VisibilityStore(defaults: defaults)
        let ranking = LauncherRankingStore(fileURL: root.appendingPathComponent("ranking.json"))
        let settings = AppSettings()
        settings.searchScopes = [stable.path, root.path]
        let index = AppIndex(ranking: ranking, aliases: aliases)
        index.start(settings: settings)
        await index.refresh()
        let hotKeys = HotKeyManager()
        UserDefaults.standard.setVolatileDomain(["favoriteApps": [id]], forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
        let favorites = FavoritesStore()
        func results(_ query: String) -> AppIndex.Results {
            index.orderedResults(query: query, visibility: visibility, favorites: favorites, hotKeys: hotKeys)
        }
        let copies = results("Android Studio").entries.filter { $0.bundleID == id }
        check("all four installations survive indexing", copies.count == 4)
        check(
            "overlapping scopes and symlinks do not duplicate an installation",
            Set(copies.map(\.id)).count == 4)
        check(
            "app-wide settings retain one representative", index.apps.filter { $0.bundleID == id }.count == 1)
        check(
            "scope priority retains the existing representative",
            index.apps.first { $0.bundleID == id }?.url == stable)
        check("each row retains its own launch URL", Set(copies.map(\.url)) == [stable, old, backup, preview])
        check(
            "same-version copies show their distinct folders",
            copies.first { $0.url == stable }?.subtitle?.contains("Stable") == true)
        check(
            "the second same-version copy shows its folder",
            copies.first { $0.url == backup }?.subtitle?.contains("Backup") == true)
        check("a distinct version needs no path label", copies.first { $0.url == old }?.subtitle == "2025.2")
        check(
            "preview keeps its own name", copies.first { $0.url == preview }?.name == "Android Studio Preview"
        )
        check(
            "single installations keep their existing appearance",
            index.apps.first { $0.url == utility }?.subtitle == nil)
        check(
            "version metadata is searchable",
            results("Android Studio 2025.2").entries.contains { $0.url == old })
        check(
            "searching Preview selects Preview",
            results("Android Studio Preview").entries.first?.url == preview)
        check(
            "settings search does not expose duplicate controls",
            index.matches("Android Studio").filter { $0.bundleID == id }.count == 1)
        check(
            "a version name still finds its app-wide settings",
            index.matches("Android Studio Preview").first?.url == stable)
        let empty = results("")
        check(
            "an existing favorite retains the representative",
            empty.entries.first?.url == stable && empty.favoriteCount == 1)
        check(
            "favoriting the app does not hide its other copies",
            empty.entries.filter { $0.bundleID == id }.count == 4)
        UserDefaults.standard.setVolatileDomain(["favoriteApps": []], forName: UserDefaults.argumentDomain)
        ranking.visit(itemKey: id, query: nil)
        let unpinned = index.orderedResults(
            query: "", visibility: visibility, favorites: FavoritesStore(), hotKeys: hotKeys)
        check(
            "Suggestions contain one representative per app",
            unpinned.entries.prefix(unpinned.suggestionCount).filter { $0.bundleID == id }.map(\.url) == [
                stable
            ])
        aliases.setAlias("ide", for: id)
        check("aliases remain app-wide", results("ide").entries.filter { $0.bundleID == id }.count == 4)
        visibility.setItemVisible(false, forKey: id)
        check(
            "visibility remains app-wide", results("Android Studio").entries.allSatisfy { $0.bundleID != id })
        visibility.setItemVisible(true, forKey: id)
        for url in [old, backup, preview] { try FileManager.default.removeItem(at: url) }
        await index.refresh()
        check(
            "removing duplicate installations invalidates search results",
            results("Android Studio").entries.filter { $0.bundleID == id }.count == 1)
        check(
            "the last installation no longer needs a version label",
            index.apps.first { $0.bundleID == id }?.subtitle == nil)
        check(
            "the last installation regains single-app actions",
            index.apps.first { $0.bundleID == id }?.primaryInstallationID == nil)
        await ranking.flush()
    }

    private static func testLanguageOverride(_ root: URL) async throws {
        let system = Set(
            SystemLanguages.preferred.compactMap { $0.split(separator: "-").first.map(String.init) })
        guard
            let language = ["ru", "ja", "ko", "de", "fr", "es", "pt", "it", "nl", "sv"]
                .first(where: { !system.contains($0) }),
            let executable = Bundle.main.executableURL
        else { throw CocoaError(.fileReadCorruptFile) }
        let app = root.appendingPathComponent("LanguageProbe.app", isDirectory: true)
        try makeApp(app, id: "com.tinycast.language-probe.\(UUID())", version: "1.0")
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard
            var info = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        info["CFBundleDevelopmentRegion"] = "en"
        info["CFBundleLocalizations"] = ["en", language]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
            to: infoURL)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let probe = macOS.appendingPathComponent("Fixture")
        try FileManager.default.copyItem(at: executable, to: probe)
        check(
            "app language does not change installed-app names or search terms",
            try await runProgram(
                probe.path, ["--localized-index", language, "-AppleLanguages", "(\(language))"]) == 0)
    }

    private static func testLocalizedIndex(_ root: URL, language: String) async throws {
        check(
            "the probe runs in its requested language", Bundle.main.preferredLocalizations.first == language)
        let app = root.appendingPathComponent("Localized.app", isDirectory: true)
        let id = "com.tinycast.localized-fixture.\(UUID())"
        try makeApp(app, id: id, version: "1.0")
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard
            var info = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        info["CFBundleDevelopmentRegion"] = "en"
        info["CFBundleDisplayName"] = "DeclaredFixtureName"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
            to: infoURL)
        for (code, name) in [("en", "SystemLanguageFixture"), (language, "InterfaceOnlyFixture")] {
            let folder = app.appendingPathComponent("Contents/Resources/\(code).lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleDisplayName": name], format: .xml, options: 0
            )
            .write(to: folder.appendingPathComponent("InfoPlist.strings"))
        }
        check(
            "the fixture exposes an interface-localized declaration",
            Bundle(url: app)?.installedAppName == "InterfaceOnlyFixture")
        let domain = "tinycast.language-index-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let aliases = AliasStore(defaults: defaults)
        let visibility = VisibilityStore(defaults: defaults)
        let ranking = LauncherRankingStore(fileURL: root.appendingPathComponent("ranking.json"))
        let settings = AppSettings()
        settings.searchScopes = [app.path]
        let index = AppIndex(ranking: ranking, aliases: aliases)
        index.start(settings: settings)
        await index.refresh()
        check("app names follow macOS languages", index.apps.first?.name == "SystemLanguageFixture")
        check(
            "the original declaration remains indexed", index.apps.first?.keywords == ["DeclaredFixtureName"])
        let favorites = FavoritesStore()
        let hotKeys = HotKeyManager()
        func results(_ query: String) -> [AppEntry] {
            index.orderedResults(
                query: query, visibility: visibility, favorites: favorites, hotKeys: hotKeys
            ).entries
        }
        check(
            "the original declaration remains searchable",
            results("DeclaredFixtureName").contains { $0.bundleID == id })
        check(
            "system-language names remain searchable",
            results("SystemLanguageFixture").contains { $0.bundleID == id })
        check(
            "interface-only names stay out of search",
            !results("InterfaceOnlyFixture").contains { $0.bundleID == id })
        await ranking.flush()
    }

    private static func testLaunch(_ root: URL) async throws {
        let id = "com.tinycast.installation-fixture.\(UUID().uuidString.lowercased())"
        let first = root.appendingPathComponent("First.app", isDirectory: true)
        let second = root.appendingPathComponent("Second.app", isDirectory: true)
        let source = root.appendingPathComponent("Fixture.swift")
        let executable = root.appendingPathComponent("Fixture")
        try """
        import AppKit

        final class Delegate: NSObject, NSApplicationDelegate {
            func applicationDidFinishLaunching(_ notification: Notification) {
                let bundle = Bundle.main.bundleURL
                let marker = bundle.deletingLastPathComponent()
                    .appendingPathComponent(bundle.lastPathComponent + ".ready")
                try! Data().write(to: marker)
            }

            func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
                let bundle = Bundle.main.bundleURL
                let marker = bundle.deletingLastPathComponent()
                    .appendingPathComponent(bundle.lastPathComponent + ".refuse-quit")
                if FileManager.default.fileExists(atPath: marker.path) { return .terminateCancel }
                let delayed = bundle.deletingLastPathComponent()
                    .appendingPathComponent(bundle.lastPathComponent + ".delay-quit")
                if FileManager.default.fileExists(atPath: delayed.path) {
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        let completed = bundle.deletingLastPathComponent()
                            .appendingPathComponent(bundle.lastPathComponent + ".quit-completed")
                        try! Data().write(to: completed)
                        sender.reply(toApplicationShouldTerminate: true)
                    }
                    return .terminateLater
                }
                return .terminateNow
            }

            func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
                let bundle = Bundle.main.bundleURL
                let marker = bundle.deletingLastPathComponent()
                    .appendingPathComponent(bundle.lastPathComponent + ".reopened")
                try! Data().write(to: marker)
                return true
            }
        }

        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        """.write(to: source, atomically: true, encoding: .utf8)
        guard
            try await runProgram(
                "/usr/bin/xcrun", ["swiftc", "-swift-version", "6", source.path, "-o", executable.path]) == 0
        else { throw CocoaError(.fileReadCorruptFile) }
        for url in [first, second] {
            try makeApp(url, id: id, version: "1.0")
            let macOS = url.appendingPathComponent("Contents/MacOS")
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: executable,
                to: macOS.appendingPathComponent("Fixture"))
            guard try await runProgram("/usr/bin/codesign", ["--force", "--sign", "-", url.path]) == 0
            else { throw CocoaError(.fileReadCorruptFile) }
        }
        defer {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) {
                app.forceTerminate()
            }
        }
        func running(_ url: URL) -> NSRunningApplication? {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == url
            }
        }
        let firstEntry = AppEntry(id: first.path, name: "First", url: first, bundleID: id, kind: .application)
        let secondEntry = AppEntry(
            id: second.path, name: "Second", url: second, bundleID: id, kind: .application)
        let center = NSWorkspace.shared.notificationCenter
        receivedWorkspaceLaunch.withLock { $0 = false }
        let observer = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil
        ) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == id
            {
                receivedWorkspaceLaunch.withLock { $0 = true }
            }
        }
        defer { center.removeObserver(observer) }
        AppLauncher.launch(first, allowsRunningApplicationSubstitution: false)
        check("the first selected installation launches", await waitUntil { running(first) != nil })
        check(
            "the first fixture completes AppKit launch",
            await waitUntil {
                FileManager.default.fileExists(atPath: root.appendingPathComponent("First.app.ready").path)
            })
        let receivesEvents = await waitUntil(timeout: .seconds(2)) {
            receivedWorkspaceLaunch.withLock { $0 }
        }
        if !receivesEvents {
            print("SKIP: workspace lifecycle notifications are unavailable in this session")
        }
        let monitor = RunningAppsMonitor()
        check(
            "the running dot belongs to the selected path",
            monitor.isRunning(firstEntry) && !monitor.isRunning(secondEntry))
        AppLauncher.launch(second, allowsRunningApplicationSubstitution: false)
        check(
            "another running version cannot replace the selection", await waitUntil { running(second) != nil }
        )
        check(
            "the second fixture completes AppKit launch",
            await waitUntil {
                FileManager.default.fileExists(atPath: root.appendingPathComponent("Second.app.ready").path)
            })
        if receivesEvents {
            check(
                "the monitor updates even when the bundle-ID set stays unchanged",
                await waitUntil { monitor.isRunning(secondEntry) })
        }
        let bothRunning = RunningAppsMonitor()
        check(
            "running paths distinguish copies with one bundle ID",
            bothRunning.isRunning(firstEntry) && bothRunning.isRunning(secondEntry))
        let secondPID = running(second)?.processIdentifier
        AppLauncher.launch(second, allowsRunningApplicationSubstitution: false)
        try await Task.sleep(for: .milliseconds(300))
        check("reopening reuses the selected installation", running(second)?.processIdentifier == secondPID)
        let delayed = root.appendingPathComponent("Second.app.delay-quit")
        try Data().write(to: delayed)
        check(
            "waiting for an accessory app to quit succeeds",
            await AppLauncher.quitAwaitingExit(bundleID: id, url: second))
        check(
            "the quit wait includes the app's final writes",
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Second.app.quit-completed").path))
        try FileManager.default.removeItem(at: delayed)
        check(
            "waiting for an absent installation succeeds",
            await AppLauncher.quitAwaitingExit(bundleID: id, url: second))
        check(
            "Quit leaves its sibling running",
            await waitUntil { running(second) == nil && running(first) != nil })
        if receivesEvents {
            check(
                "the running dot clears for only the version that quit",
                await waitUntil { !monitor.isRunning(secondEntry) && monitor.isRunning(firstEntry) })
        }
        AppLauncher.launch(second, allowsRunningApplicationSubstitution: false)
        check("the second installation can reopen", await waitUntil { running(second) != nil })
        let siblingPID = running(second)?.processIdentifier
        let restartedPID = running(first)?.processIdentifier
        await AppLauncher.restart(bundleID: id, url: first)
        check(
            "Restart reopens the selected version without workspace notifications",
            await waitUntil {
                running(first).map { $0.processIdentifier != restartedPID } ?? false
            })
        check(
            "Restart leaves the sibling process alone", running(second)?.processIdentifier == siblingPID)
        let canceled = Task { await AppLauncher.restart(bundleID: id, url: second) }
        canceled.cancel()
        await canceled.value
        check("a canceled restart leaves the app running", running(second)?.processIdentifier == siblingPID)
        let refusal = root.appendingPathComponent("Second.app.refuse-quit")
        try Data().write(to: refusal)
        let started = ContinuousClock.now
        check(
            "a refused quit times out without claiming success",
            await !AppLauncher.quitAwaitingExit(bundleID: id, url: second))
        check("a refused quit retains the grace period", ContinuousClock.now - started >= .seconds(5))
        check("a refused quit leaves the app alive", running(second)?.processIdentifier == siblingPID)
        try FileManager.default.removeItem(at: refusal)
        let canceledQuit = Task { await AppLauncher.quitAwaitingExit(bundleID: id, url: second) }
        canceledQuit.cancel()
        check("a canceled quit fails", await !canceledQuit.value)
        try await Task.sleep(for: .milliseconds(300))
        check("a canceled quit leaves the app running", running(second)?.processIdentifier == siblingPID)
        _ = AppLauncher.quit(bundleID: id, url: second, force: true)
        check(
            "Force Quit targets the selected path",
            await waitUntil { running(second) == nil && running(first) != nil })
        let firstPID = running(first)?.processIdentifier
        let reopened = root.appendingPathComponent("First.app.reopened")
        try? FileManager.default.removeItem(at: reopened)
        AppLauncher.launch(second)
        check(
            "ordinary app opens reach a running instance",
            await waitUntil {
                FileManager.default.fileExists(atPath: reopened.path) || running(second) != nil
            })
        check(
            "ordinary app opens allow running-version substitution",
            FileManager.default.fileExists(atPath: reopened.path)
                && running(first)?.processIdentifier == firstPID && running(second) == nil)
        _ = AppLauncher.quit(bundleID: id, url: second, force: true)
        _ = AppLauncher.quit(bundleID: id, url: first, force: true)
        check(
            "fixture processes are cleaned up",
            await waitUntil {
                NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
            })
    }

    private static func runProgram(_ executable: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private static func waitUntil(timeout: Duration = .seconds(8), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}

// Empty feature catalogs keep this harness focused on the shipped launcher.
enum SettingsTab: Sendable { case ai }
enum ExtensionRefreshState: Hashable, Sendable { case idle }
enum EntryIcon: Hashable, Sendable { case file(stamp: Int), symbol(String) }
enum IconCache {
    static func observeStyle() {}
    static func icon(for source: EntryIcon, fileURL: URL) -> NSImage { NSImage() }
}
enum CommandID: String, Sendable {
    case fixture
    var sfSymbol: String { "" }
    var hotKeyAction: HotKeyAction? { nil }
    var isQueryDriven: Bool { false }
    var suggestionPriority: Int? { nil }
    var boostedTerms: Set<String> { [] }
    var owner: SettingsTab? { nil }
}
enum CommandCatalog {
    static let all: [AppEntry] = []
    static func command(for entry: AppEntry) -> CommandID? { nil }
}
enum HotKeyAction: Hashable, Sendable {
    case togglePalette, dictation, command(CommandID)
    case app(bundleID: String), settingsPane(bundleID: String), quickAction(id: UUID)
    case customCommand(id: UUID), systemAction(id: SystemAction.ID), windowCommand(id: WindowCommand.ID)
    case customWindowSize(id: UUID), windowLayout(id: UUID), windowRoom(id: UUID), quicklink(id: UUID)
    case appleShortcut(id: UUID), snippet(id: UUID), extensionCommand(entryID: String)
}
struct OtherEntry<Tag: Sendable>: Sendable {
    var id = UUID()
    var entryID: String { id.uuidString }
    var name = ""
    var iconSymbol: String?
    var isEnabled = true
    var showsInRootSearch = true
    var link = ""
    static var sfSymbol: String { "" }
    static func id(fromEntryID id: String) -> UUID? { nil }
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool { lhs.name < rhs.name }
}
enum LayoutTag: Sendable {}
enum RoomTag: Sendable {}
enum SizeTag: Sendable {}
enum QuickActionTag: Sendable {}
enum CommandTag: Sendable {}
enum QuicklinkTag: Sendable {}
enum ShortcutTag: Sendable {}
typealias WindowLayout = OtherEntry<LayoutTag>
typealias Room = OtherEntry<RoomTag>
typealias CustomWindowSize = OtherEntry<SizeTag>
typealias CustomQuickAction = OtherEntry<QuickActionTag>
typealias CustomCommand = OtherEntry<CommandTag>
typealias Quicklink = OtherEntry<QuicklinkTag>
typealias AppleShortcut = OtherEntry<ShortcutTag>
struct SystemAction: Sendable {
    enum ID: String, Sendable { case fixture }
    var id = ID.fixture
    var entryID = ""
    var name = ""
    var englishName = ""
    var sfSymbol = ""
}
enum SystemActionCatalog {
    static let all: [SystemAction] = []
    static func action(forEntryID id: String) -> SystemAction? { nil }
}
struct WindowCommand: Sendable {
    enum ID: String, Sendable { case fixture }
    var id = ID.fixture
    var entryID = ""
    var name = ""
    var englishName = ""
    var sfSymbol = ""
}
enum WindowCommandCatalog {
    static let all: [WindowCommand] = []
    static func command(forEntryID id: String) -> WindowCommand? { nil }
}
enum QuicklinkDestination {
    static func detect(_ link: String) -> Self? { nil }
    var defaultSymbol: String { "" }
}
struct StoredSnippet {
    struct Snippet { var isEnabled = true; var name = ""; var keyword: String? }
    var snippet = Snippet()
    var entryID = ""
    var fileURL = URL(fileURLWithPath: "/")
    static let sfSymbol = ""
    static func id(fromEntryID id: String) -> UUID? { nil }
}
enum SettingsPaneScanner {
    struct Cache: Sendable {}
    static func scan(languages: [String], cache: Cache?) -> ([AppEntry], Cache?) { ([], nil) }
}
@Observable
final class AppSettings {
    var searchScopes: [String] = []
    var launcherShowsSuggestions = true
    var rootSearchSensitivity = SearchSensitivity.default
}
@MainActor
final class HotKeyManager {
    var revision = 0
    func binding(for action: HotKeyAction) -> Int? { nil }
}
