import AppKit
import Observation

@main
@MainActor
struct AppInstallationTests {
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
            testFileFavorites(root)
            try await testLanguageOverride(root)
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
        let favorites = FavoritesStore(defaults: defaults)
        favorites.replace(keys: [id])
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
        favorites.replace(keys: [])
        ranking.visit(itemKey: id, query: nil)
        let unpinned = index.orderedResults(
            query: "", visibility: visibility, favorites: favorites, hotKeys: hotKeys)
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

    private static func testFileFavorites(_ root: URL) {
        let domain = "tinycast.file-favorites-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = FavoritesStore(defaults: defaults)
        let app = AppEntry(
            id: root.appending(path: "Fixture.app").path, name: "Fixture",
            url: root.appending(path: "Fixture.app"), bundleID: "com.example.fixture", kind: .application)
        let folder = FileSearchResult(
            url: root.appending(path: "Projects"), isDirectory: true, homeDirectory: root)
        let file = FileSearchResult(
            url: root.appending(path: "Résumé #1? 100%.txt"), isDirectory: false, homeDirectory: root)
        store.toggle(folder)
        store.toggle(app)
        store.toggle(file)
        check("files and folders become favorites", store.isFavorite(folder) && store.isFavorite(file))
        check("app favorites retain bundle identity", store.keys[1] == app.bundleID)
        check(
            "mixed favorites retain insertion order",
            store.orderedItems(entries: [app], files: [file, folder]).map(\.key)
                == [folder.favoriteKey, app.preferenceKey, file.favoriteKey])
        check(
            "file rows cannot collide with an application's path identity",
            FavoritesStore.Item.file(folder).id != folder.id)
        check(
            "relaunch restores file paths and directory hints without requiring the index",
            FavoritesStore(defaults: defaults).files(homeDirectory: root).map(\.favoriteKey)
                == [folder.favoriteKey, file.favoriteKey])
        store.replace(keys: [folder.favoriteKey, "unavailable-app", app.preferenceKey, file.favoriteKey])
        store.exchange(folder.favoriteKey, with: app.preferenceKey)
        check(
            "reordering mixed favorites preserves hidden slots",
            store.keys == [app.preferenceKey, "unavailable-app", folder.favoriteKey, file.favoriteKey])
        check(
            "hidden apps and disabled file search leave no visible favorite rows",
            store.orderedItems(entries: [], files: []).isEmpty && store.keys.count == 4)
        let restored = FavoritesStore(defaults: defaults)
        restored.replace(keys: store.keys)
        check(
            "the existing backup key list restores the mixed order",
            restored.orderedItems(entries: [app], files: restored.files(homeDirectory: root)).map(\.key)
                == [app.preferenceKey, folder.favoriteKey, file.favoriteKey])
        check(
            "app-only ordering excludes file favorites",
            restored.ordered([app]).favorites == [app] && restored.ordered([app]).rest.isEmpty)
        restored.toggle(folder)
        check(
            "removing a folder leaves other favorites intact",
            !restored.isFavorite(folder) && restored.isFavorite(file) && restored.isFavorite(app))
        restored.remove(keys: [file.favoriteKey])
        check("file favorites support removal by key", !restored.isFavorite(file))
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

    private static func runProgram(_ executable: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

// Empty feature catalogs keep this harness focused on the shipped launcher.
enum SettingsTab: Sendable {
    case ai, quickActions, windowManagement, quicklinks, snippets, commands, calendar
    var tint: IconTint { .gray }
}
enum ExtensionRefreshState: Hashable, Sendable { case idle }
enum EntryIcon: Hashable, Sendable {
    case file(stamp: Int), symbol(String), tile(symbol: String, tint: IconTint)
}
enum IconCache {
    static func observeStyle() {}
    static func icon(for source: EntryIcon, fileURL: URL) -> NSImage { NSImage() }
}
enum CommandID: String, Sendable {
    case fixture
    var sfSymbol: String { "" }
    var tint: IconTint { .gray }
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
    init?(entryID: String) { nil }
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
    var tint = IconTint.gray
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
