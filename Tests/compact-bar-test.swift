import Foundation

extension CommandID: SettingsFileRawValue {}

@main
@MainActor
struct CompactBarTests {
    private static var failures = 0

    private static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() throws {
        let defaults = CommandID.defaultCompactBarCommands
        check(
            defaults == [.clipboardHistory, .searchFiles, .searchSnippets, .searchQuicklinks],
            "the existing four commands remain the default")
        check(CommandID.compactBarOptions.count == 8, "eight supported destinations")
        for count in 0...CommandID.compactBarLimit {
            let commands = Array(defaults.prefix(count))
            var selection = CompactBarSelection()
            selection.move(by: -1, commands: commands)
            check(selection.command == nil, "Left stops at Search with \(count) slots")
            for command in commands {
                selection.move(by: 1, commands: commands)
                check(selection.command == command, "Right follows configured order")
            }
            selection.move(by: 1, commands: commands)
            check(selection.command == commands.last, "Right stops at the last visible slot")
            for _ in commands { selection.move(by: -1, commands: commands) }
            check(selection.command == nil, "Left returns to Search")
        }

        var selection = CompactBarSelection(command: .searchFiles)
        selection.reconcile(commands: [.searchFiles, .clipboardHistory])
        check(selection.command == .searchFiles, "reordering preserves the selected command")
        selection.reconcile(commands: [.clipboardHistory])
        check(selection.command == nil, "removing or disabling the selected command returns to Search")
        selection.command = .showNotes
        selection.move(by: 1, commands: defaults)
        check(selection.command == defaults.first, "an obsolete selection starts from Search")

        check(CommandID.compactBarCommands(from: []) == [], "empty means no shortcuts")
        let chosen: [CommandID] = [.quickAI, .searchEmoji, .mySchedule, .showNotes]
        check(
            CommandID.compactBarCommands(from: chosen.map(\.rawValue)) == chosen,
            "all additional destinations retain their order")
        for invalid in [
            ["unknown"], [CommandID.quit.rawValue],
            [CommandID.searchFiles.rawValue, CommandID.searchFiles.rawValue],
            Array(CommandID.compactBarOptions.prefix(5)).map(\.rawValue)
        ] {
            check(
                CommandID.compactBarCommands(from: invalid) == nil,
                "invalid command lists are rejected whole")
        }

        let suite = "compact-bar-test.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let key = AppSettingsKey.compactBarCommands.rawValue
        check(
            preferences.stringArray(forKey: key).flatMap(CommandID.compactBarCommands(from:))
                ?? defaults == defaults, "missing preferences use defaults")
        preferences.set(chosen.map(\.rawValue), forKey: key)
        check(
            preferences.stringArray(forKey: key).flatMap(CommandID.compactBarCommands(from:)) == chosen,
            "stable identifiers round trip through isolated preferences")
        preferences.set([], forKey: key)
        check(
            preferences.stringArray(forKey: key).flatMap(CommandID.compactBarCommands(from:)) == [],
            "an explicitly empty preference stays empty")

        let state = Commands()
        let binding = SettingsFileBinding(.compactBarCommands, state, \.value) {
            CommandID.validCompactBarCommands($0) ? $0 : nil
        }
        check(
            binding.write(chosen.settingsJSON).isEmpty && state.value == chosen,
            "settings binding accepts the configured order")
        let encoded = SettingsFileFormat.render([.compactBarCommands: binding.read()])
        let decoded = try SettingsFileFormat.parse(encoded)
        check(
            decoded.values[.compactBarCommands] == chosen.settingsJSON,
            "settings JSON round trip retains identifiers")
        for invalid: SettingsFileJSON in [
            .array([.string("unknown")]), .array([.string(CommandID.quit.rawValue)]),
            .array([.string(CommandID.quickAI.rawValue), .string(CommandID.quickAI.rawValue)]),
            Array(CommandID.compactBarOptions.prefix(5)).settingsJSON, .bool(false)
        ] {
            check(
                !binding.write(invalid).isEmpty && state.value == chosen,
                "invalid settings leave the current configuration intact")
        }
        check(
            binding.write(.array([])).isEmpty && state.value.isEmpty,
            "settings binding accepts zero shortcuts")
        print("Compact bar tests: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }

    private final class Commands {
        var value = CommandID.defaultCompactBarCommands
    }
}
