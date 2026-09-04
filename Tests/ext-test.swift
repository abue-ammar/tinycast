// Compiles the real engine sources against JavaScriptCore; pass a directory to run one.

import AppKit
import Foundation
import SwiftUI

@main
struct ExtensionTests {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let directory = arguments.first {
            await runInstalledExtension(
                directory: URL(fileURLWithPath: directory), command: arguments.dropFirst().first)
        } else {
            await runChecks()
        }
    }

    // MARK: - Harness plumbing

    /// `proc` and `fetch` are the app's real ones; main-actor calls get canned answers.
    @MainActor
    final class StubHost: ExtensionHostAPI {
        var calls: [String] = []
        var toasts: [String] = []
        var huds: [String] = []
        var oauthTokens: [String: String] = [:]
        private let fetcher = ExtensionFetcher()

        func perform(api: String, method: String, arguments: [RenderValue]) async throws -> String {
            calls.append("\(api).\(method)")
            if api == "proc", method == "run" {
                if ProcessInfo.processInfo.environment["EXT_TEST_VERBOSE"] != nil {
                    let spec = arguments.first?.objectValue ?? [:]
                    let args = (spec["args"]?.arrayValue ?? []).compactMap(\.stringValue)
                    print(
                        "  proc.run: \(spec["command"]?.stringValue ?? "?") \(args.joined(separator: " "))"
                            + "  [shell=\(spec["shell"]?.boolValue ?? false) detached=\(spec["detached"]?.boolValue ?? false)]"
                    )
                }
                return ExtensionRuntime.jsonString(
                    from: try await ExtensionAsyncProcess.run(arguments.first))
            }
            if api == "fetch" {
                return ExtensionRuntime.jsonString(from: try await fetcher.request(arguments.first))
            }
            switch "\(api).\(method)" {
            case "feedback.showToast":
                toasts.append(arguments.first?.objectValue?["title"]?.stringValue ?? "")
                return "1"
            case "feedback.showHUD":
                huds.append(arguments.first?.stringValue ?? "")
                return ""
            case "storage.get", "clipboard.readText":
                return #""""#
            case "storage.all":
                return "{}"
            case "system.frontmostApplication":
                return
                    #"{"name":"Finder","path":"/System/Library/CoreServices/Finder.app","bundleId":"com.apple.finder"}"#
            case "system.applications":
                return "[]"
            case "oauth.authorize":
                let state = arguments[safe: 1]?.stringValue ?? ""
                return "{\"authorizationCode\":\"auth_code_swift_test\",\"state\":\"\(state)\"}"
            case "oauth.getTokens":
                let providerId = arguments.first?.stringValue ?? ""
                return oauthTokens[providerId] ?? ""
            case "oauth.setTokens":
                let providerId = arguments.first?.stringValue ?? ""
                let tokens = arguments[safe: 1]?.stringValue ?? ""
                oauthTokens[providerId] = tokens
                return ""
            case "oauth.removeTokens":
                let providerId = arguments.first?.stringValue ?? ""
                oauthTokens.removeValue(forKey: providerId)
                return ""
            default:
                return ""
            }
        }
    }

    @MainActor
    final class Recorder: ExtensionRuntimeDelegate {
        var trees: [RenderTree] = []
        var failures: [String] = []
        var logs: [String] = []
        var finished = false

        func runtime(_ runtime: ExtensionRuntime, session: String, didRender tree: RenderTree) {
            trees.append(tree)
        }
        func runtime(_ runtime: ExtensionRuntime, session: String, didFail message: String) {
            failures.append(message)
        }
        func runtime(_ runtime: ExtensionRuntime, session: String, navigationDepth: Int) {}
        func runtime(_ runtime: ExtensionRuntime, session: String, didFinish: Void) { finished = true }
        func runtime(_ runtime: ExtensionRuntime, log level: String, message: String) {
            logs.append("[\(level)] \(message)")
        }
    }

    /// The generated runtime, found relative to this source file's repository.
    static func runtimeURL() -> URL {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tinycast/Resources/RaycastRuntime.generated.js"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Tinycast/Resources/RaycastRuntime.generated.js")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    @MainActor
    static func makeRuntime() -> (ExtensionRuntime, StubHost, Recorder) {
        let host = StubHost()
        let recorder = Recorder()
        let runtime = ExtensionRuntime(hostAPI: host, runtimeURL: runtimeURL())
        runtime.setDelegate(recorder)
        return (runtime, host, recorder)
    }

    static func launchContext(
        extensionName: String = "fixture", command: String = "fixture",
        mode: ExtensionCommandMode = .view, assets: String = "/tmp",
        preferences: [String: ExtensionPreferenceValue] = [:],
        arguments: [String: String] = [:], isDarkAppearance: Bool = true
    ) -> ExtensionLaunchContext {
        ExtensionLaunchContext(
            extensionName: extensionName, extensionTitle: extensionName, commandName: command,
            commandMode: mode, assetsPath: assets, supportPath: "/tmp",
            preferences: preferences, caches: [:], arguments: arguments, fallbackText: nil,
            isDarkAppearance: isDarkAppearance)
    }

    /// `EXT_TEST_ARGS="hours=0,minutes=5"` — stands in for the palette's inline argument fields.
    static func environmentArguments() -> [String: String] {
        guard let raw = ProcessInfo.processInfo.environment["EXT_TEST_ARGS"] else { return [:] }
        var arguments: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            arguments[String(parts[0])] = String(parts[1])
        }
        return arguments
    }

    /// `EXT_TEST_PREFS` as JSON — strings and bools, what a manifest preference holds.
    static func environmentPreferences() -> [String: ExtensionPreferenceValue] {
        guard let raw = ProcessInfo.processInfo.environment["EXT_TEST_PREFS"],
            let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        else { return [:] }
        return json.compactMapValues { value in
            if let flag = value as? Bool { return .bool(flag) }
            if let text = value as? String { return .string(text) }
            return nil
        }
    }

    /// Let the JS event loop and the main-actor host hops settle.
    static func settle(_ milliseconds: UInt64 = 250) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    // MARK: - Results

    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func check(_ label: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : "\n      \(detail)")")
        }
    }

    // MARK: - Checks

    @MainActor
    static func runChecks() async {
        manifestChecks()
        renderNodeChecks()
        screenChecks()
        actionIconChecks()
        oauthUnitChecks()
        await runtimeChecks()

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func manifestChecks() {
        let json: [String: Any] = [
            "name": "demo", "title": "Demo", "description": "d", "author": "a",
            "icon": "icon.png", "platforms": ["macOS", "Windows"],
            "preferences": [
                ["name": "token", "type": "password", "required": true],
                // A platform-keyed default must resolve to the macOS value.
                [
                    "name": "socket", "type": "textfield",
                    "default": ["macOS": "/var/run/x.sock", "Windows": "\\\\pipe"]
                ],
                ["name": "flag", "type": "checkbox", "title": "Flag"],
                [
                    "name": "mode", "type": "dropdown", "default": "b",
                    "data": [["title": "A", "value": "a"], ["title": "B", "value": "b"]]
                ]
            ],
            "commands": [
                ["name": "search", "title": "Search", "mode": "view", "keywords": ["find"]],
                ["name": "toggle", "title": "Toggle", "mode": "no-view"],
                ["name": "bar", "title": "Bar", "mode": "menu-bar"],
                [
                    "name": "args", "title": "Args", "mode": "view",
                    "arguments": [["name": "q", "required": true, "placeholder": "Query"]]
                ]
            ]
        ]
        guard let manifest = ExtensionManifest(json: json) else {
            check("manifest parses", false)
            return
        }
        check("manifest parses", true)
        check("title", manifest.title == "Demo")
        check("supports macOS", manifest.supportsMacOS)
        check("commands", manifest.commands.count == 4, "\(manifest.commands.count)")
        check("view mode", manifest.commands[0].mode == .view)
        check("no-view mode", manifest.commands[1].mode == .noView)
        check("menu-bar is unsupported", manifest.commands[2].mode.isSupported == false)
        check("menu-bar explains itself", manifest.commands[2].mode.unsupportedReason != nil)
        // Extensions branch on `environment.appearance`, so the host must not report a fixed one.
        check(
            "a dark host reports dark",
            launchContext(isDarkAppearance: true).jsonString().contains("\"appearance\":\"dark\""))
        check(
            "a light host reports light",
            launchContext(isDarkAppearance: false).jsonString().contains("\"appearance\":\"light\""))
        check("keywords", manifest.commands[0].keywords == ["find"])
        check("arguments", manifest.commands[3].arguments.first?.name == "q")
        check("argument required", manifest.commands[3].arguments.first?.required == true)
        // A blank optional argument arrives as "": `Number(args.x)` is NaN for undefined.
        check(
            "unfilled arguments are completed to empty strings",
            manifest.commands[3].completeArguments([:]) == ["q": ""],
            String(describing: manifest.commands[3].completeArguments([:])))
        check(
            "provided arguments survive completion",
            manifest.commands[3].completeArguments(["q": "hi"]) == ["q": "hi"])

        let prefs = Dictionary(uniqueKeysWithValues: manifest.preferences.map { ($0.name, $0) })
        check("password kind", prefs["token"]?.kind == .password)
        check("required flagged", prefs["token"]?.required == true)
        check(
            "platform-keyed default resolves to macOS",
            prefs["socket"]?.defaultValue == .string("/var/run/x.sock"),
            String(describing: prefs["socket"]?.defaultValue))
        check(
            "checkbox with no default is false",
            prefs["flag"]?.effectiveDefault == .bool(false),
            String(describing: prefs["flag"]?.effectiveDefault))
        check("dropdown options", prefs["mode"]?.options.count == 2)
        check("dropdown default", prefs["mode"]?.effectiveDefault == .string("b"))

        // A manifest with no commands isn't an extension Tinycast can run.
        check("rejects a manifest with no commands", ExtensionManifest(json: ["name": "x"]) == nil)
        check(
            "rejects a Windows-only manifest",
            ExtensionManifest(
                json: [
                    "name": "w", "platforms": ["Windows"],
                    "commands": [["name": "c", "title": "C"]]
                ])?.supportsMacOS == false)

        // Launcher round-trip: an entry id must decode back to the same command.
        let reference = ExtensionCommandRef(extensionName: "@scope/demo", commandName: "search")
        let decoded = ExtensionCommandRef(entryID: reference.entryID)
        check(
            "command ref round-trips", decoded == reference,
            "\(reference.entryID) → \(String(describing: decoded))")
        check(
            "non-extension entry id is rejected",
            ExtensionCommandRef(entryID: "/Applications/Mail.app") == nil)
    }

    static func renderNodeChecks() {
        let json = """
            {"children":[{"id":1,"type":"__screen","props":{"active":true},"children":[
              {"id":2,"type":"List","props":{"isLoading":false,"filtering":true,
                 "actions":{"id":9,"type":"ActionPanel","props":{},"children":[]}},
               "children":[
                {"id":3,"type":"List.Item","props":{
                    "title":"Row","subtitle":"sub","keywords":["kw"],
                    "icon":{"source":"circle-16","tintColor":"raycast-green"},
                    "accessories":[{"text":"3"},{"tag":{"value":"live","color":"#ff0000"}}],
                    "due":{"$date":"2026-01-02T03:04:05.678Z"},
                    "actions":{"id":4,"type":"ActionPanel","props":{},"children":[
                       {"id":5,"type":"Action","props":{"title":"Go","onAction":{"$fn":"5:onAction"},
                          "shortcut":{"modifiers":["cmd","shift"],"key":"g"}},"children":[]},
                       {"id":6,"type":"ActionPanel.Section","props":{"title":"More"},"children":[
                          {"id":7,"type":"Action","props":{"title":"Nested","style":"destructive"},"children":[]}]}]}},
                 "children":[]}]}]}]}
            """
        guard let tree = RenderTree(json: json) else {
            check("render tree decodes", false)
            return
        }
        check("render tree decodes", true)
        check("one screen", tree.screens.count == 1)
        check("active screen resolves", tree.active?.bool("active") == true)
        check("active root is the List", tree.activeRoot?.type == "List")

        guard let list = tree.activeRoot, let item = list.children.first else {
            check("list has an item", false)
            return
        }
        check("list has an item", true)
        check("string prop", item.string("title") == "Row")
        check("bool prop", list.bool("filtering") == true)
        check("array prop", item.array("keywords").compactMap(\.stringValue) == ["kw"])
        check("nested object prop", item.object("icon")?["source"]?.stringValue == "circle-16")
        check("accessories decode", item.array("accessories").count == 2)
        // 2026-01-02T03:04:05.678Z
        let expectedDue = DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5
        ).date!
        check(
            "date prop revives",
            item.date("due").map { abs($0.timeIntervalSince(expectedDue) - 0.678) < 0.01 } == true,
            String(describing: item.date("due")))
        check("slot prop becomes a node", item.node("actions")?.type == "ActionPanel")
        check("screen-level actions slot", list.node("actions")?.id == 9)

        // A number that happens to be whole must not read back as "3.0".
        check(
            "whole numbers stringify without a decimal",
            RenderValue.number(3).stringValue == "3", RenderValue.number(3).stringValue ?? "nil")
        check("bools aren't numbers", RenderValue.bool(true).boolValue == true)
        check(
            "a plain object prop isn't mistaken for a node",
            RenderValue(json: ["type": "day", "min": 1] as [String: Any]).nodeValue == nil)

        let actions = ExtensionScreen.actions(in: item.node("actions"))
        check("actions flatten across sections", actions.count == 2, "\(actions.count)")
        check("first action title", actions.first?.title == "Go")
        check("handler id survives", actions.first?.handler == "5:onAction")
        check(
            "shortcut renders as keycaps", actions.first?.shortcutCaps == ["⌘", "⇧", "G"],
            String(describing: actions.first?.shortcutCaps))
        check("section title carried", actions.last?.section == "More")
        check("destructive style", actions.last?.isDestructive == true)
    }

    static func screenChecks() {
        func tree(_ children: String) -> RenderTree {
            RenderTree(
                json: """
                    {"children":[{"id":1,"type":"__screen","props":{"active":true},"children":[\(children)]}]}
                    """)!
        }

        let listJSON = """
            {"id":2,"type":"List","props":{"filtering":true,"searchBarPlaceholder":"Find…"},"children":[
              {"id":3,"type":"List.Section","props":{"title":"Alpha","subtitle":"two"},"children":[
                {"id":4,"type":"List.Item","props":{"title":"Apple"},"children":[]},
                {"id":5,"type":"List.Item","props":{"title":"Banana"},"children":[]}]},
              {"id":6,"type":"List.Item","props":{"title":"Cherry","keywords":["red"]},"children":[]}]}
            """
        let list = ExtensionScreen(tree: tree(listJSON), query: "")
        check("kind is list", list.kind == .list)
        check("placeholder", list.searchPlaceholder == "Find…")
        check("filters locally", list.filtersLocally)
        check(
            "items flattened in order",
            list.items.map { $0.node.string("title") } == ["Apple", "Banana", "Cherry"])
        check("rows interleave the section header", list.rows.count == 4, "\(list.rows.count)")
        if case .header(let title, let subtitle, _) = list.rows.first {
            check("header title", title == "Alpha")
            check("header subtitle", subtitle == "two")
        } else {
            check("first row is a header", false)
        }

        // Filtering keeps row order and drops now-empty sections along with their header.
        let filtered = ExtensionScreen(tree: tree(listJSON), query: "an")
        check(
            "filter matches title and keyword",
            filtered.items.map { $0.node.string("title") } == ["Banana"],
            String(describing: filtered.items.map { $0.node.string("title") }))
        check("empty section drops its header", filtered.rows.count == 2, "\(filtered.rows.count)")
        let byKeyword = ExtensionScreen(tree: tree(listJSON), query: "red")
        check("keyword match", byKeyword.items.map { $0.node.string("title") } == ["Cherry"])

        // A command that owns the search text must not be filtered behind its back.
        let controlled = ExtensionScreen(
            tree: tree(
                """
                {"id":2,"type":"List","props":{"onSearchTextChange":{"$fn":"2:onSearchTextChange"}},"children":[
                  {"id":3,"type":"List.Item","props":{"title":"Apple"},"children":[]}]}
                """), query: "zzz")
        check("onSearchTextChange disables local filtering", controlled.filtersLocally == false)
        check("controlled rows survive a non-matching query", controlled.items.count == 1)
        check("search handler exposed", controlled.searchTextHandler == "2:onSearchTextChange")

        let grid = ExtensionScreen(
            tree: tree(
                """
                {"id":2,"type":"Grid","props":{"columns":4},"children":[
                  {"id":3,"type":"Grid.Item","props":{"title":"One"},"children":[]}]}
                """), query: "")
        check(
            "kind is grid with columns", grid.kind == .grid(ExtensionGridLayout(columns: 4)),
            String(describing: grid.kind))

        let shaped = ExtensionScreen(
            tree: tree(
                """
                {"id":2,"type":"Grid","props":{"columns":3,"aspectRatio":"16/9","fit":"fill",
                  "inset":"lg"},"children":[
                  {"id":3,"type":"Grid.Item","props":{"title":"One"},"children":[]}]}
                """), query: "")
        check(
            "grid layout props parsed",
            shaped.kind
                == .grid(
                    ExtensionGridLayout(
                        columns: 3, aspectRatio: 16.0 / 9, fills: true, inset: .large)),
            String(describing: shaped.kind))

        let legacy = ExtensionScreen(
            tree: tree(#"{"id":2,"type":"Grid","props":{"itemSize":"small"},"children":[]}"#),
            query: "")
        check("itemSize still sets columns", legacy.kind == .grid(ExtensionGridLayout(columns: 8)))

        let layout = ExtensionGridLayout(columns: 5)
        check(
            "tile width divides the space",
            layout.tileWidth(inWidth: 100, spacing: 5) == 16,
            String(layout.tileWidth(inWidth: 100, spacing: 5)))
        check("columns clamp to Raycast's range", ExtensionGridLayout(columns: 99).columns == 8)
        check("a bad aspect ratio falls back to square", ExtensionGridLayout(aspectRatio: 0).aspectRatio == 1)
        check("large inset insets a quarter of the tile", ExtensionGridLayout.Inset.large.fraction == 0.24)

        let form = ExtensionScreen(
            tree: tree(
                """
                {"id":2,"type":"Form","props":{},"children":[
                  {"id":3,"type":"Form.TextField","props":{"id":"name","value":"Ada"},"children":[]},
                  {"id":4,"type":"Form.Separator","props":{},"children":[]}]}
                """), query: "")
        check("kind is form", form.kind == .form)
        check("fields collected", form.fields.count == 2)
        check("only focusable fields are rows", form.items.count == 1)
        check("the row is the field, not the separator", form.items.first?.node.id == 3)
        check("a separator has no focus index", form.focusItem(for: form.fields[1]) == nil)
        check(
            "a text area keeps the vertical keys",
            ExtensionFormField(type: "Form.TextArea").ownsVerticalKeys)
        check(
            "a dropdown leaves ↵ to the form",
            !ExtensionFormField(type: "Form.Dropdown").ownsReturn)

        let detail = ExtensionScreen(
            // Doubled delimiters: the heading contains `"#`, which closes a single-# string.
            tree: tree(##"{"id":2,"type":"Detail","props":{"markdown":"# Hi"},"children":[]}"##),
            query: "")
        check("kind is detail", detail.kind == .detail)

        let unsupported = ExtensionScreen(
            tree: tree(#"{"id":2,"type":"MenuBarExtra","props":{},"children":[]}"#), query: "")
        check(
            "unknown root reported", unsupported.kind == .unsupported("MenuBarExtra"),
            String(describing: unsupported.kind))

        // An item's own panel wins; the screen's is the fallback.
        let panels = ExtensionScreen(
            tree: tree(
                """
                {"id":2,"type":"List","props":{"actions":{"id":8,"type":"ActionPanel","props":{},"children":[]}},"children":[
                  {"id":3,"type":"List.Item","props":{"title":"A","actions":{"id":9,"type":"ActionPanel","props":{},"children":[]}},"children":[]},
                  {"id":4,"type":"List.Item","props":{"title":"B"},"children":[]}]}
                """), query: "")
        check("item panel wins", panels.actionPanel(forItemAt: 0)?.id == 9)
        check("screen panel is the fallback", panels.actionPanel(forItemAt: 1)?.id == 8)
        check("out-of-range selection falls back", panels.actionPanel(forItemAt: 99)?.id == 8)
    }

    /// An `Action`'s icon is a full `ImageLike`, so the ⌘K panel has to keep its tint.
    @MainActor
    static func actionIconChecks() {
        func icon(
            _ json: String, isDestructive: Bool = false, assets: String? = nil
        ) -> ExtensionImage.Resolved {
            let wrapped = Data(#"{"icon": \#(json)}"#.utf8)
            let props = (try? JSONSerialization.jsonObject(with: wrapped)) as? [String: Any]
            return ExtensionImage.actionIcon(
                props?["icon"].map(RenderValue.init(json:)), assetsPath: assets, isDark: true,
                isDestructive: isDestructive)
        }

        let tinted = icon(#"{"source":"circle-16","tintColor":"raycast-green"}"#)
        check("a tinted symbol keeps its source", tinted.source == .symbol("circle"))
        check("a tinted symbol keeps its tint", tinted.tint == .green)

        // Doubled delimiters: the hex tint contains `"#`, which closes a single-# raw string.
        check(
            "raw hex tints too",
            icon(##"{"source":"circle-16","tintColor":"#FF3B30"}"##).tint
                == Color(red: 1, green: 0x3B / 255, blue: 0x30 / 255))
        check(
            "a themed tint picks the dark side",
            icon(#"{"source":"circle-16","tintColor":{"light":"raycast-red","dark":"raycast-blue"}}"#)
                .tint == .blue)

        let bare = icon(#""checkmark-circle-16""#)
        check("a bare icon still resolves", bare.source == .symbol("checkmark.circle"))
        check("and carries no tint", bare.tint == nil)

        let asset = icon(#""logo.png""#, assets: "/tmp/demo/assets")
        check(
            "an asset name resolves against assets/", asset.source == .file("/tmp/demo/assets/logo.png"),
            String(describing: asset.source))

        check("no icon falls back to a glyph", icon("null").source == .symbol("bolt"))
        let destructive = icon("null", isDestructive: true)
        check("a destructive fallback is a trash glyph", destructive.source == .symbol("trash"))
        check("and takes red", destructive.tint == .red)
        check(
            "a destructive action's own tint wins",
            icon(#"{"source":"circle-16","tintColor":"raycast-yellow"}"#, isDestructive: true).tint
                == .yellow)
        // A tint masks artwork rather than colouring it, so a destructive PNG must stay untinted.
        let destructiveArtwork = icon(#""danger.png""#, isDestructive: true, assets: "/tmp/a")
        check(
            "a destructive artwork icon keeps its own colours",
            destructiveArtwork.source == .file("/tmp/a/danger.png") && destructiveArtwork.tint == nil,
            String(describing: destructiveArtwork))
    }

    private final class MockTokenStore: ExtensionOAuthTokenStore, @unchecked Sendable {
        var storage: [String: String] = [:]

        func get(account: String) -> String? {
            storage[account]
        }

        func set(_ value: String, account: String) -> Bool {
            storage[account] = value
            return true
        }

        func remove(account: String) -> Bool {
            storage.removeValue(forKey: account) != nil
        }

        func removeAll(prefix: String, exactMatch: String) {
            storage = storage.filter { key, _ in
                key != exactMatch && !key.hasPrefix(prefix)
            }
        }
    }

    @MainActor
    static func oauthUnitChecks() {
        let originalStore = ExtensionOAuthKeychain.store
        ExtensionOAuthKeychain.store = MockTokenStore()
        defer { ExtensionOAuthKeychain.store = originalStore }

        // Keychain round-trip
        let extName = "com.test.unit"
        let provId = "unit_provider"
        let json = "{\"accessToken\":\"token_xyz\",\"refreshToken\":\"refresh_abc\"}"

        ExtensionOAuthKeychain.setTokens(json, extensionName: extName, providerId: provId)
        let read = ExtensionOAuthKeychain.getTokens(extensionName: extName, providerId: provId)
        check("OAuth Keychain sets and gets tokens", read == json, read ?? "nil")

        ExtensionOAuthKeychain.removeTokens(extensionName: extName, providerId: provId)
        let afterRemove = ExtensionOAuthKeychain.getTokens(extensionName: extName, providerId: provId)
        check("OAuth Keychain removes tokens", afterRemove == nil, afterRemove ?? "not nil")

        ExtensionOAuthKeychain.setTokens(json, extensionName: extName, providerId: "prov1")
        ExtensionOAuthKeychain.setTokens(json, extensionName: extName, providerId: "prov2")
        ExtensionOAuthKeychain.removeAllTokens(extensionName: extName)
        let afterRemoveAll1 = ExtensionOAuthKeychain.getTokens(extensionName: extName, providerId: "prov1")
        let afterRemoveAll2 = ExtensionOAuthKeychain.getTokens(extensionName: extName, providerId: "prov2")
        check(
            "OAuth Keychain removeAllTokens clears all for extension",
            afterRemoveAll1 == nil && afterRemoveAll2 == nil)

        // URL parsing in ExtensionOAuthSession
        let raycastURL = URL(string: "raycast://oauth?code=auth_123&state=state_456")!
        let params = ExtensionOAuthSession.parseCallback(url: raycastURL)
        check(
            "parseCallback parses query parameters",
            params["code"] == "auth_123" && params["state"] == "state_456")

        let fragmentURL = URL(string: "raycast://oauth#access_token=token_xyz&state=state_789")!
        let fragParams = ExtensionOAuthSession.parseCallback(url: fragmentURL)
        check(
            "parseCallback parses hash fragment",
            fragParams["access_token"] == "token_xyz" && fragParams["state"] == "state_789")

        let nonOAuthURL = URL(string: "raycast://extensions/installed")!
        check(
            "handleCallbackURL ignores a non-oauth URL",
            ExtensionOAuthSession.handleCallbackURL(nonOAuthURL) == .ignored)

        // A callback with nothing waiting for it is reported, not silently dropped.
        let strayURL = URL(string: "tinycast://oauth?code=abc&state=xyz")!
        check(
            "handleCallbackURL reports an expired callback",
            ExtensionOAuthSession.handleCallbackURL(strayURL) == .expired)
    }

    // MARK: - End-to-end through JavaScriptCore

    @MainActor
    static func runtimeChecks() async {
        let runtimeFile = runtimeURL()
        guard FileManager.default.fileExists(atPath: runtimeFile.path) else {
            check("RaycastRuntime.generated.js exists", false, runtimeFile.path)
            return
        }
        check("RaycastRuntime.generated.js exists", true)

        let (runtime, host, recorder) = makeRuntime()
        do {
            try await runtime.boot(
                config: .current(supportDirectory: FileManager.default.temporaryDirectory))
            check("runtime boots in JavaScriptCore", true)
        } catch {
            check("runtime boots in JavaScriptCore", false, error.localizedDescription)
            return
        }

        // A synthetic command exercising React state, the node shims, timers and host calls.
        let command = """
            "use strict";
            const { List, ActionPanel, Action, Icon, showToast, Toast } = require("@raycast/api");
            const React = require("react");
            const path = require("node:path");
            const crypto = require("node:crypto");
            const h = React.createElement;
            module.exports.default = function Command() {
              const [count, setCount] = React.useState(0);
              React.useEffect(() => {
                const timer = setTimeout(() => setCount(1), 20);
                showToast({ style: Toast.Style.Success, title: "hello" });
                return () => clearTimeout(timer);
              }, []);
              const digest = crypto.createHash("sha256").update("abc").digest("hex").slice(0, 8);
              // AbortSignal's statics too: `AbortSignal.timeout` used to be "not a function".
              const abortable = [
                typeof AbortSignal.timeout, typeof AbortSignal.abort, typeof AbortSignal.any,
                String(AbortSignal.timeout(5e3).aborted), AbortSignal.abort().reason.name,
              ].join(",");
              return h(List, { navigationTitle: "Synthetic", isLoading: false },
                h(List.Item, {
                  title: "count=" + count,
                  subtitle: path.join("/a/b", "../c"),
                  icon: Icon.Circle,
                  accessories: [{ text: digest }, { text: abortable }],
                  actions: h(ActionPanel, null,
                    h(Action, { title: "Bump", onAction: () => setCount((v) => v + 10) }))
                }));
            };
            """
        await runtime.start(
            session: "s1", code: command, file: URL(fileURLWithPath: "/tmp/synthetic.js"),
            mode: .view, context: launchContext())
        await settle()

        check("no failures", recorder.failures.isEmpty, recorder.failures.joined(separator: "\n"))
        check("rendered at least once", !recorder.trees.isEmpty)

        guard var screen = recorder.trees.last.map({ ExtensionScreen(tree: $0, query: "") }) else {
            check("screen builds from the live tree", false)
            return
        }
        check("screen builds from the live tree", true)
        check("navigation title", screen.navigationTitle == "Synthetic")
        check(
            "timer fired and re-rendered",
            screen.items.first?.node.string("title") == "count=1",
            screen.items.first?.node.string("title") ?? "nil")
        check(
            "node path shim", screen.items.first?.node.string("subtitle") == "/a/c",
            screen.items.first?.node.string("subtitle") ?? "nil")
        check(
            "crypto shim",
            ExtensionAccessoriesView_labelForTest(screen.items.first?.node.array("accessories").first)
                == "ba7816bf",
            String(describing: screen.items.first?.node.array("accessories").first))
        check("toast reached the host", host.toasts == ["hello"], host.toasts.joined(separator: ","))
        check(
            "AbortSignal carries its statics",
            ExtensionAccessoriesView_labelForTest(screen.items.first?.node.array("accessories").last)
                == "function,function,function,false,AbortError",
            String(describing: screen.items.first?.node.array("accessories").last))

        // Dispatch the row's action and confirm the re-render.
        let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: 0))
        check("action is dispatchable", actions.first?.handler != nil)
        if let handler = actions.first?.handler {
            await runtime.dispatch(
                session: "s1", handler: handler,
                payload: ExtensionRuntime.jsonString(from: []))
            await settle()
            screen = ExtensionScreen(tree: recorder.trees.last!, query: "")
            check(
                "action re-rendered the row",
                screen.items.first?.node.string("title") == "count=11",
                screen.items.first?.node.string("title") ?? "nil")
        }

        // OAuth PKCE and TokenSet runtime tests
        let (oauthRuntime, oauthHost, oauthRecorder) = makeRuntime()
        try? await oauthRuntime.boot(
            config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        let oauthCommand = """
            "use strict";
            const { OAuth, showHUD } = require("@raycast/api");
            module.exports.default = async function () {
              const client = new OAuth.PKCEClient({
                redirectMethod: OAuth.RedirectMethod.Web,
                providerName: "GitHub",
                providerId: "gh",
              });
              const req = await client.authorizationRequest({
                endpoint: "https://github.com/login/oauth/authorize",
                clientId: "id123",
              });
              const auth = await client.authorize(req);
              const tokens = new OAuth.TokenSet({
                accessToken: "token_" + auth.authorizationCode,
                refreshToken: "refresh_123",
                expiresIn: 3600,
              });
              await client.setTokens(tokens);
              const read = await client.getTokens();
              await showHUD(read.accessToken);
            };
            """
        await oauthRuntime.start(
            session: "sOAuth", code: oauthCommand,
            file: URL(fileURLWithPath: "/tmp/oauth.js"), mode: .noView,
            context: launchContext(mode: .noView))
        await settle()
        check("oauth command finished", oauthRecorder.finished, oauthRecorder.failures.joined())
        check(
            "oauth flow reached token storage",
            oauthHost.huds == ["token_auth_code_swift_test"],
            oauthHost.huds.joined(separator: ","))
        await oauthRuntime.stop(session: "sOAuth")

        // Command arguments must reach `props.arguments`, and the bag must exist even when empty.
        let (withArguments, _, argumentRecorder) = makeRuntime()
        try? await withArguments.boot(
            config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        let argumentCommand = #"""
            "use strict";
            const { Detail } = require("@raycast/api");
            const React = require("react");
            module.exports.default = function (props) {
              const bag = props.arguments;
              return React.createElement(Detail, {
                markdown: [bag.hours, bag.minutes, Object.keys(bag).length, props.launchType].join("|"),
              });
            };
            """#
        await withArguments.start(
            session: "sA", code: argumentCommand, file: URL(fileURLWithPath: "/tmp/args.js"),
            mode: .view, context: launchContext(arguments: ["hours": "0", "minutes": "5"]))
        await settle()
        let argumentMarkdown = argumentRecorder.trees.last?.activeRoot?.string("markdown") ?? ""
        check(
            "launch arguments reach props.arguments", argumentMarkdown == "0|5|2|userInitiated",
            argumentMarkdown)
        await withArguments.stop(session: "sA")

        // React's scheduler drives commits through `setTimeout`, shared across sessions.
        let (pending, _, pendingRecorder) = makeRuntime()
        try? await pending.boot(
            config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        let tickingCommand = #"""
            "use strict";
            const { List } = require("@raycast/api");
            const React = require("react");
            module.exports.default = function Command() {
              const [tick, setTick] = React.useState(0);
              React.useEffect(() => {
                const id = setInterval(() => setTick((v) => v + 1), 40);
                return () => clearInterval(id);
              }, []);
              return React.createElement(List, null,
                React.createElement(List.Item, { key: "t", title: "tick=" + tick }));
            };
            """#
        await pending.start(
            session: "p1", code: tickingCommand, file: URL(fileURLWithPath: "/tmp/tick.js"),
            mode: .view, context: launchContext())
        await settle(70)
        await pending.stop(session: "p1")
        pending.shutdown()
        let pendingRerun = Recorder()
        pending.setDelegate(pendingRerun)
        try? await pending.boot(
            config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        await pending.start(
            session: "p2", code: tickingCommand, file: URL(fileURLWithPath: "/tmp/tick.js"),
            mode: .view, context: launchContext())
        await settle(150)
        check(
            "a re-run after stopping mid-timer still renders",
            !pendingRerun.trees.isEmpty,
            "first run rendered \(pendingRecorder.trees.count)×; "
                + pendingRerun.failures.joined(separator: "|"))
        await pending.stop(session: "p2")

        await runtime.stop(session: "s1")
        let rerunRecorder = Recorder()
        runtime.setDelegate(rerunRecorder)
        await runtime.start(
            session: "s1b", code: command, file: URL(fileURLWithPath: "/tmp/synthetic.js"),
            mode: .view, context: launchContext())
        await settle()
        check(
            "a second run in the same runtime renders",
            !rerunRecorder.trees.isEmpty, rerunRecorder.failures.joined(separator: "|"))
        check(
            "the second run's timers still fire",
            rerunRecorder.trees.last
                .map { ExtensionScreen(tree: $0, query: "").items.first?.node.string("title") == "count=1" }
                == true,
            rerunRecorder.trees.last
                .flatMap { ExtensionScreen(tree: $0, query: "").items.first?.node.string("title") }
                ?? "no tree")
        await runtime.stop(session: "s1b")
        runtime.setDelegate(recorder)

        // A no-view command runs headless and reports completion.
        let (headless, headlessHost, headlessRecorder) = makeRuntime()
        try? await headless.boot(
            config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        await headless.start(
            session: "s2",
            code: """
                "use strict";
                const { showHUD } = require("@raycast/api");
                module.exports.default = async function () { await showHUD("done"); };
                """,
            file: URL(fileURLWithPath: "/tmp/headless.js"), mode: .noView,
            context: launchContext(mode: .noView))
        await settle()
        check("no-view command finished", headlessRecorder.finished, headlessRecorder.failures.joined())
        check("no-view HUD reached the host", headlessHost.huds == ["done"])
        await headless.stop(session: "s2")

        // A throwing command surfaces its error rather than taking the runtime down.
        let (failing, _, failingRecorder) = makeRuntime()
        try? await failing.boot(
            config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        await failing.start(
            session: "s3",
            code: #"module.exports.default = function () { throw new Error("kaboom"); };"#,
            file: URL(fileURLWithPath: "/tmp/bad.js"), mode: .view, context: launchContext())
        await settle()
        check(
            "a throwing command reports a failure",
            failingRecorder.failures.contains { $0.contains("kaboom") },
            failingRecorder.failures.joined(separator: "|"))
        await failing.stop(session: "s3")

        await swiftHelperChecks()
        zlibChecks()
    }

    /// Raycast's `swift:` wrapper chmods its bundled helper before spawning it: store zips ship it 644.
    @MainActor
    static func swiftHelperChecks() async {
        let helper = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-helper-\(UUID().uuidString)")
        try? Data("#!/bin/sh\necho '{\"hex\":\"#FF0000\"}'\n".utf8).write(to: helper)
        defer { try? FileManager.default.removeItem(at: helper) }

        let (runtime, _, recorder) = makeRuntime()
        try? await runtime.boot(
            config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        let command = """
            "use strict";
            const { Detail } = require("@raycast/api");
            const React = require("react");
            const { chmod } = require("fs/promises");
            const { spawn } = require("child_process");
            module.exports.default = function Command() {
              const [state, setState] = React.useState("pending");
              React.useEffect(() => {
                (async () => {
                  await chmod("\(helper.path)", "755");
                  const child = spawn("\(helper.path)", ["pick"]);
                  const out = [];
                  child.stdout.on("data", (chunk) => out.push(chunk.toString()));
                  child.on("exit", (code) => setState(code + ":" + JSON.parse(out.join("")).hex));
                })().catch((error) => setState("threw:" + error.message));
              }, []);
              return React.createElement(Detail, { markdown: state });
            };
            """
        await runtime.start(
            session: "sSwift", code: command, file: URL(fileURLWithPath: "/tmp/swift-helper.js"),
            mode: .view, context: launchContext())
        await settle(1200)

        let mode = (try? FileManager.default.attributesOfItem(atPath: helper.path))
            .flatMap { $0[.posixPermissions] as? NSNumber }
        check("chmod applies the requested mode", mode?.intValue == 0o755, String(describing: mode))
        check(
            "a chmodded helper is spawnable",
            recorder.trees.last?.activeRoot?.string("markdown") == "0:#FF0000",
            recorder.trees.last?.activeRoot?.string("markdown") ?? "no tree")
        await runtime.stop(session: "sSwift")
    }

    /// `zlib` is the one node shim with no JS-side implementation to lean on.
    static func zlibChecks() {
        let payload = Data(String(repeating: "tinycast extensions ", count: 64).utf8)
        do {
            check("gzip round-trips", try Zlib.gunzip(Zlib.gzip(payload)) == payload)
            check("zlib round-trips", try Zlib.inflate(Zlib.deflate(payload)) == payload)
            check("raw deflate round-trips", try Zlib.inflateRaw(Zlib.deflateRaw(payload)) == payload)
            check("gzip actually compresses", try Zlib.gzip(payload).count < payload.count)
        } catch {
            check("zlib round-trips", false, error.localizedDescription)
        }
        // Known-answer checks so a framing bug can't hide behind a self-consistent round-trip.
        check("crc32", Zlib.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        check("adler32", Zlib.adler32(Data("123456789".utf8)) == 0x091E_01DE)
    }

    // MARK: - Running a real extension

    @MainActor
    static func runInstalledExtension(directory: URL, command commandName: String?) async {
        guard let manifest = try? ExtensionManifest.load(directory: directory) else {
            print("Not an extension: \(directory.path)")
            exit(1)
        }
        let runnable = manifest.commands.filter { $0.mode.isSupported }
        guard
            let target = commandName.flatMap({ name in runnable.first { $0.name == name } })
                ?? runnable.first
        else {
            print("No runnable command in \(manifest.title)")
            exit(1)
        }
        let bundle = directory.appendingPathComponent("\(target.name).js")
        guard let code = try? String(contentsOf: bundle, encoding: .utf8) else {
            print("Missing built bundle: \(bundle.path)")
            exit(1)
        }

        print("▶ \(manifest.title) — \(target.title) (\(target.mode.rawValue))")
        let (runtime, host, recorder) = makeRuntime()
        do {
            try await runtime.boot(config: .current(supportDirectory: FileManager.default.temporaryDirectory))
        } catch {
            print("boot failed: \(error.localizedDescription)")
            exit(1)
        }

        var preferences: [String: ExtensionPreferenceValue] = [:]
        for schema in manifest.preferences + target.preferences {
            preferences[schema.name] = schema.effectiveDefault
        }
        // `EXT_TEST_PREFS` stands in for Settings: many extensions have no manifest default.
        for (key, value) in environmentPreferences() { preferences[key] = value }
        let context = launchContext(
            extensionName: manifest.name, command: target.name, mode: target.mode,
            assets: directory.appendingPathComponent("assets").path, preferences: preferences,
            arguments: target.completeArguments(environmentArguments()))
        let settleMS = UInt64(
            ProcessInfo.processInfo.environment["EXT_TEST_SETTLE_MS"].flatMap(UInt64.init) ?? 1500)

        // `EXT_TEST_RERUN=1` runs, tears down and runs again: the works-once-then-hangs case.
        if ProcessInfo.processInfo.environment["EXT_TEST_RERUN"] != nil {
            await runtime.start(
                session: "r1", code: code, file: bundle, mode: target.mode, context: context)
            await settle(settleMS)
            print("run 1: \(recorder.trees.count) render(s), \(recorder.failures.count) failure(s)")
            await runtime.stop(session: "r1")
            runtime.shutdown()
            let first = recorder.trees.count
            try? await runtime.boot(
                config: .current(supportDirectory: FileManager.default.temporaryDirectory))
            print("→ tore down after \(first) render(s); re-running in a fresh context")
        }

        await runtime.start(
            session: "s1", code: code, file: bundle, mode: target.mode, context: context)
        await settle(settleMS)

        for failure in recorder.failures { print("✗ \(failure)") }
        if ProcessInfo.processInfo.environment["EXT_TEST_VERBOSE"] != nil {
            for line in recorder.logs { print("  \(line)") }
        }
        print(
            "\(recorder.trees.count) render(s); host calls: \(Set(host.calls).sorted().joined(separator: ", "))"
        )
        for toast in host.toasts { print("  toast: \(toast)") }
        for hud in host.huds { print("  hud: \(hud)") }
        if let tree = recorder.trees.last {
            let screen = ExtensionScreen(tree: tree, query: "")
            print("root: \(screen.kind)  rows: \(screen.rows.count)  fields: \(screen.fields.count)")
            for item in screen.items.prefix(12) {
                let node = item.node
                let accessories = node.array("accessories").count
                print(
                    "  • \(node.string("title") ?? "")"
                        + (node.string("subtitle").map { "  —  \($0)" } ?? "")
                        + (accessories > 0 ? "  [\(accessories) accessories]" : "")
                        + (node.node("actions") != nil ? "  ⌘K" : ""))
            }
            if case .detail = screen.kind {
                print("  markdown: \((screen.root?.string("markdown") ?? "").prefix(200))")
            }
        }
        await runtime.stop(session: "s1")
        exit(recorder.failures.isEmpty ? 0 : 1)
    }
}

/// The accessory label rule lives in the view layer; mirror just the string case for the harness.
private func ExtensionAccessoriesView_labelForTest(_ value: RenderValue?) -> String? {
    guard let value else { return nil }
    if let text = value.stringValue { return text }
    return value.objectValue?["text"]?.stringValue
}
