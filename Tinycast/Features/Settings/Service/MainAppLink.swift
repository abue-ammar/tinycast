import Foundation

/// Settings' line to the main app: the work only the main app can do, and what only it knows.
@MainActor
@Observable
final class MainAppLink {
    private(set) var status = MainAppStatus()
    @ObservationIgnored private(set) lazy var extensions = ExtensionLibrary(mainApp: self)

    @ObservationIgnored private let link: ProcessLink<SettingsWire.ToMainApp, SettingsWire.ToSettings>
    @ObservationIgnored private let mirror: SharedStateMirror
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var calls: [UUID: (ExtensionCallEvent) -> Void] = [:]
    @ObservationIgnored private var mcpCalls: [UUID: CheckedContinuation<MCPSettingsResult, Never>] = [:]

    init(
        link: ProcessLink<SettingsWire.ToMainApp, SettingsWire.ToSettings>,
        mirror: (@escaping (SharedChange) -> Void) -> SharedStateMirror, core: AppCore
    ) {
        self.link = link
        self.mirror = mirror { [weak link] in link?.send(.changed($0)) }
        self.core = core
    }

    func start() {
        link.onReceive = { [weak self] in self?.receive($0) }
        // The main app quit, relaunched or crashed; without it, Settings edits nothing live.
        link.onClose = { [weak self] in self?.didClose() }
        link.start()
        mirror.start()
        observeRecording()
    }

    /// State goes first, so the main app acts on what the pane just changed.
    func send(_ action: SettingsAction) {
        mirror.flush()
        link.send(.perform(action))
    }

    /// Cancelling the waiting task cancels the main app's work too, as an in-process call would.
    func call(
        _ call: ExtensionCall, onEvent: @escaping (ExtensionCallEvent) -> Void = { _ in }
    ) async -> ExtensionCallResult {
        mirror.flush()
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                calls[id] = { [weak self] event in
                    guard case .finished(let result) = event else { return onEvent(event) }
                    self?.calls[id] = nil
                    continuation.resume(returning: result)
                }
                link.send(.call(id, call))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.link.send(.cancelCall(id)) }
        }
    }

    @discardableResult
    func callMCP(_ call: MCPSettingsCall) async throws -> MCPServerStatus? {
        try Task.checkCancellation()
        mirror.flush()
        let id = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                mcpCalls[id] = continuation
                link.send(.mcpCall(id, call))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.link.send(.cancelCall(id)) }
        }
        try Task.checkCancellation()
        return try result.get()
    }

    private func didClose() {
        let waiting = mcpCalls.values
        mcpCalls.removeAll()
        for continuation in waiting { continuation.resume(returning: .cancelled) }
        core.terminate()
    }

    func open(_ url: URL) {
        link.send(.openURL(url))
    }

    /// The last changes before exit; the link blocks until they are in the pipe.
    func flush() {
        mirror.flush()
        link.flush()
    }

    private func receive(_ message: SettingsWire.ToSettings) {
        switch message {
        case .show(let request):
            core.settingsCoordinator.show(request)
            link.send(.activate)
        case .changed(let change):
            mirror.apply(change)
        case .callEvent(let id, let event):
            calls[id]?(event)
        case .mcpResult(let id, let result):
            mcpCalls.removeValue(forKey: id)?.resume(returning: result)
        case .status(let status):
            self.status = status
            core.appIndex.adoptCommands(hidden: status.hiddenCommands, unlisted: status.unlistedCommands)
            core.hotKeys.capture.hyperRoute = status.hyperKey.route
            core.hotKeys.modifierTapMonitor.adoptNeedsAccessibility(status.modifierTapsNeedAccessibility)
        }
    }

    private func observeRecording() {
        let isRecording = withObservationTracking {
            core.hotKeys.recordingAction != nil
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeRecording() }
        }
        link.send(.recordingShortcut(isRecording))
    }
}
