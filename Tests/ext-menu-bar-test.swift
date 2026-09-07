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
            supportDirectory: directory.appendingPathComponent("support"),
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
        manager.activate(owner, command: command)
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tinycast-menu-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ExtensionStorage(directory: directory.appendingPathComponent("storage"))
        let source = #"""
            const React = require("react");
            const { MenuBarExtra, LocalStorage, environment } = require("@raycast/api");
            module.exports.default = function() {
              const [loading, setLoading] = React.useState(true);
              const [title, setTitle] = React.useState(environment.launchType);
              React.useEffect(() => { const timer = setTimeout(() => setLoading(false), 50);
                return () => clearTimeout(timer); }, []);
              return React.createElement(MenuBarExtra, { title, isLoading: loading, icon: "raycast-star" },
                React.createElement(MenuBarExtra.Section, { title: "Usage" },
                  React.createElement(MenuBarExtra.Item, { title: "Information", subtitle: "Details", tooltip: "Tip" }),
                  React.createElement(MenuBarExtra.Item, { title: "Refresh", shortcut: { key: "r", modifiers: ["cmd"] },
                    alternate: React.createElement(MenuBarExtra.Item, { title: "Alternate", onAction() {} }),
                    onAction: async event => {
                      await new Promise(resolve => setTimeout(resolve, 250));
                      await LocalStorage.setItem("clicked", event.type);
                      setTitle("Updated");
                    } }),
                  React.createElement(MenuBarExtra.Submenu, { title: "Empty" }),
                  React.createElement(MenuBarExtra.Submenu, { title: "Nested" },
                    React.createElement(MenuBarExtra.Item, { title: "Child", onAction() {} }))));
            };
            """#
        func owner(_ name: String, code: String) -> InstalledExtension {
            let path = directory.appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try? code.write(to: path.appendingPathComponent("bar.js"), atomically: true, encoding: .utf8)
            let manifest = ExtensionManifest(json: ["name": name, "commands": [
                ["name": "bar", "title": "Bar", "mode": "menu-bar", "interval": "10m", "disabledByDefault": true]
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
        let installed = [first, second, empty, hanging]
        let firstRef = ExtensionCommandRef(extensionName: "first", commandName: "bar")
        var boots: [(String, ExtensionLaunchType)] = []
        var failures: [String] = []
        var hosts: [MenuHost] = []
        weak var lastRuntime: ExtensionRuntime?
        let manager = ExtensionMenuBarManager(
            storage: storage, file: directory.appendingPathComponent("bars.json"),
            supportDirectory: directory.appendingPathComponent("support"), executionTimeout: .seconds(1),
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
        manager.activate(first, command: first.manifest.commands[0])
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
        check("informational row is disabled", items.first { $0.title == "Information" }?.isEnabled == false)
        check("native subtitle and tooltip", items.first { $0.title == "Information" }?.subtitle == "Details"
              && items.first { $0.title == "Information" }?.toolTip == "Tip")
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

        manager.activate(first, command: first.manifest.commands[0])
        manager.activate(second, command: second.manifest.commands[0])
        await settle(750)
        check("queued refreshes finish serially", boots.suffix(2).map(\.0) == ["first", "second"] && !manager.isRunning)
        manager.activate(empty, command: empty.manifest.commands[0])
        await settle(300)
        check("null removes item without forgetting activation", manager.store.records["extension:empty/bar"] != nil
              && manager.store.records["extension:empty/bar"]?.snapshot == nil && !manager.isRunning)
        manager.activate(hanging, command: hanging.manifest.commands[0])
        await settle(150)
        manager.disable("extension:hanging/bar")
        await settle(150)
        check("disable cancels host requests", hosts.last?.didCancel == true && lastRuntime == nil)
        check("disable removes snapshot and schedule", manager.store.records["extension:hanging/bar"] == nil)
        manager.activate(hanging, command: hanging.manifest.commands[0])
        await settle(1250)
        check("loading timeout releases runtime", !manager.isRunning && lastRuntime == nil
              && failures.last?.contains("timed out") == true)
        manager.synchronize([])
        check("uninstall prunes every menu and schedule", manager.store.records.isEmpty && !manager.isRunning)
    }
}
