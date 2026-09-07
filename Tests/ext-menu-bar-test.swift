import AppKit
import Foundation

extension ExtensionTests {
    @MainActor
    static func runInstalledMenuBar(_ owner: InstalledExtension, command: ExtensionCommand) async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tinycast-live-menu-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ExtensionStorage(directory: directory.appendingPathComponent("storage"))
        for (key, value) in environmentPreferences() {
            storage.setPreference(extension: owner.manifest.name, key: key, value: value)
        }
        var hosts: [StubHost] = []
        var boots = 0
        weak var lastRuntime: ExtensionRuntime?
        let manager = ExtensionMenuBarManager(
            storage: storage, file: directory.appendingPathComponent("bars.json"),
            supportDirectory: directory.appendingPathComponent("support"), showsStatusItems: false,
            makeExecution: { _, _ in
                boots += 1
                let host = StubHost()
                hosts.append(host)
                let runtime = ExtensionRuntime(hostAPI: host, runtimeURL: runtimeURL())
                lastRuntime = runtime
                return .init(runtime: runtime, stop: {})
            }, onError: { message, _, _ in check("installed menu command", false, message) })
        defer { manager.stop() }
        let reference = ExtensionCommandRef(extensionName: owner.manifest.name, commandName: command.name)
        print("▶ Native menu lifecycle: \(owner.title) — \(command.title)")
        manager.synchronize([owner])
        manager.run(owner, command: command)
        for _ in 0..<200 where manager.isRunning { await settle(50) }
        check("real command settles and unloads", !manager.isRunning && lastRuntime == nil)
        check("real command saves a native item", manager.store.records[reference.entryID]?.snapshot?.hasMenu == true)
        let controller = manager.controller(for: reference, owner: owner)
        for cycle in 1...3 {
            controller.menuWillOpen(controller.menu)
            await settle(1500)
            let items = controller.menu.items
            check("cycle \(cycle) renders provider sections", items.contains { $0.isSectionHeader })
            check("cycle \(cycle) renders Configure", items.contains { $0.title == "Configure…" && $0.isEnabled })
            print("  cycle \(cycle): \(items.count) native menu rows, \(boots) context boots")
            if let index = items.firstIndex(where: { $0.title == "Refresh" }) {
                controller.menuDidClose(controller.menu)
                controller.menu.performActionForItem(at: index)
                for _ in 0..<200 where manager.isRunning { await settle(50) }
                check("cycle \(cycle) refresh finishes and unloads", !manager.isRunning && lastRuntime == nil)
            } else {
                check("real command offers Refresh", false)
                controller.menuDidClose(controller.menu)
            }
        }
        controller.menuWillOpen(controller.menu)
        await settle(1500)
        if let index = controller.menu.items.firstIndex(where: { $0.title == "Open Provider Usage" }) {
            controller.menuDidClose(controller.menu)
            controller.menu.performActionForItem(at: index)
            await settle(300)
            check("real command dispatches launchCommand", hosts.last?.calls.contains("system.launchCommand") == true)
        }
        print("\(passes) passed, \(failures) failed; \(boots) fresh contexts")
    }

    @MainActor
    static func menuBarRenderingChecks() async {
        let controller = ExtensionMenuBarController(entryID: "tinycast-fixture-rendering", assetsPath: "/tmp", isVisible: false)
        defer { controller.remove() }
        let row = RenderNode(id: 2, type: "MenuBarExtra.Item", props: [
            "title": .string("Weekly · 17%"), "subtitle": .string("resets in 5d"),
            "icon": .string("star-16"), "onAction": .handler("refresh"),
            "shortcut": .object(["macOS": .object(["key": .string("pageDown"),
                                                   "modifiers": .array([.string("cmd")])])])
        ])
        let root = RenderNode(id: 1, type: "MenuBarExtra", children: [row])
        controller.showMenu(root, session: "one")
        await settle(200)
        let item = controller.menu.items.first
        check("menu is prepared while closed", item?.title == "Weekly · 17% resets in 5d" && item?.image?.size.width == 14,
              "title=\(item?.title ?? "nil") image=\(String(describing: item?.image?.size))")
        check("menu contains only extension rows", controller.menu.items.count == 1)
        check("macOS named shortcut maps to native key", item?.keyEquivalent == "\u{f72d}"
              && item?.keyEquivalentModifierMask == .command)
        check("closed menu has inline secondary text", item?.attributedTitle?.string == "Weekly · 17% resets in 5d"
              && item?.subtitle == nil)
        controller.clearMenu()
        check("unloading clears cached callbacks", item?.representedObject == nil)
        controller.menuWillOpen(controller.menu)
        check("opening keeps prepared rows", controller.menu.items.first === item)
        let loading = RenderNode(id: 3, type: "MenuBarExtra", props: ["isLoading": .bool(true)], children: [])
        controller.showMenu(loading, session: "two")
        check("loading does not replace settled content", controller.menu.items.first === item)
        controller.showMenu(root, session: "two")
        check("fresh session rebinds existing rows", controller.menu.items.first === item && item?.representedObject != nil)
        let image = item?.image
        var changes = 0
        let observation = NotificationCenter.default.addObserver(forName: NSMenu.didChangeItemNotification,
                                                                  object: controller.menu, queue: nil) { _ in
            MainActor.assumeIsolated { changes += 1 }
        }
        for _ in 0..<20 { controller.showMenu(root, session: "two") }
        NotificationCenter.default.removeObserver(observation)
        check("repeated renders preserve rows and icons", controller.menu.items.first === item && item?.image === image)
        check("identical renders cause no native layout updates", changes == 0, "\(changes) menu notifications")
        let props = row.props.merging(["subtitle": .string("resets in 4d")]) { _, value in value }
        let updated = RenderNode(id: 2, type: row.type, props: props)
        controller.showMenu(RenderNode(id: 1, type: root.type, children: [updated]), session: "two")
        check("text changes update in place", controller.menu.items.first === item
              && item?.attributedTitle?.string == "Weekly · 17% resets in 4d")
        controller.menuDidClose(controller.menu)
        controller.clearMenu()
    }

    @MainActor
    final class DelayedMenuHost: ExtensionHostAPI {
        var pending: [CheckedContinuation<String, Never>] = []
        var huds: [String] = []

        func perform(api: String, method: String, arguments: [RenderValue]) async throws -> String {
            if api == "clipboard" { return await withCheckedContinuation { pending.append($0) } }
            if api == "feedback", method == "showHUD" { huds.append(arguments.first?.stringValue ?? "") }
            return ""
        }

        func sessionEnded() {}
    }

    @MainActor
    static func lateMenuResponseChecks() async {
        let host = DelayedMenuHost()
        let runtime = ExtensionRuntime(hostAPI: host, runtimeURL: runtimeURL())
        defer {
            runtime.shutdown()
            for reply in host.pending { reply.resume(returning: "") }
        }
        let code = #"""
            const { Clipboard, showHUD } = require("@raycast/api");
            module.exports.default = async () => { await showHUD(await Clipboard.readText()); };
            """#
        let file = URL(fileURLWithPath: "/tmp/late-response.js")
        for session in ["old", "new"] {
            try? await runtime.boot(config: .current(supportDirectory: FileManager.default.temporaryDirectory))
            await runtime.start(session: session, code: code, file: file, mode: .noView, context: launchContext(mode: .noView))
            await settle(100)
            if session == "old" { runtime.shutdown() }
        }
        guard host.pending.count == 2 else { check("both host requests wait", false); return }
        host.pending.removeFirst().resume(returning: #""old""#)
        await settle(100)
        check("late response cannot settle a fresh context", host.huds.isEmpty)
        host.pending.removeFirst().resume(returning: #""new""#)
        await settle(100)
        check("fresh context receives only its own response", host.huds == ["new"])
    }

    @MainActor
    final class MenuHost: ExtensionHostAPI {
        let name: String
        let storage: ExtensionStorage
        var didCancel = false

        init(name: String, storage: ExtensionStorage) {
            self.name = name
            self.storage = storage
        }

        func perform(api: String, method: String, arguments: [RenderValue]) async throws -> String {
            if api == "storage", method == "set", let key = arguments.first?.stringValue,
                let value = arguments.dropFirst().first.flatMap(ExtensionStorage.StoredValue.init(renderValue:)) {
                storage.setLocalStorage(extension: name, key: key, value: value)
            }
            if api == "fetch" {
                do { try await Task.sleep(for: .seconds(5)) } catch { didCancel = true; throw error }
            }
            return ""
        }

        func sessionEnded() {}
    }

    @MainActor
    static func menuBarHostChecks() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        await menuBarRenderingChecks()
        await lateMenuResponseChecks()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tinycast-menu-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ExtensionStorage(directory: directory.appendingPathComponent("storage"))
        let source = #"""
            const React = require("react");
            const { MenuBarExtra, LocalStorage, environment } = require("@raycast/api");
            module.exports.default = function(props) {
              const [loading, setLoading] = React.useState(true);
              const [title, setTitle] = React.useState(environment.launchType);
              const actions = React.useRef(0);
              React.useEffect(() => {
                if (props.launchContext?.origin) LocalStorage.setItem("launch",
                  environment.launchType + ":" + props.arguments.value + ":" + props.launchContext.origin);
              }, []);
              React.useEffect(() => { const timer = setTimeout(() => setLoading(false), 50);
                return () => clearTimeout(timer); }, []);
              return React.createElement(MenuBarExtra, { title, isLoading: loading, icon: "star-16" },
                React.createElement(MenuBarExtra.Section, { title: "Usage" },
                  React.createElement(MenuBarExtra.Item, { title: "Information", subtitle: "Details", tooltip: "Tip" }),
                  React.createElement(MenuBarExtra.Item, { title: "Refresh", shortcut: { key: "r", modifiers: ["cmd"] },
                    alternate: React.createElement(MenuBarExtra.Item, { title: "Alternate", onAction() {} }),
                    onAction: async event => {
                      const action = ++actions.current;
                      await new Promise(resolve => setTimeout(resolve, action === 1 ? 250 : 650));
                      await LocalStorage.setItem("clicked", event.type);
                      await LocalStorage.setItem("completed", action);
                      setTitle("Updated");
                    } }),
                  React.createElement(MenuBarExtra.Submenu, { title: "Empty" }),
                  React.createElement(MenuBarExtra.Submenu, { title: "Nested" },
                    React.createElement(MenuBarExtra.Item, { title: "Child", onAction() {} }))));
            };
            """#
        func owner(_ name: String, code: String, mode: String = "menu-bar") -> InstalledExtension {
            let path = directory.appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try? code.write(to: path.appendingPathComponent("bar.js"), atomically: true, encoding: .utf8)
            let manifest = ExtensionManifest(json: ["name": name, "commands": [
                ["name": "bar", "title": "Bar", "mode": mode, "interval": "10m", "disabledByDefault": true]
            ]])!
            return InstalledExtension(manifest: manifest, directory: path)
        }
        let first = owner("first", code: source)
        let second = owner("second", code: source)
        let empty = owner("empty", code: "module.exports.default = () => null;")
        let hanging = owner("hanging", code: #"""
            const React = require("react");
            const { MenuBarExtra } = require("@raycast/api");
            module.exports.default = () => {
              React.useEffect(() => { fetch("https://fixture.invalid"); }, []);
              return React.createElement(MenuBarExtra, { title: "Loading", isLoading: true });
            };
            """#)
        let job = owner("job", code: #"""
            const { LocalStorage, environment } = require("@raycast/api");
            module.exports.default = async props => {
              await LocalStorage.setItem("context", environment.launchType + ":" + props.launchContext.origin);
            };
            """#, mode: "no-view")
        let installed = [first, second, empty, hanging, job]
        let firstRef = ExtensionCommandRef(extensionName: "first", commandName: "bar")
        var boots: [(String, ExtensionLaunchType)] = []
        var failures: [String] = []
        var hosts: [MenuHost] = []
        weak var lastRuntime: ExtensionRuntime?
        let manager = ExtensionMenuBarManager(
            storage: storage, file: directory.appendingPathComponent("bars.json"),
            supportDirectory: directory.appendingPathComponent("support"), executionTimeout: .seconds(1),
            showsStatusItems: false,
            makeExecution: { owner, type in
                boots.append((owner.manifest.name, type))
                let host = MenuHost(name: owner.manifest.name, storage: storage)
                hosts.append(host)
                let runtime = ExtensionRuntime(hostAPI: host, runtimeURL: runtimeURL())
                lastRuntime = runtime
                return .init(runtime: runtime, stop: {})
            }, onError: { message, _, _ in failures.append(message) })
        defer { manager.stop() }
        manager.synchronize(installed)
        check("install does not run a menu command", boots.isEmpty && manager.store.records.isEmpty)
        manager.run(first, command: first.manifest.commands[0])
        await settle(400)
        check("settled menu keeps only a snapshot", !manager.isRunning && lastRuntime == nil)
        check("manual launch snapshots title", manager.store.records[firstRef.entryID]?.snapshot?.title == "userInitiated")
        check("manifest interval schedules next refresh", manager.store.records[firstRef.entryID]?.nextRefresh != nil)

        let controller = manager.controller(for: firstRef, owner: first)
        controller.menuWillOpen(controller.menu)
        await settle(300)
        check("opening a menu reloads its runtime", boots.count == 2 && manager.isRunning)
        let items = controller.menu.items
        check("native section header", items.first?.isSectionHeader == true && items.first?.title == "Usage")
        check("informational row is disabled", items.first { $0.title == "Information Details" }?.isEnabled == false)
        check("inline subtitle and tooltip", items.first { $0.title == "Information Details" }?.attributedTitle?.string
              == "Information Details" && items.first { $0.title == "Information Details" }?.subtitle == nil
              && items.first { $0.title == "Information Details" }?.toolTip == "Tip")
        check("empty submenu is disabled", items.first { $0.title == "Empty" }?.isEnabled == false)
        check("nested menu retains children", items.first { $0.title == "Nested" }?.submenu?.items.first?.title == "Child")
        let alternate = items.first { $0.title == "Alternate" }
        check("alternate inherits shortcut and adds option", alternate?.isAlternate == true
              && alternate?.keyEquivalent == "r" && alternate?.keyEquivalentModifierMask == [.command, .option])
        await settle(900)
        check("an open settled menu outlives background timeout", manager.isRunning)
        if let index = controller.menu.items.firstIndex(where: { $0.title == "Refresh" }) {
            controller.menuDidClose(controller.menu)
            controller.menu.performActionForItem(at: index)
            await settle(150)
            check("closing menu does not cancel an async action", manager.isRunning)
            await settle(400)
            check("action writes into its own extension", storage.localStorageValue(extension: "first", key: "clicked")
                  == .string("left-click") && storage.localStorageValue(extension: "second", key: "clicked") == nil)
            check("action snapshot updates before unloading",
                  manager.store.records[firstRef.entryID]?.snapshot?.title == "Updated"
                  && !manager.isRunning && lastRuntime == nil)
        } else { check("refresh action exists", false) }

        controller.menuWillOpen(controller.menu)
        await settle(200)
        let beforeReopen = boots.count
        if let index = controller.menu.items.firstIndex(where: { $0.title == "Refresh" }) {
            controller.menuDidClose(controller.menu)
            controller.menu.performActionForItem(at: index)
            await settle(100)
            controller.menuWillOpen(controller.menu)
            check("reopening preserves an unfinished action's runtime", boots.count == beforeReopen)
            controller.menu.performActionForItem(at: index)
            controller.menuDidClose(controller.menu)
        } else { check("refresh exists after reopening", false) }
        let secondRef = ExtensionCommandRef(extensionName: "second", commandName: "bar")
        manager.store.set(.init(), for: secondRef.entryID)
        let secondController = manager.controller(for: secondRef, owner: second)
        secondController.menuWillOpen(secondController.menu)
        await settle(350)
        check("another menu waits for every overlapping action", boots.count == beforeReopen && manager.isRunning)
        await settle(550)
        check("both actions finish before the queued menu opens", boots.last?.0 == "second"
              && storage.localStorageValue(extension: "first", key: "completed") == .number(2))
        secondController.menuDidClose(secondController.menu)
        await settle(200)
        check("reopened action sessions unload after closing", !manager.isRunning && lastRuntime == nil)

        controller.menuWillOpen(controller.menu)
        await settle(200)
        manager.run(second, command: second.manifest.commands[0], arguments: ["value": "kept"],
                    type: .background, context: ["origin": .string("payload")])
        var secondRecord = manager.store.records[secondRef.entryID]!
        secondRecord.nextRefresh = .distantPast
        manager.store.set(secondRecord, for: secondRef.entryID)
        manager.synchronize(installed)
        await settle(100)
        controller.menuDidClose(controller.menu)
        await settle(550)
        check("scheduled refresh preserves an explicit background launch's payload",
              storage.localStorageValue(extension: "second", key: "launch") == .string("background:kept:payload")
              && !manager.isRunning)

        var record = manager.store.records[firstRef.entryID]!
        record.nextRefresh = .distantPast
        manager.store.set(record, for: firstRef.entryID)
        manager.synchronize(installed)
        await settle(450)
        check("overdue refresh runs with background launch type", boots.last?.1 == .background)
        check("background refresh unloads", !manager.isRunning && lastRuntime == nil)
        let restored = ExtensionMenuBarStore(file: directory.appendingPathComponent("bars.json"))
        check("button snapshot survives restart", restored.records == manager.store.records)
        let bootCount = boots.count
        manager.stop()
        manager.synchronize(installed)
        await settle(150)
        check("restoring a saved item executes no JavaScript", boots.count == bootCount)

        manager.run(first, command: first.manifest.commands[0])
        manager.run(second, command: second.manifest.commands[0])
        await settle(750)
        check("queued refreshes finish serially", boots.suffix(2).map(\.0) == ["first", "second"] && !manager.isRunning)
        manager.run(empty, command: empty.manifest.commands[0])
        await settle(300)
        check("null removes item without forgetting activation", manager.store.records["extension:empty/bar"] != nil
              && manager.store.records["extension:empty/bar"]?.snapshot == nil && !manager.isRunning)
        let (foreground, _, recorder) = makeRuntime()
        defer { foreground.shutdown() }
        try? await foreground.boot(config: .current(supportDirectory: directory))
        await foreground.start(session: "foreground", code: #"""
            const React = require("react");
            const { Detail } = require("@raycast/api");
            module.exports.default = () => {
              const [count, setCount] = React.useState(0);
              React.useEffect(() => { setInterval(() => setCount(value => value + 1), 40); }, []);
              return React.createElement(Detail, { markdown: String(count) });
            };
            """#, file: directory.appendingPathComponent("foreground.js"), mode: .view, context: launchContext())
        await settle(100)
        let foregroundRenders = recorder.trees.count
        manager.run(job, command: job.manifest.commands[0], type: .background, context: ["origin": .string("menu")])
        await settle(300)
        check("background no-view receives scoped context", storage.localStorageValue(extension: "job", key: "context")
              == .string("background:menu") && !manager.isRunning && lastRuntime == nil)
        check("no-view launch creates no menu snapshot", manager.store.records["extension:job/bar"] == nil)
        manager.run(first, command: first.manifest.commands[0], type: .background)
        await settle(300)
        check("foreground keeps rendering during background commands", recorder.trees.count > foregroundRenders + 3
              && recorder.failures.isEmpty && !manager.isRunning)
        foreground.shutdown()

        manager.run(hanging, command: hanging.manifest.commands[0])
        await settle(150)
        manager.disable("extension:hanging/bar")
        await settle(150)
        check("disable cancels host requests", hosts.last?.didCancel == true && lastRuntime == nil)
        check("disable removes snapshot and schedule", manager.store.records["extension:hanging/bar"] == nil)
        manager.run(hanging, command: hanging.manifest.commands[0])
        await settle(1250)
        check("loading timeout releases runtime", !manager.isRunning && lastRuntime == nil
              && failures.last?.contains("timed out") == true)
        manager.synchronize([])
        check("uninstall prunes every menu and schedule", manager.store.records.isEmpty && !manager.isRunning)
    }
}
