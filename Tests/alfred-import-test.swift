// Standalone contract tests for the Alfred import: the real reader and its pure mappers.
// The package is built here rather than committed, the way raycast-test builds its own container.

import Foundation

@main
@MainActor
struct AlfredImportTests {
    static var failures = 0
    static var passes = 0

    static func main() throws {
        let package = try Fixture.build()
        defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }

        check("a package folder is recognised", AlfredPreferencesReader.isPackage(package))
        check(
            "a folder that is not one is not",
            !AlfredPreferencesReader.isPackage(package.deletingLastPathComponent()))
        check(
            "a file is not a package",
            !AlfredPreferencesReader.isPackage(
                package.appendingPathComponent("preferences/prefs.plist")))

        try testHotkeys(package: package)
        try testSearchScope(package: package)
        try testSnippets(package: package)
        try testQuicklinks(package: package)
        try testWorkflows(package: package)
        try testSelection(package: package)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Hotkeys

    private static func testHotkeys(package: URL) throws {
        let chord = KeyShortcut(carbonKeyCode: 49, carbonModifiers: 256 + 4096)
        check(
            "Alfred's ⌃⌘Space maps to our chord",
            AlfredHotkeyImport.binding(["key": 49, "mod": 1_310_720]) == .combo(chord))
        check(
            "⌃⌘ reads as control and command, nothing else",
            AlfredHotkeyImport.binding(["key": 49, "mod": 1_310_720])?.shortcut?.modifierFlags
                == [.control, .command])
        check(
            "Alfred's unset chord is no binding",
            AlfredHotkeyImport.binding(["key": -1, "mod": -1]) == nil)
        check(
            "a bare key needs a commanding modifier here too",
            AlfredHotkeyImport.binding(["key": 0, "mod": 0]) == nil)
        check("a function key needs none", AlfredHotkeyImport.binding(["key": 105, "mod": 0]) != nil)
        check("a missing key code is no binding", AlfredHotkeyImport.binding(["mod": 1_310_720]) == nil)

        let result = try AlfredPreferencesReader.read(package: package)
        check("the newest local profile supplies the palette chord", result.paletteHotkey == .combo(chord))
        check(
            "the globally stored clipboard chord comes over",
            result.clipboardHotkey == .combo(KeyShortcut(carbonKeyCode: 9, carbonModifiers: 256 + 4096)))
    }

    // MARK: - Search scope

    private static func testSearchScope(package: URL) throws {
        let result = try AlfredPreferencesReader.read(package: package)
        check(
            "the newest profile's scope wins, abbreviated and deduped",
            result.searchScopes == ["/Applications", "~/Developer/Applications", "/opt/homebrew/bin"])
    }

    // MARK: - Snippets

    private static func testSnippets(package: URL) throws {
        let result = try AlfredPreferencesReader.read(package: package)
        check("both collections come over", result.snippets.count == 2)
        check(
            "collections and files are read in a stable order",
            result.snippets.map(\.name) == ["Alpha", "Zulu"])
        check(
            "each collection's own affixes are applied, and the workflow trigger's are not",
            result.snippets.map(\.keyword) == ["!sig", "sigz"])

        let context = SnippetTemplateEngine.ExpansionContext(
            clipboard: "clipped", selection: "", now: Date(timeIntervalSince1970: 0),
            calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current, makeUUID: { "uuid" })
        let alpha = SnippetTemplateEngine.expand(text: result.snippets[0].text, context: context)
        check(
            "a rewritten Alfred date placeholder is one the engine expands",
            alpha.text == "Built 1970-01-01")
        let zulu = SnippetTemplateEngine.expand(text: result.snippets[1].text, context: context)
        check(
            "an Alfred clipboard modifier survives the rewrite",
            zulu.text == "Signed CLIPPED")
    }

    // MARK: - Quicklinks

    private static func testQuicklinks(package: URL) throws {
        let result = try AlfredPreferencesReader.read(package: package)
        check("bookmarks, custom searches and defaults all come over", result.quicklinks.count == 4)
        check(
            "an openurl bookmark lands and a launchfile one does not",
            result.quicklinks[0].link == "https://example.com/welcome")
        check(
            "an empty bookmark label falls back to the host",
            result.quicklinks[0].name == "example.com")
        check(
            "a custom search keeps its title and gains a keyword",
            result.quicklinks[1].name == "GitHub" && result.quicklinks[1].keyword == "gh")
        check(
            "the query token is rewritten to ours",
            result.quicklinks[1].link == "https://github.com/search?q={argument}")
        check(
            "a default search lands with its own name and keyword",
            result.quicklinks[2].name == "Google" && result.quicklinks[2].keyword == "g")
        check(
            "a keyword the title does not contain lives in the keyword field",
            result.quicklinks[3].name == "Google Images" && result.quicklinks[3].keyword == "gi")
        check(
            "a disabled custom search is not carried over",
            !result.quicklinks.contains { $0.link.contains("example.com/never") })
        check("a search folder with no template is reported", result.skippedSearches == ["tiktok"])
    }

    // MARK: - Workflows

    private static func testWorkflows(package: URL) throws {
        let result = try AlfredPreferencesReader.read(package: package)
        check("only the convertible workflows come over", result.commands.count == 3)
        check(
            "a quoted {query}, two triggers, another interpreter and a disabled one are left out",
            result.skippedWorkflows == 4)

        let query = result.commands.first { $0.command.name == "Copy (cp)" }
        check("a keyword lands in the name", query != nil)
        check(
            "an unquoted {query} becomes the command's own argument",
            query?.command.command == "echo \"${1}\"")
        check(
            "a trigger that takes input declares the argument",
            query?.command.arguments.map(\.name) == ["argument"])
        check(
            "a keyword that takes none declares none",
            result.commands.first { $0.command.name == "No Input (ni)" }?
                .command.arguments.isEmpty == true)
        check("no chord means no binding", query?.hotkey == nil)

        let sorted = result.commands.first { $0.command.name == "Sort Lines" }
        check("a workflow with no keyword keeps its own name", sorted != nil)
        check("an argv script is untouched", sorted?.command.command == "sort \"${1}\"")
        let chord = KeyShortcut(carbonKeyCode: 1, carbonModifiers: 256 + 2048 + 4096)
        check("the workflow's hotkey becomes the command's chord", sorted?.hotkey == .combo(chord))
        check("an output window is what Alfred always opened", sorted?.command.showsOutput == true)
    }

    // MARK: - Category trimming

    private static func testSelection(package: URL) throws {
        let result = try AlfredPreferencesReader.read(package: package)
        let snippetsOnly = result.selecting([.snippets])
        check("snippets survive", snippetsOnly.snippets.count == 2)
        check("quicklinks are dropped", snippetsOnly.quicklinks.isEmpty)
        check("commands are dropped", snippetsOnly.commands.isEmpty)
        check("the chords are dropped", snippetsOnly.paletteHotkey == nil)
        check("the scope is dropped", snippetsOnly.searchScopes == nil)
        check(
            "the note about what was skipped goes with its category",
            snippetsOnly.skippedSearches.isEmpty && snippetsOnly.skippedWorkflows == 0)

        let linksOnly = result.selecting([.quicklinks])
        check("the skipped-search note rides with quicklinks", linksOnly.skippedSearches == ["tiktok"])
        check("the skipped-workflow note does not", linksOnly.skippedWorkflows == 0)
    }

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
            passes += 1
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}

/// The package every case above reads, built fresh so no real Alfred data is ever committed.
enum Fixture {
    private static let stale = Date(timeIntervalSinceNow: -86_400)

    static func build() throws -> URL {
        let package = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alfred-\(UUID().uuidString)/Alfred.alfredpreferences")
        try write(["location": "Germany"], at: package, "preferences/prefs.plist")
        try write(
            ["hotkey": ["key": 9, "mod": 1_310_720, "string": "V"]],
            at: package, "preferences/features/clipboard/prefs.plist")
        // Alfred's own snippet *trigger*, not a collection: it must not reach a keyword.
        try write(
            ["keywordPrefix": "!!"], at: package, "preferences/workflows/trigger/snippet/prefs.plist")
        try write(
            [
                "customSites": [
                    "A": [
                        "enabled": true, "keyword": "gh", "text": "GitHub",
                        "url": "https://github.com/search?q={query}"
                    ],
                    "B": [
                        "enabled": false, "keyword": "no", "text": "Never",
                        "url": "https://example.com/never"
                    ]
                ]
            ],
            at: package, "preferences/features/websearch/prefs.plist")
        try write(["keyword": "g"], at: package, "preferences/features/websearch/google/prefs.plist")
        try write(["keyword": "gi"], at: package, "preferences/features/websearch/images/prefs.plist")
        try write(["keyword": "tt"], at: package, "preferences/features/websearch/tiktok/prefs.plist")

        // Two machines' profiles: the stale one dated back, so the newest is this Mac's.
        try write(
            ["default": ["key": 49, "mod": 1_310_720]],
            at: package, "preferences/local/stale/hotkey/prefs.plist", stale)
        try write(
            ["scope": ["/Applications", "/usr/bin"]],
            at: package, "preferences/local/stale/features/defaultresults/prefs.plist", stale)
        try write(
            ["default": ["key": 49, "mod": 1_310_720]],
            at: package, "preferences/local/current/hotkey/prefs.plist")
        try write(
            ["scope": ["/Applications/", "~/Developer/Applications", "/opt/homebrew/bin"]],
            at: package, "preferences/local/current/features/defaultresults/prefs.plist")

        try write(["pages": ["PAGE"], "uid": "INDEX"], at: package, "remote/pages/pages.data")
        try write(
            [
                "title": "Bookmarks",
                "items": [
                    [
                        "actionuid": "remote.alfred.openurl",
                        "actionconfig": ["url": "https://example.com/welcome"],
                        "buttonlabel": "", "itemuid": "1"
                    ],
                    [
                        "actionuid": "remote.alfred.launchfile",
                        "actionconfig": ["path": "/Applications"],
                        "buttonlabel": "Applications", "itemuid": "2"
                    ]
                ]
            ],
            at: package, "remote/pages/PAGE.data")

        try write(["snippetkeywordsuffix": "z"], at: package, "snippets/productivity/info.plist")
        try write(
            ["snippetkeywordprefix": "!"], at: package, "snippets/Coding/info.plist")
        try writeSnippet(
            "Alpha", "Built {date:yyyy-MM-dd}", "sig", at: package, "snippets/Coding")
        try writeSnippet(
            "Zulu", "Signed {clipboard:uppercase}", "sig", at: package, "snippets/productivity")

        try writeWorkflow(
            package: package, name: "Copy", keyword: "cp", script: "echo {query}", argumentType: 0)
        try writeWorkflow(
            package: package, name: "No Input", keyword: "ni", script: "echo hi", argumentType: 2)
        try writeWorkflow(
            package: package, name: "Quoted", keyword: "q", script: "echo \"{query}\"")
        try writeWorkflow(
            package: package, name: "Sort Lines", script: "sort \"${1}\"", scriptArgument: 1,
            argumentType: 1, hotkey: ["hotkey": 1, "hotmod": 1_835_008])
        try writeWorkflow(
            package: package, name: "Two Triggers", keyword: "tt", script: "echo {query}",
            extraTrigger: true)
        try writeWorkflow(
            package: package, name: "Ruby", keyword: "rb", script: "puts 1", interpreter: 5)
        try writeWorkflow(
            package: package, name: "Disabled", keyword: "off", script: "echo {query}", disabled: true)
        return package
    }

    private static func write(_ plist: [String: Any], at package: URL, _ path: String) throws {
        try write(plist, at: package, path, nil)
    }

    private static func write(_ plist: [String: Any], at package: URL, _ path: String, _ modified: Date?)
        throws
    {
        let url = package.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    private static func writeSnippet(
        _ name: String, _ text: String, _ keyword: String, at package: URL, _ folder: String
    ) throws
    {
        let stored: [String: Any] = [
            "alfredsnippet": ["snippet": text, "uid": keyword, "name": name, "keyword": keyword]
        ]
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent(folder), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: stored)
        try data.write(to: package.appendingPathComponent("\(folder)/\(name) [\(keyword)].json"))
    }

    private static func writeWorkflow(
        package: URL, name: String, keyword: String? = nil, script: String, scriptArgument: Int = 0,
        argumentType: Int = 0, interpreter: Int = 0, hotkey: [String: Any]? = nil,
        extraTrigger: Bool = false, disabled: Bool = false
    ) throws {
        let uid = "W-\(name)"
        var objects: [[String: Any]] = [
            [
                "uid": "\(uid)-SCRIPT", "type": "alfred.workflow.action.script",
                "config": [
                    "type": interpreter, "script": script, "scriptfile": "",
                    "scriptargtype": scriptArgument
                ]
            ]
        ]
        var connections: [String: [[String: Any]]] = [:]
        func addTrigger(_ id: String, _ config: [String: Any]) {
            objects.append(["uid": id, "type": "alfred.workflow.input.keyword", "config": config])
            connections[id] = [["destinationuid": "\(uid)-SCRIPT"]]
        }
        if let keyword {
            addTrigger("\(uid)-TRIGGER", ["keyword": keyword, "argumenttype": argumentType])
        } else if let hotkey {
            var config = hotkey
            config["argument"] = argumentType
            objects.append([
                "uid": "\(uid)-TRIGGER", "type": "alfred.workflow.trigger.hotkey", "config": config
            ])
            connections["\(uid)-TRIGGER"] = [["destinationuid": "\(uid)-SCRIPT"]]
        }
        if extraTrigger {
            addTrigger("\(uid)-SECOND", ["keyword": "other", "argumenttype": 0])
        }
        try write(
            [
                "name": name, "bundleid": "", "objects": objects, "connections": connections,
                "disabled": disabled
            ],
            at: package, "workflows/user.workflow.\(uid)/info.plist")
    }
}
