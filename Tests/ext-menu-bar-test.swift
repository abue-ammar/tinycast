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
            makeExecution: { _, _, _ in
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
            let cachedActions = controller.menu.items.filter { $0.action != nil }
            check("cycle \(cycle) cached actions are bright before boot", !cachedActions.isEmpty
                  && cachedActions.allSatisfy { $0.isEnabled && $0.representedObject == nil })
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
        if let index = controller.menu.items.firstIndex(where: { $0.title == "Open Provider Usage" }) {
            controller.menuDidClose(controller.menu)
            controller.menu.performActionForItem(at: index)
            for _ in 0..<200 where manager.isRunning { await settle(50) }
            check("real command queues an immediate launchCommand click",
                  hosts.last?.calls.contains("system.launchCommand") == true
                  && !manager.isRunning && lastRuntime == nil)
        }
        print("\(passes) passed, \(failures) failed; \(boots) fresh contexts")
    }

    @MainActor
    static func menuBarRenderingChecks() async {
        let controller = ExtensionMenuBarController(entryID: "tinycast-fixture-rendering", assetsPath: "/tmp", isVisible: false)
        defer { controller.remove() }
        controller.menuWillOpen(controller.menu)
        check("opening callback does not change menu structure", controller.menu.items.isEmpty)
        controller.menuDidClose(controller.menu)
        controller.menuNeedsUpdate(controller.menu)
        let placeholder = controller.menu.items.first
        check("cold menu has content before opening", placeholder?.title == "Loading…"
              && placeholder?.isEnabled == false && !controller.isOpen)
        controller.menuNeedsUpdate(controller.menu)
        check("repeated native preparation keeps one placeholder", controller.menu.items.count == 1
              && controller.menu.items.first === placeholder)
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
        controller.menuNeedsUpdate(controller.menu)
        check("native preparation preserves cached content", controller.menu.items.first === item)
        check("menu is prepared while closed", item?.title == "Weekly · 17% resets in 5d" && item?.image?.size.width == 14,
              "title=\(item?.title ?? "nil") image=\(String(describing: item?.image?.size))")
        check("menu contains only extension rows", controller.menu.items.count == 1)
        check("macOS named shortcut maps to native key", item?.keyEquivalent == "\u{f72d}"
              && item?.keyEquivalentModifierMask == .command)
        check("closed menu has inline secondary text", item?.attributedTitle?.string == "Weekly · 17% resets in 5d"
              && item?.subtitle == nil)
        controller.clearMenu()
        check("unloading preserves action appearance without callbacks",
              item?.representedObject == nil && item?.isEnabled == true)
        controller.menuWillOpen(controller.menu)
        check("opening keeps prepared rows", controller.menu.items.first === item)
        let loading = RenderNode(id: 3, type: "MenuBarExtra", props: ["isLoading": .bool(true)], children: [])
        controller.showMenu(loading, session: "two")
        check("loading keeps settled actions bright", controller.menu.items.first === item && item?.isEnabled == true)
        controller.showMenu(root, session: "two")
        check("fresh session rebinds existing rows", controller.menu.items.first === item
              && item?.representedObject != nil && item?.isEnabled == true)
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
    static func menuBarPendingActionChecks() {
        let controller = ExtensionMenuBarController(entryID: "tinycast-fixture-pending-action", assetsPath: "/tmp",
                                                     isVisible: false)
        defer { controller.remove() }
        var dispatched: [String] = []
        var opens = 0
        var unavailable = 0
        controller.onAction = { dispatched.append("\($0):\($1):\($2)") }
        controller.onOpen = { opens += 1 }
        controller.onActionUnavailable = { unavailable += 1 }
        func root(_ id: Int, title: String = "Run", duplicate: Bool = false) -> RenderNode {
            let rows = (0..<(duplicate ? 2 : 1)).map { index in
                RenderNode(id: id + index, type: "MenuBarExtra.Item", props: [
                    "title": .string(title), "onAction": .handler("handler-\(id + index)")
                ])
            }
            return RenderNode(id: id + 2, type: "MenuBarExtra", children: [
                RenderNode(id: id + 3, type: "MenuBarExtra.Section", props: ["title": .string("Section")], children: [
                    RenderNode(id: id + 4, type: "MenuBarExtra.Submenu", props: ["title": .string("Nested")], children: rows)
                ])
            ])
        }
        func click() {
            let submenu = controller.menu.items.first { $0.submenu != nil }?.submenu
            check("cached submenu has a usable action", submenu?.items.first?.isEnabled == true)
            submenu?.performActionForItem(at: 0)
        }
        controller.showMenu(root(10), session: "old")
        controller.clearMenu()
        click()
        check("cached clicks request a runtime without using stale handlers", dispatched.isEmpty && opens == 1)
        controller.showMenu(RenderNode(id: 1, type: "MenuBarExtra", props: ["isLoading": .bool(true)]), session: "new")
        check("cached click survives loading renders", dispatched.isEmpty)
        controller.showMenu(root(100), session: "new")
        check("pending click binds to the fresh handler despite new node IDs", dispatched == ["new:handler-100:left-click"])
        controller.showMenu(root(100), session: "new")
        check("pending click dispatches only once", dispatched.count == 1)

        controller.clearMenu()
        click()
        controller.showMenu(root(100, title: "Different"), session: "changed")
        check("a reused node ID cannot redirect a cached click", dispatched.count == 1 && unavailable == 1)
        controller.showMenu(root(200), session: "before-duplicates")
        controller.clearMenu()
        click()
        controller.showMenu(root(300, duplicate: true), session: "duplicates")
        check("ambiguous fresh actions are rejected", dispatched.count == 1 && unavailable == 2)
        controller.clearMenu()
        let before = opens
        click()
        check("ambiguous cached actions are rejected before queuing", opens == before && unavailable == 3)

        controller.showMenu(root(400), session: "before-error")
        controller.clearMenu()
        click()
        controller.showError("Fixture failure")
        controller.showMenu(root(500), session: "after-error")
        check("failed refreshes discard pending clicks", dispatched.count == 1)
        controller.clearMenu()
        click()
        controller.clearMenu()
        controller.showMenu(root(600), session: "after-cancel")
        check("shutdown discards pending clicks", dispatched.count == 1)

        func section(_ name: String) -> RenderNode {
            RenderNode(id: 1, type: "MenuBarExtra", children: [
                RenderNode(id: 2, type: "MenuBarExtra.Section", props: ["title": .string(name)], children: [
                    RenderNode(id: 3, type: "MenuBarExtra.Separator"),
                    RenderNode(id: 4, type: "MenuBarExtra.Item", props: [
                        "title": .string("Open"), "onAction": .handler(name)
                    ])
                ])
            ])
        }
        controller.showMenu(section("Account A"), session: "account-a")
        controller.clearMenu()
        controller.menu.performActionForItem(at: 2)
        controller.showMenu(section("Account B"), session: "account-b")
        check("separators cannot hide a changed section from queued clicks", dispatched.count == 1 && unavailable == 4)

        func alternate(_ primary: String) -> RenderNode {
            RenderNode(id: 1, type: "MenuBarExtra", children: [
                RenderNode(id: 2, type: "MenuBarExtra.Item", props: [
                    "title": .string(primary), "onAction": .handler(primary),
                    "alternate": .node(RenderNode(id: 3, type: "MenuBarExtra.Item", props: [
                        "title": .string("Reveal in Finder"), "onAction": .handler("reveal-" + primary)
                    ]))
                ])
            ])
        }
        controller.showMenu(alternate("Open File A"), session: "file-a")
        controller.clearMenu()
        controller.menu.performActionForItem(at: 1)
        controller.showMenu(alternate("Open File B"), session: "file-b")
        check("alternate clicks retain their primary item's identity", dispatched.count == 1 && unavailable == 5)
    }

    @MainActor
    static func menuBarImageChecks() async {
        var pending: [CheckedContinuation<NSImage?, Never>] = []
        let controller = ExtensionMenuBarController(entryID: "tinycast-fixture-slow-image", assetsPath: "/tmp",
                                                     isVisible: false, loadImage: { _, _, _ in
            await withCheckedContinuation { pending.append($0) }
        })
        defer { controller.remove() }
        func root(_ icon: String) -> RenderNode {
            RenderNode(id: 1, type: "MenuBarExtra", children: [
                RenderNode(id: 2, type: "MenuBarExtra.Submenu", props: ["title": .string("Actions")], children: [
                    RenderNode(id: 3, type: "MenuBarExtra.Item", props: [
                        "title": .string("Run"), "icon": .string(icon), "onAction": .handler("run")
                    ])
                ])
            ])
        }
        controller.showMenu(root("slow"), session: "one")
        let item = controller.menu.items.first?.submenu?.items.first
        let placeholder = item?.image
        check("slow icons do not block text or actions", item?.title == "Run" && item?.isEnabled == true
              && item?.representedObject != nil && placeholder?.size.width == 14)
        await settle(20)
        controller.showMenu(root("new"), session: "one")
        let oldImage = NSImage(size: NSSize(width: 14, height: 14))
        pending.removeFirst().resume(returning: oldImage)
        await settle(20)
        check("obsolete icon replies cannot replace current artwork", item?.image === placeholder && pending.count == 1)
        controller.clearMenu()
        check("unloading preserves submenu action appearance", item?.isEnabled == true && item?.representedObject == nil)
        let newImage = NSImage(size: NSSize(width: 14, height: 14))
        pending.removeFirst().resume(returning: newImage)
        await settle(20)
        check("late images update rows without restoring expired callbacks", item?.image === newImage
              && item?.isEnabled == true && item?.representedObject == nil)

        var attempts: [CGFloat: Int] = [:]
        let retry = ExtensionMenuBarController(entryID: "tinycast-fixture-retry-image", assetsPath: "/tmp",
                                                isVisible: false, loadImage: { _, _, size in
            attempts[size, default: 0] += 1
            return attempts[size] == 1 ? nil : NSImage(size: NSSize(width: size, height: size))
        })
        defer { retry.remove() }
        let snapshot = ExtensionMenuBarSnapshot(node: RenderNode(id: 0, type: "MenuBarExtra", props: [
            "icon": .string("retry"), "title": .string("Usage")
        ], children: root("retry").children))
        retry.update(snapshot)
        retry.showMenu(root("retry"), session: "one")
        await settle(20)
        for _ in 0..<20 {
            retry.update(snapshot)
            retry.showMenu(root("retry"), session: "one")
        }
        await settle(20)
        check("failed icons are attempted once per session", attempts[14] == 1 && attempts[18] == 1)
        retry.clearMenu()
        retry.showMenu(root("retry"), session: "two")
        await settle(20)
        check("next session retries unchanged menu and status icons", attempts[14] == 2 && attempts[18] == 2)
        retry.clearMenu()
        retry.showMenu(root("retry"), session: "three")
        await settle(20)
        check("successful icons remain cached across sessions", attempts[14] == 2 && attempts[18] == 2)
        retry.showMenu(root("other"), session: "three")
        await settle(20)
        retry.showMenu(root("retry"), session: "three")
        let returningPlaceholder = retry.menu.items.first?.submenu?.items.first?.image
        await settle(20)
        check("returning to an evicted icon reloads it in the same session", attempts[14] == 4
              && retry.menu.items.first?.submenu?.items.first?.image !== returningPlaceholder)
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
        var isInteractive = false

        init(name: String, storage: ExtensionStorage) {
            self.name = name
            self.storage = storage
        }

        func perform(api: String, method: String, arguments: [RenderValue]) async throws -> String {
            if api == "feedback", method == "confirmAlert" { return isInteractive ? "true" : "false" }
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
        menuBarPendingActionChecks()
        await menuBarImageChecks()
        await lateMenuResponseChecks()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tinycast-menu-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ExtensionStorage(directory: directory.appendingPathComponent("storage"))
        let source = #"""
            const React = require("react");
            const { MenuBarExtra, LocalStorage, environment, confirmAlert } = require("@raycast/api");
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
                  React.createElement(MenuBarExtra.Item, { title: "Confirm", onAction: async () => {
                    await LocalStorage.setItem("confirmed", await confirmAlert({ title: "Continue?" }));
                  } }),
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
            makeExecution: { owner, _, type in
                boots.append((owner.manifest.name, type))
                let host = MenuHost(name: owner.manifest.name, storage: storage)
                host.isInteractive = type == .userInitiated
                hosts.append(host)
                let runtime = ExtensionRuntime(hostAPI: host, runtimeURL: runtimeURL())
                lastRuntime = runtime
                return .init(runtime: runtime, stop: {}, enableInteraction: { host.isInteractive = true })
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

        manager.run(first, command: first.manifest.commands[0], type: .background)
        let backgroundBoots = boots.count
        check("background hosts begin without interactive prompts", hosts.last?.isInteractive == false)
        controller.menuWillOpen(controller.menu)
        await settle(200)
        check("opening promotes the existing background host", boots.count == backgroundBoots
              && hosts.last?.isInteractive == true)
        if let index = controller.menu.items.firstIndex(where: { $0.title == "Confirm" }) {
            controller.menuDidClose(controller.menu)
            controller.menu.performActionForItem(at: index)
            await settle(250)
            check("actions can confirm after opening a background refresh",
                  storage.localStorageValue(extension: "first", key: "confirmed") == .bool(true) && !manager.isRunning)
        } else { check("confirmation action exists", false) }

        storage.setLocalStorage(extension: "first", key: "confirmed", value: .bool(false))
        let beforeEarlyClick = boots.count
        controller.menuWillOpen(controller.menu)
        if let index = controller.menu.items.firstIndex(where: { $0.title == "Confirm" }) {
            let item = controller.menu.items[index]
            check("opening a cached menu keeps actions bright before boot", item.isEnabled && item.representedObject == nil)
            controller.menuDidClose(controller.menu)
            controller.menu.performActionForItem(at: index)
            await settle(400)
            check("clicking immediately after opening runs the fresh action and unloads",
                  storage.localStorageValue(extension: "first", key: "confirmed") == .bool(true)
                  && boots.count == beforeEarlyClick + 1 && !manager.isRunning && lastRuntime == nil)
        } else { check("early confirmation action exists", false) }

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

/// The headless refresh lane: what one run reports, and what a preempted one must not.
@MainActor
enum ExtensionBackgroundSessionTests {
    static func runChecks(_ check: (String, Bool, String) -> Void) async {
        let reference = ExtensionCommandRef(extensionName: "coffee", commandName: "status")

        // A fast command used to finish before anyone waited, and then record a timeout instead.
        let early = ExtensionBackgroundSession(reference: reference)
        early.complete(.success)
        var outcome = await early.wait(timeout: 0.05)
        check("a run that finished before the wait still reports success", outcome == .success, "")

        let failed = ExtensionBackgroundSession(reference: reference)
        failed.complete(.failure("TypeError: x"))
        outcome = await failed.wait(timeout: 0.05)
        check("a synchronous failure keeps its own message", outcome.error == "TypeError: x", "")

        let hung = ExtensionBackgroundSession(reference: reference)
        outcome = await hung.wait(timeout: 0.05)
        check("a run that never settles times out", outcome == .failure("Timed out."), "")
        hung.complete(.success)
        check("a late success cannot rewrite the timeout", hung.outcome == .failure("Timed out."), "")

        let aborted = ExtensionBackgroundSession(reference: reference)
        aborted.complete(.cancelled)
        outcome = await aborted.wait(timeout: 0.05)
        check("a preempted run records neither success nor failure",
              outcome == .cancelled && outcome.error == nil, "")

        await realCommandChecks(check)
    }

    /// End to end through JavaScriptCore, wired the way `runInBackground` wires it.
    static func realCommandChecks(_ check: (String, Bool, String) -> Void) async {
        let reference = ExtensionCommandRef(extensionName: "fixture", commandName: "status")
        let cases: [(String, String, ExtensionBackgroundSession.Outcome)] = [
            ("a command that returns settles as a success",
             "module.exports.default = async function() { return; };", .success),
            ("a command that throws settles as its own failure",
             "module.exports.default = async function() { throw new Error('boom'); };",
             .failure("boom"))
        ]
        for (label, body, expected) in cases {
            let session = ExtensionBackgroundSession(reference: reference)
            let relay = BackgroundRelay(session: session)
            let runtime = ExtensionRuntime(
                hostAPI: StubBackgroundHost(), runtimeURL: ExtensionTests.runtimeURL())
            defer { runtime.shutdown() }
            runtime.setDelegate(relay)
            try? await runtime.boot(config: ExtensionBootConfig.current(
                supportDirectory: FileManager.default.temporaryDirectory))
            var context = ExtensionLaunchContext(
                extensionName: reference.extensionName, extensionTitle: reference.extensionName,
                commandName: reference.commandName, commandMode: ExtensionCommandMode.noView,
                assetsPath: "/tmp",
                supportPath: "/tmp", preferences: [:], caches: [:], arguments: [:],
                fallbackText: nil, isDarkAppearance: true)
            context.launchType = .background
            await runtime.start(
                session: session.id, code: body, file: URL(fileURLWithPath: "/tmp/status.js"),
                mode: ExtensionCommandMode.noView, context: context)
            // The whole point: a fast command settles before anyone waits, and must still report.
            let outcome = await session.wait(timeout: 5)
            let matched: Bool
            switch (outcome, expected) {
            case (.success, .success): matched = true
            case (.failure(let actual), .failure(let wanted)): matched = actual.contains(wanted)
            default: matched = false
            }
            check(label, matched, "got \(outcome)")
        }
    }
}

/// Routes the runtime callbacks into one background session, exactly as `ExtensionManager` does.
@MainActor
private final class BackgroundRelay: ExtensionRuntimeDelegate {
    private let session: ExtensionBackgroundSession

    init(session: ExtensionBackgroundSession) { self.session = session }

    func runtime(_ runtime: ExtensionRuntime, session id: String, didRender tree: RenderTree) {}
    func runtime(_ runtime: ExtensionRuntime, session id: String, navigationDepth: Int) {}
    func runtime(_ runtime: ExtensionRuntime, log level: String, message: String) {}

    func runtime(_ runtime: ExtensionRuntime, session id: String, didFail message: String) {
        guard id == session.id else { return }
        session.complete(.failure(message))
    }

    func runtime(_ runtime: ExtensionRuntime, session id: String, didFinish: Void) {
        guard id == session.id else { return }
        session.complete(.success)
    }
}

@MainActor
private final class StubBackgroundHost: ExtensionHostAPI {
    func perform(api: String, method: String, arguments: [RenderValue]) async throws -> String { "" }
    func sessionEnded() {}
}
