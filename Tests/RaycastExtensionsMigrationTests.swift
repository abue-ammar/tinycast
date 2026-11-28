import Foundation

@main
struct RaycastExtensionsMigrationTests {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        let suite = "tinycast.raycast-extensions-migration-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let retired = [
            "extensionsShowInLauncher", "extensionPackageManager",
            "extensionCustomSearchPaths",
            "extensionAppearances", "boundExtensionCommandEntryIDs",
            "hotkey.extensionCommand.extension:weather/forecast",
            "NSStatusItem Visible extension:weather/temperature",
            "NSStatusItem Preferred Position extension:weather/temperature"
        ]
        let kept = [
            "hotkey.quicklink.1", "NSStatusItem Visible Item-0", "launcherAliases", "extensionsEnabled",
            "boundExtensionCommandIDs", "hotkey.extensionCommand.hello/greet"
        ]
        for key in retired + kept { defaults.set(true, forKey: key) }

        let root = FileManager.default.temporaryDirectory
            .appending(path: "raycast-extensions-migration-\(UUID())", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(
            at: root.appending(path: "extensions/weather"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: root.appending(path: "extension-data"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: root.appending(path: "CloudSync"), withIntermediateDirectories: true)
        for file in ["extension-commands.json", "extension-versions.json", "notes.json"] {
            try? Data("{}".utf8).write(to: root.appending(path: file))
        }

        let settingsFile = root.appending(path: "settings.json")
        try? Data(
            #"{"quicklinks": {"enabled": false}, "extensions": {"enabled": true, "showInLauncher": true}}"#
                .utf8
        ).write(to: settingsFile)

        RaycastExtensionsMigration.run(
            defaults: defaults, supportDirectory: root, settingsFile: settingsFile)
        check("every retired default is gone", retired.allSatisfy { defaults.object(forKey: $0) == nil })
        check("every unrelated key stays", kept.allSatisfy { defaults.object(forKey: $0) != nil })
        let rewritten = (try? Data(contentsOf: settingsFile)).flatMap { try? SettingsFileFormat.parse($0) }
        check(
            "settings.json loses the retired key and keeps the rest, native extensions' switch too",
            rewritten?.issues == []
                && rewritten?.values == [.quicklinksEnabled: .bool(false), .extensionsEnabled: .bool(true)])
        check(
            "a settings.json with other problems is left to the import",
            RaycastExtensionsMigration.strippingRetiredKey(
                Data(#"{"extensions": {"showInLauncher": true}, "bogus": {}}"#.utf8)) == nil)
        check(
            "a settings.json without the retired key is left as written",
            RaycastExtensionsMigration.strippingRetiredKey(
                Data(#"{"quicklinks": {"enabled": false}, "extensions": {"enabled": true}}"#.utf8)) == nil)

        func left() -> Set<String> {
            Set((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
        }
        RaycastExtensionsMigration.removeFiles(in: root)
        let others: Set<String> = ["CloudSync", "notes.json", "settings.json"]
        check("only the runtime's own files are removed", left() == others)
        RaycastExtensionsMigration.removeFiles(in: root)
        check("a second run changes nothing", left() == others)

        check(
            "only the runtime's launcher keys are retired, never a native command's",
            RaycastExtensionsMigration.retiredEntries(
                in: [
                    "extension:weather/forecast", "/Applications/Safari.app", "extension-command:hello/greet"
                ],
                ["quicklink:1", "extension:weather/forecast", "extension:notes/new"])
                == ["extension:weather/forecast", "extension:notes/new"])
        check(
            "its synced aliases and chords are retired, a native command's stay",
            RaycastExtensionsMigration.isRetiredEntry(.launcherShortcuts, key: "extension:weather/forecast")
                && !RaycastExtensionsMigration.isRetiredEntry(
                    .launcherShortcuts, key: "extension-command:hello/greet")
                && !RaycastExtensionsMigration.isRetiredEntry(.notes, key: "extension:weather/forecast"))
        check(
            "the runtime's synced records are retired",
            RaycastExtensionsMigration.isRetiredRecord("extensions.0a1b2c"))
        check(
            "and so is its Show in launcher setting",
            RaycastExtensionsMigration.isRetiredRecord(
                SyncSourceID.settings.recordName(for: "extensions.showInLauncher")))
        check(
            "every other record stays",
            !RaycastExtensionsMigration.isRetiredRecord("notes.0a1b2c")
                && !RaycastExtensionsMigration.isRetiredRecord("launcherShortcuts.0a1b2c")
                && !RaycastExtensionsMigration.isRetiredRecord(
                    SyncSourceID.settings.recordName(for: "quicklinks.enabled"))
        )

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
