// Standalone test for the Raycast-extension runtime — compiles the *real* engine sources (no copy to
// sync) and runs them against JavaScriptCore, exactly as the app does:
//
//   swiftc -parse-as-library \
//     Tinycast/Core/Extensions/{ExtensionRuntime,ExtensionNodeShims,ExtensionBootConfig,ExtensionManifest,ExtensionScreen,RenderNode}.swift \
//     via Scripts/run-tests.sh ext-test
//     -o /tmp/ext-test && /tmp/ext-test
//
// With no arguments it runs the built-in checks (manifest parsing, tree decoding, screen flattening,
// and a synthetic command end-to-end through JSC). Pass a directory to run a real extension:
//
//   /tmp/ext-test ~/.config/raycast/extensions/<uuid> [command-name]

import Foundation

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

    /// Records every host call and answers it. `proc` and `fetch` go through the app's real
    /// implementations, so an extension that shells out or hits the network behaves as it would in the
    /// app; everything main-actor-shaped (clipboard, window, storage) gets a canned answer.
    @MainActor
    final class StubHost: ExtensionHostAPI {
        var calls: [String] = []
        var toasts: [String] = []
        var huds: [String] = []
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
        arguments: [String: String] = [:]
    ) -> ExtensionLaunchContext {
        ExtensionLaunchContext(
            extensionName: extensionName, extensionTitle: extensionName, commandName: command,
            commandMode: mode, assetsPath: assets, supportPath: "/tmp",
            preferences: preferences, caches: [:], arguments: arguments, fallbackText: nil)
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

    /// `EXT_TEST_PREFS` as JSON — strings and bools only, which is what a manifest preference holds.
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
        check("keywords", manifest.commands[0].keywords == ["find"])
        check("arguments", manifest.commands[3].arguments.first?.name == "q")
        check("argument required", manifest.commands[3].arguments.first?.required == true)
        // A blank optional argument must arrive as "", never absent: extensions do `Number(args.x)`,
        // which is 0 for "" but NaN for undefined.
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
            list.items.map { $0.string("title") } == ["Apple", "Banana", "Cherry"])
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
            filtered.items.map { $0.string("title") } == ["Banana"],
            String(describing: filtered.items.map { $0.string("title") }))
        check("empty section drops its header", filtered.rows.count == 2, "\(filtered.rows.count)")
        let byKeyword = ExtensionScreen(tree: tree(listJSON), query: "red")
        check("keyword match", byKeyword.items.map { $0.string("title") } == ["Cherry"])

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
        check("kind is grid with columns", grid.kind == .grid(columns: 4), String(describing: grid.kind))

        let form = ExtensionScreen(
            tree: tree(
                """
                {"id":2,"type":"Form","props":{},"children":[
                  {"id":3,"type":"Form.TextField","props":{"id":"name","value":"Ada"},"children":[]},
                  {"id":4,"type":"Form.Separator","props":{},"children":[]}]}
                """), query: "")
        check("kind is form", form.kind == .form)
        check("fields collected", form.fields.count == 2)
        check("form has no selectable rows", form.items.isEmpty)

        let detail = ExtensionScreen(
            // Doubled delimiters: the markdown heading contains `"#`, which closes a single-# raw string.
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
              // AbortSignal's statics, not just its instance shape: an extension reaching for
              // `AbortSignal.timeout` used to get "is not a function" at runtime.
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
            screen.items.first?.string("title") == "count=1",
            screen.items.first?.string("title") ?? "nil")
        check(
            "node path shim", screen.items.first?.string("subtitle") == "/a/c",
            screen.items.first?.string("subtitle") ?? "nil")
        check(
            "crypto shim",
            ExtensionAccessoriesView_labelForTest(screen.items.first?.array("accessories").first)
                == "ba7816bf",
            String(describing: screen.items.first?.array("accessories").first))
        check("toast reached the host", host.toasts == ["hello"], host.toasts.joined(separator: ","))
        check(
            "AbortSignal carries its statics",
            ExtensionAccessoriesView_labelForTest(screen.items.first?.array("accessories").last)
                == "function,function,function,false,AbortError",
            String(describing: screen.items.first?.array("accessories").last))

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
                screen.items.first?.string("title") == "count=11",
                screen.items.first?.string("title") ?? "nil")
        }

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

        // Running a second command in the same runtime must work exactly like the first — the JSContext
        // and React's scheduler are shared across sessions.
        // Stop while a timer is still pending — what closing the palette mid-refresh does. React's
        // scheduler drives commits through `setTimeout`, so anything that kills timers it doesn't own
        // can wedge every later session.
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
                .map { ExtensionScreen(tree: $0, query: "").items.first?.string("title") == "count=1" }
                == true,
            rerunRecorder.trees.last
                .flatMap { ExtensionScreen(tree: $0, query: "").items.first?.string("title") } ?? "no tree")
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

        zlibChecks()
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
        // `EXT_TEST_PREFS={"version":"v8"}` stands in for what the user set in Settings — plenty of
        // extensions branch on a preference that has no manifest default.
        for (key, value) in environmentPreferences() { preferences[key] = value }
        let context = launchContext(
            extensionName: manifest.name, command: target.name, mode: target.mode,
            assets: directory.appendingPathComponent("assets").path, preferences: preferences,
            arguments: target.completeArguments(environmentArguments()))
        let settleMS = UInt64(
            ProcessInfo.processInfo.environment["EXT_TEST_SETTLE_MS"].flatMap(UInt64.init) ?? 1500)

        // `EXT_TEST_RERUN=1` runs the command, tears it down the way the palette does, and runs it
        // again in the same runtime — the "works once, then hangs" case.
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
                let accessories = item.array("accessories").count
                print(
                    "  • \(item.string("title") ?? "")"
                        + (item.string("subtitle").map { "  —  \($0)" } ?? "")
                        + (accessories > 0 ? "  [\(accessories) accessories]" : "")
                        + (item.node("actions") != nil ? "  ⌘K" : ""))
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
