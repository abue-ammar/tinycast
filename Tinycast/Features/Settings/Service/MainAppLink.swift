import AppKit

/// Settings' line to the main app: the work only the main app can do, and what only it knows.
@MainActor
@Observable
final class MainAppLink {
    private(set) var status = MainAppStatus()

    @ObservationIgnored private let link: ProcessLink<SettingsWire.ToMainApp, SettingsWire.ToSettings>
    @ObservationIgnored private let mirror: SharedStateMirror
    @ObservationIgnored private unowned let core: AppCore
    private enum CloseState {
        case open
        case waiting((() -> Void)?)
        case ready
    }

    @ObservationIgnored private var calls: [UUID: CheckedContinuation<SettingsWire.Reply, Error>] = [:]
    @ObservationIgnored private var closeTimeout: Task<Void, Never>?
    @ObservationIgnored private var closeState = CloseState.open

    private var acceptsRequests: Bool {
        guard case .open = closeState else { return false }
        return link.isOpen
    }

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
        link.onClose = { [weak self] _ in self?.didClose() }
        link.start()
        mirror.start()
        observeRecording()
    }

    /// State goes first, so the main app acts on what the pane just changed.
    func send(_ action: SettingsAction) {
        guard acceptsRequests else { return }
        mirror.flush()
        if action.presentsWindow { yieldFocusToMainApp() }
        link.send(.perform(action))
    }

    /// macOS lets an app come forward only when the active one hands over focus, as this one does.
    private func yieldFocusToMainApp() {
        NSRunningApplication(processIdentifier: getppid())?.activate(from: .current)
    }

    @discardableResult
    func callMCP(_ call: MCPSettingsCall) async throws -> MCPServerStatus? {
        guard case .mcp(let status) = try await request(.mcp(call)) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return status
    }

    func prepareBackup(at url: URL) async throws -> BackupPreview {
        guard case .backupPreview(let preview) = try await request(.backup(.prepare(url))) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return preview
    }

    func runBackup(_ call: BackupSettingsCall) async throws -> String {
        guard case .backupMessage(let message) = try await request(.backup(call)) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return message
    }

    private func request(_ call: SettingsWire.Call) async throws -> SettingsWire.Reply {
        try Task.checkCancellation()
        guard acceptsRequests else { throw SettingsWire.Failure.disconnected }
        mirror.flush()
        let id = UUID()
        let reply = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                calls[id] = continuation
                link.send(.call(id, call))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id) }
        }
        try Task.checkCancellation()
        switch reply {
        case .cancelled: throw CancellationError()
        case .failure(let message): throw SettingsWire.Failure(errorDescription: message)
        default: return reply
        }
    }

    private func cancel(_ id: UUID) {
        link.send(.cancelCall(id))
        calls.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func didClose() {
        let pending = calls.values
        calls.removeAll()
        for call in pending { call.resume(throwing: SettingsWire.Failure.disconnected) }
        if case .open = closeState {
            core.terminate()
        } else {
            finishClosing()
        }
    }

    func open(_ url: URL) {
        link.send(.openURL(url))
    }

    func beginClosing() {
        guard case .open = closeState else { return }
        closeState = .waiting(nil)
        mirror.flush()
        link.send(.closing)
        closeTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.finishClosing()
        }
    }

    func prepareToClose(_ completion: @escaping () -> Void) -> Bool {
        guard link.isOpen else { return false }
        beginClosing()
        guard case .waiting(let registered) = closeState else { return false }
        if registered == nil { closeState = .waiting(completion) }
        return true
    }

    private func finishClosing() {
        guard case .waiting(let completion) = closeState else { return }
        closeState = .ready
        closeTimeout?.cancel()
        closeTimeout = nil
        completion?()
    }

    private func receive(_ message: SettingsWire.ToSettings) {
        switch message {
        case .show(let id, let request):
            guard acceptsRequests else { return }
            core.settingsCoordinator.show(request)
            link.send(.activate(id))
        case .changed(let change):
            mirror.apply(change)
        case .reply(let id, let reply):
            calls.removeValue(forKey: id)?.resume(returning: reply)
        case .readyToClose:
            finishClosing()
        case .status(let status):
            self.status = status
            core.appIndex.adoptCommands(hidden: status.hiddenCommands, unlisted: status.unlistedCommands)
            core.hotKeys.capture.hyperRoute = status.hyperKey.route
            core.hotKeys.modifierTapMonitor.adoptNeedsAccessibility(status.modifierTapsNeedAccessibility)
        }
    }

    private func observeRecording() {
        guard acceptsRequests else { return }
        let isRecording = withObservationTracking {
            core.hotKeys.recordingAction != nil
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeRecording() }
        }
        link.send(.recordingShortcut(isRecording))
    }
}
