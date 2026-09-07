import AppKit
import os

@MainActor
final class ExtensionMenuBarManager: ExtensionRuntimeDelegate {
    let store: ExtensionMenuBarStore
    private let storage: ExtensionStorage
    private let supportDirectory: URL
    private let executionTimeout: Duration
    private let showsStatusItems: Bool
    private let makeExecution: (InstalledExtension, ExtensionLaunchType) -> Execution?
    private let onError: (String, InstalledExtension, Bool) -> Void
    private var installed: [InstalledExtension] = []
    private var controllers: [String: ExtensionMenuBarController] = [:]
    private var requests: [Request] = []
    private var active: Session?
    private var launchTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    struct Execution {
        let runtime: ExtensionRuntime
        var stop: () -> Void
    }

    var isRunning: Bool { active != nil }

    private struct Request {
        let reference: ExtensionCommandRef
        var type: ExtensionLaunchType = .background
        var arguments: [String: String] = [:]
        var context: [String: RenderValue] = [:]
    }

    private final class Session {
        let id = UUID().uuidString
        let request: Request
        let owner: InstalledExtension
        let mode: ExtensionCommandMode
        let execution: Execution
        var runtime: ExtensionRuntime { execution.runtime }
        var isLoading = true
        var actionRunning = false

        init(request: Request, owner: InstalledExtension, mode: ExtensionCommandMode, execution: Execution) {
            self.request = request
            self.owner = owner
            self.mode = mode
            self.execution = execution
        }
    }

    init(storage: ExtensionStorage, file: URL, supportDirectory: URL, executionTimeout: Duration = .seconds(60),
         showsStatusItems: Bool = true,
         makeExecution: @escaping (InstalledExtension, ExtensionLaunchType) -> Execution?,
         onError: @escaping (String, InstalledExtension, Bool) -> Void) {
        self.storage = storage
        self.supportDirectory = supportDirectory
        self.executionTimeout = executionTimeout
        self.showsStatusItems = showsStatusItems
        self.makeExecution = makeExecution
        self.onError = onError
        store = ExtensionMenuBarStore(file: file)
    }

    func synchronize(_ installed: [InstalledExtension]) {
        self.installed = installed
        for (entryID, record) in store.records {
            guard let reference = ExtensionCommandRef(entryID: entryID), let (owner, command) = resolve(reference),
                command.mode == .menuBar
            else {
                disable(entryID)
                continue
            }
            if let snapshot = record.snapshot { controller(for: reference, owner: owner).update(snapshot) }
        }
        scheduleRefresh()
    }

    func run(_ owner: InstalledExtension, command: ExtensionCommand, arguments: [String: String] = [:],
             type: ExtensionLaunchType = .userInitiated, context: [String: RenderValue] = [:]) {
        let reference = ExtensionCommandRef(extensionName: owner.manifest.name, commandName: command.name)
        if command.mode == .menuBar, store.records[reference.entryID] == nil {
            store.set(.init(), for: reference.entryID)
        }
        enqueue(Request(reference: reference, type: type, arguments: arguments, context: context))
    }

    func disable(_ entryID: String) {
        requests.removeAll { $0.reference.entryID == entryID }
        controllers.removeValue(forKey: entryID)?.remove()
        store.set(nil, for: entryID)
        if active?.request.reference.entryID == entryID { finish() }
        runNext()
        scheduleRefresh()
    }

    func remove(extensionName: String) {
        requests.removeAll { $0.reference.extensionName == extensionName }
        if active?.owner.manifest.name == extensionName { finish() }
        for entryID in store.records.keys where ExtensionCommandRef(entryID: entryID)?.extensionName == extensionName {
            disable(entryID)
        }
        runNext()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        requests.removeAll()
        finish()
        for controller in controllers.values { controller.remove() }
        controllers.removeAll()
        installed = []
    }

    private func resolve(_ reference: ExtensionCommandRef) -> (InstalledExtension, ExtensionCommand)? {
        guard let owner = installed.first(where: { $0.manifest.name == reference.extensionName }),
            let command = owner.command(named: reference.commandName)
        else { return nil }
        return (owner, command)
    }

    private func enqueue(_ request: Request) {
        requests.removeAll { $0.reference == request.reference }
        requests.append(request)
        if active == nil { runNext() }
    }

    private func runNext() {
        guard active == nil, !requests.isEmpty else { return }
        let request = requests.removeFirst()
        let entryID = request.reference.entryID
        guard let (owner, command) = resolve(request.reference),
            command.mode == .noView || store.records[entryID] != nil
        else { runNext(); return }
        if command.mode == .menuBar {
            var record = store.records[entryID] ?? .init()
            record.nextRefresh = command.interval.map { Date().addingTimeInterval($0) }
            store.set(record, for: entryID)
            scheduleRefresh()
        }

        let missing = storage.missingRequiredPreferences(extension: owner.manifest.name,
                                                         schemas: owner.manifest.preferences + command.preferences)
        guard missing.isEmpty, let bundle = owner.bundleURL(for: command) else {
            let message = missing.isEmpty ? ExtensionLaunchError.notBuilt(command.title).localizedDescription
                : ExtensionLaunchError.missingPreferences(missing).localizedDescription
            controllers[entryID]?.showError(message)
            if request.type == .userInitiated {
                onError(message, owner, !missing.isEmpty)
            }
            runNext()
            return
        }
        guard let execution = makeExecution(owner, request.type) else { runNext(); return }
        let runtime = execution.runtime
        runtime.setDelegate(self)
        let session = Session(request: request, owner: owner, mode: command.mode, execution: execution)
        active = session
        let support = supportDirectory.appendingPathComponent(ExtensionCatalog.safeName(owner.manifest.name))
        let context = ExtensionLaunchContext(
            extensionName: owner.manifest.name, extensionTitle: owner.title, commandName: command.name,
            commandMode: command.mode, assetsPath: owner.assetsPath, supportPath: support.path,
            preferences: storage.resolvedPreferences(extension: owner.manifest.name,
                                                     schemas: owner.manifest.preferences + command.preferences),
            caches: storage.caches(extension: owner.manifest.name), arguments: command.completeArguments(request.arguments),
            fallbackText: nil, isDarkAppearance: NSApp.effectiveAppearance.isDark,
            launchType: request.type, launchContext: request.context)
        launchTask = Task { [weak self] in
            do {
                let code = try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                    return try String(contentsOf: bundle, encoding: .utf8)
                }.value
                guard !Task.isCancelled else { return }
                try await runtime.boot(config: .current(supportDirectory: support))
                guard !Task.isCancelled else { runtime.shutdown(); return }
                await runtime.start(session: session.id, code: code, file: bundle, mode: command.mode, context: context)
            } catch {
                self?.runtime(runtime, session: session.id, didFail: error.localizedDescription)
            }
        }
        armDeadline(session)
    }

    func controller(for reference: ExtensionCommandRef, owner: InstalledExtension) -> ExtensionMenuBarController {
        if let controller = controllers[reference.entryID] { return controller }
        let controller = ExtensionMenuBarController(entryID: reference.entryID, assetsPath: owner.assetsPath,
                                                     isVisible: showsStatusItems)
        controller.onOpen = { [weak self] in
            guard let self else { return }
            self.idleTask?.cancel()
            if self.active?.request.reference == reference { self.finish() }
            self.requests.removeAll { $0.reference == reference }
            self.requests.insert(Request(reference: reference, type: .userInitiated), at: 0)
            if self.active != nil { self.finish() }
            self.runNext()
        }
        controller.onClose = { [weak self] in
            guard let self, let active = self.active, active.request.reference == reference else { return }
            self.armDeadline(active)
            self.releaseIfIdle()
        }
        controller.onAction = { [weak self] session, handler, type in
            guard let self, let active = self.active, active.id == session else { return }
            self.idleTask?.cancel()
            active.actionRunning = true
            self.armDeadline(active)
            Task {
                await active.runtime.dispatch(session: session, handler: handler,
                                              payload: ExtensionRuntime.jsonString(from: [["type": type]]),
                                              completesSession: true)
            }
        }
        controllers[reference.entryID] = controller
        return controller
    }

    private func armDeadline(_ session: Session) {
        deadlineTask?.cancel()
        let timeout = executionTimeout
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.active?.id == session.id else { return }
            if self.controllers[session.request.reference.entryID]?.isOpen == true,
                !session.isLoading, !session.actionRunning { return }
            self.runtime(session.runtime, session: session.id, didFail: "The menu bar command timed out.")
        }
    }

    private func releaseIfIdle() {
        idleTask?.cancel()
        guard let active, !active.isLoading, !active.actionRunning,
            controllers[active.request.reference.entryID]?.isOpen != true
        else { return }
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            await active.runtime.drainHostCalls()
            guard !Task.isCancelled, let self, self.active?.id == active.id,
                !active.isLoading, !active.actionRunning,
                self.controllers[active.request.reference.entryID]?.isOpen != true
            else { return }
            self.finish()
            self.runNext()
        }
    }

    private func finish() {
        launchTask?.cancel()
        deadlineTask?.cancel()
        idleTask?.cancel()
        launchTask = nil
        deadlineTask = nil
        idleTask = nil
        guard let session = active else { return }
        active = nil
        session.execution.stop()
        session.runtime.shutdown()
        storage.flush()
        controllers[session.request.reference.entryID]?.clearMenu()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        let dates = store.records.values.compactMap(\.nextRefresh)
        guard let next = dates.min() else { return }
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)), tolerance: .seconds(1)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            let due = self.store.records.filter { ($0.value.nextRefresh ?? .distantFuture) <= Date() }.map(\.key)
            for entryID in due {
                guard let reference = ExtensionCommandRef(entryID: entryID), let (_, command) = self.resolve(reference)
                else { continue }
                var record = self.store.records[entryID] ?? .init()
                record.nextRefresh = command.interval.map { Date().addingTimeInterval($0) }
                self.store.set(record, for: entryID)
                if self.active?.request.reference != reference { self.enqueue(Request(reference: reference)) }
            }
            self.scheduleRefresh()
        }
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, didRender tree: RenderTree) {
        guard let active, active.id == session else { return }
        let reference = active.request.reference
        let root = tree.activeRoot
        guard root == nil || root?.type == "MenuBarExtra" else {
            self.runtime(runtime, session: session, didFail: "A menu bar command must render MenuBarExtra or null.")
            return
        }
        let wasLoading = active.isLoading
        active.isLoading = root?.bool("isLoading") == true
        if !wasLoading, active.isLoading { armDeadline(active) }
        var record = store.records[reference.entryID] ?? .init()
        if let root {
            let snapshot = ExtensionMenuBarSnapshot(node: root)
            let controller = controller(for: reference, owner: active.owner)
            if !active.isLoading || record.snapshot == nil { controller.update(snapshot) }
            controller.showMenu(root, session: session)
            if !active.isLoading { record.snapshot = snapshot }
        } else {
            controllers.removeValue(forKey: reference.entryID)?.remove()
            record.snapshot = nil
        }
        if !active.isLoading { store.set(record, for: reference.entryID) }
        releaseIfIdle()
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, didFail message: String) {
        guard let active, active.id == session else { return }
        controllers[active.request.reference.entryID]?.showError(message)
        if active.request.type == .userInitiated { onError(message, active.owner, false) }
        finish()
        runNext()
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, navigationDepth: Int) {}

    func runtime(_ runtime: ExtensionRuntime, session: String, didFinish: Void) {
        guard let active, active.id == session else { return }
        active.actionRunning = false
        if active.mode == .noView { active.isLoading = false }
        releaseIfIdle()
    }

    func runtime(_ runtime: ExtensionRuntime, log level: String, message: String) {
        if level == "error" {
            Logger(subsystem: "com.tinycast", category: "extension-menu-bar").error("\(message, privacy: .public)")
        }
    }
}
