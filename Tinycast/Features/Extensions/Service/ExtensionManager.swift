import AppKit

/// Every extension process: one per extension, each checked before it spawns, and none while off.
@MainActor
final class ExtensionManager {
    private struct Run {
        let bundle: ExtensionBundle
        let session: ExtensionSession
    }

    private enum LaunchFailure: Error {
        case needsNewerTinycast
        case invalidSignature
    }

    private(set) var isEnabled = false
    #if DEBUG
        private(set) var isDeveloperModeOn = false
    #endif
    /// Launched, by extension id, until its process is gone.
    private var running: [String: Run] = [:]
    /// The next run of an extension whose previous process is still stopping.
    private var waiting: [String: Run] = [:]
    private let signatures: ExtensionSignatureService
    private let hostCalls: ExtensionHostCallRunner
    private let showMessage: (String, DialogTone) -> Void

    init(
        hostCalls: ExtensionHostCallRunner, showMessage: @escaping (String, DialogTone) -> Void,
        signatures: ExtensionSignatureService = ExtensionSignatureService()
    ) {
        self.hostCalls = hostCalls
        self.showMessage = showMessage
        self.signatures = signatures
    }

    /// Off stops every process and refuses every run.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled { stopRuns(.extensionsOff) { _ in true } }
    }

    #if DEBUG
        func setDeveloperMode(_ on: Bool) {
            guard on != isDeveloperModeOn else { return }
            isDeveloperModeOn = on
            if !on { stopRuns(.closed) { $0.bundle.origin == .developer } }
        }
    #endif

    /// A run the user starts stops the extension's current one; any other run gives way to it.
    @discardableResult
    func run(
        _ bundle: ExtensionBundle, command: String, reason: ExtensionWire.Start.Reason
    ) -> ExtensionSession? {
        guard isEnabled, bundle.manifest.commands.contains(where: { $0.name == command }) else { return nil }
        #if DEBUG
            if bundle.origin == .developer, !isDeveloperModeOn { return nil }
        #endif
        let current = running[bundle.id]
        guard reason == .user || current == nil else { return nil }
        let run = Run(bundle: bundle, session: makeSession(bundle, command: command, reason: reason))
        if let current {
            waiting[bundle.id]?.session.stop(.anotherCommand)
            waiting[bundle.id] = run
            current.session.stop(.anotherCommand)
        } else {
            launch(run)
        }
        return run.session
    }

    private func makeSession(
        _ bundle: ExtensionBundle, command: String, reason: ExtensionWire.Start.Reason
    ) -> ExtensionSession {
        let start = ExtensionWire.Start(
            api: .current, command: command, reason: reason, preferences: [:],
            dataFolder: AppPaths.applicationSupport()
                .appending(path: "ExtensionData/\(bundle.id)", directoryHint: .isDirectory),
            locale: Locale.current.identifier(.bcp47),
            appearance: NSApp.effectiveAppearance.isDark ? .dark : .light)
        let showsUI = reason == .user
        let session = ExtensionSession(
            extensionID: bundle.id, executable: bundle.executableURL, start: start,
            perform: { [hostCalls] in hostCalls.perform($0, showsUI: showsUI) })
        session.onFinish = { [weak self] hud in
            guard showsUI, let hud else { return }
            self?.showMessage(hud, .success)
        }
        session.onGone = { [weak self, weak session] in
            guard let self, let session else { return }
            ended(session)
        }
        return session
    }

    private func launch(_ run: Run) {
        running[run.bundle.id] = run
        do {
            try check(run.bundle)
            try FileManager.default.createDirectory(
                at: run.session.start.dataFolder, withIntermediateDirectories: true)
            try run.session.launch()
        } catch {
            if run.session.start.reason == .user { report(error, for: run.bundle) }
            run.session.stop(.closed)
        }
    }

    /// Before every spawn: this build speaks its protocol, and the bundle is Tinycast's to run.
    private func check(_ bundle: ExtensionBundle) throws(LaunchFailure) {
        guard let api = bundle.manifest.api, ExtensionAPIVersion.current.canRun(api) else {
            throw .needsNewerTinycast
        }
        #if DEBUG
            if bundle.origin == .developer { return }
        #endif
        do {
            try signatures.verify(bundle.url, id: bundle.id)
        } catch {
            throw .invalidSignature
        }
    }

    private func ended(_ session: ExtensionSession) {
        let id = session.extensionID
        guard running[id]?.session === session else { return }
        running[id] = nil
        guard let next = waiting.removeValue(forKey: id) else { return }
        launch(next)
    }

    private func stopRuns(_ reason: ExtensionWire.Stop.Reason, where matches: (Run) -> Bool) {
        let dropped = waiting.filter { matches($0.value) }
        for id in dropped.keys { waiting[id] = nil }
        for run in dropped.values { run.session.stop(reason) }
        for run in running.values where matches(run) { run.session.stop(reason) }
    }

    private func report(_ error: Error, for bundle: ExtensionBundle) {
        let name = bundle.manifest.name
        let message =
            switch error as? LaunchFailure {
            case .needsNewerTinycast: String(localized: "\(name) needs a newer version of Tinycast.")
            case .invalidSignature: String(localized: "\(name) can't run because its signature isn't valid.")
            case nil: String(localized: "\(name) couldn't start.")
            }
        showMessage(message, .danger)
    }
}
