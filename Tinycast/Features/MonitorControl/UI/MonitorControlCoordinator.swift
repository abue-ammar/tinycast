import AppKit
import CoreAudio
import Observation

@MainActor
@Observable
final class MonitorControlCoordinator: HealthCheckable {
    private(set) var displays: [MonitorKeyRouting.Display] = []
    private(set) var status = "Checking connected displays…"
    private(set) var hasPermission = false
    private let settings: AppSettings
    private let ticker: HealthTicker
    @ObservationIgnored private let listener = MonitorMediaKeyListener()
    @ObservationIgnored private var hardware: MonitorHardwareSession?
    @ObservationIgnored private var events: Task<Void, Never>?
    @ObservationIgnored private var results: Task<Void, Never>?
    @ObservationIgnored private var notifications: [NotificationToken] = []
    @ObservationIgnored private var audioListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private let hud: MonitorHUDController
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var nextProbe: Date?
    @ObservationIgnored private var topology = ""
    @ObservationIgnored private var active = false
    @ObservationIgnored private var feedback = MonitorFeedbackState()

    init(settings: AppSettings, ticker: HealthTicker) {
        self.settings = settings
        self.ticker = ticker
        hud = MonitorHUDController(settings: settings)
    }

    func start() {
        guard !active else { return }
        active = true
        applyFineAdjustments()
        let hardware = MonitorHardwareSession()
        self.hardware = hardware
        events = Task { [weak self, listener] in
            for await command in listener.events {
                guard !Task.isCancelled else { break }
                self?.adjust(command)
            }
        }
        results = Task { [weak self] in
            for await result in hardware.results {
                guard !Task.isCancelled else { break }
                self?.receive(result)
            }
        }
        observe(NSApplication.didChangeScreenParametersNotification, center: .default) { coordinator in
            coordinator.reprobe()
        }
        observe(NSWorkspace.willSleepNotification, center: NSWorkspace.shared.notificationCenter) { coordinator in
            coordinator.sleeping = true
            coordinator.reprobe()
        }
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { coordinator in
            coordinator.sleeping = false
            coordinator.reprobe()
        }
        let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateAudioTarget() }
        }
        var address = Self.audioAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, callback) == noErr {
            audioListener = callback
        }
        ticker.subscribe(self)
        reprobe()
    }

    func stop() {
        active = false
        ticker.unsubscribe(self)
        listener.stop()
        hardware?.stop()
        hardware = nil
        events?.cancel()
        results?.cancel()
        events = nil
        results = nil
        notifications.removeAll()
        if let audioListener {
            var address = Self.audioAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, audioListener)
        }
        audioListener = nil
        feedback = MonitorFeedbackState()
        hud.dismiss()
    }

    func applyEnabled() { reprobe() }

    func applyFineAdjustments() {
        listener.routing.withLock { $0.fineAdjustments = settings.externalMonitorFineAdjustments }
    }

    func reprobe() {
        guard active else { return }
        generation &+= 1
        nextProbe = nil
        displays = []
        feedback = MonitorFeedbackState()
        hud.dismiss()
        let screens = currentScreens()
        topology = screenSignature(screens)
        listener.routing.withLock {
            $0.generation = generation
            $0.displays = []
            $0.audioTarget = nil
            $0.enabled = false
            $0.revisions.removeAll()
        }
        let enabled = settings.externalMonitorControlsEnabled && !sleeping
        status = enabled ? "Checking connected displays…" : "External monitor controls are off."
        hardware?.discover(generation: generation, screens: enabled ? screens : [])
        healthCheck()
    }

    func healthCheck() {
        guard active else { return }
        hasPermission = Permissions.isAccessibilityTrusted()
        let signature = screenSignature(currentScreens())
        if signature != topology || (nextProbe.map { $0 <= Date() } ?? false) {
            reprobe()
            return
        }
        let enabled = settings.externalMonitorControlsEnabled && !sleeping && hasPermission
        if enabled {
            let installed = listener.install()
            listener.routing.withLock { $0.enabled = installed }
            if !installed { status = "Keyboard access is unavailable. Check Accessibility permission." }
        } else {
            listener.stop()
            feedback = MonitorFeedbackState()
            hud.dismiss()
        }
        updateAudioTarget()
    }

    private func adjust(_ command: MonitorKeyRouting.Command) {
        let display = listener.routing.withLock { state -> MonitorKeyRouting.Display? in
            guard state.enabled, state.generation == command.generation else { return nil }
            return state.displays.first { $0.id == command.displayID && $0.values[command.control] != nil }
        }
        guard var display else { return }
        display.values[command.control] = command.value
        if command.control == .volume, command.value.current > 0 {
            display.values[.mute]?.current = 2
        }
        feedback.begin(command)
        hud.show(display: display, control: command.control, value: command.value, pending: feedback.pending)
        hardware?.enqueue(command)
    }

    private func receive(_ result: MonitorHardwareSession.Result) {
        switch result {
        case .muteState(let version, let id, let value):
            guard version == generation else { return }
            listener.routing.withLock { state in
                if let index = state.displays.firstIndex(where: { $0.id == id }) {
                    state.displays[index].values[.mute] = value
                }
            }
        case .discovered(let version, let found, let available):
            guard version == generation else { return }
            displays = found
            listener.routing.withLock { $0.displays = found }
            if !settings.externalMonitorControlsEnabled || sleeping { return }
            status = available ? (found.isEmpty ? "No external displays connected." : "External monitors detected.")
                : "Hardware monitor controls are unavailable on this Mac."
            if found.contains(where: { $0.values.isEmpty }) { nextProbe = Date().addingTimeInterval(30) }
            updateAudioTarget()
        case .applied(let command, let value):
            let accepted = listener.routing.withLock { $0.complete(command, value: value) }
            guard accepted else { return }
            displays = listener.routing.withLock { $0.displays }
            guard let display = displays.first(where: { $0.id == command.displayID }) else { return }
            let present = feedback.finish(command, failed: value == nil)
            if let value {
                if present { hud.show(display: display, control: command.control, value: value) }
            } else {
                if present { hud.showFailure(display: display) }
                status = "A monitor stopped responding. Retrying shortly; its unsupported keys use macOS."
                nextProbe = Date().addingTimeInterval(30)
            }
        }
    }

    private func updateAudioTarget() {
        let target = MonitorAudioOutput.target(displays: displays)
        listener.routing.withLock { $0.audioTarget = target }
    }

    private func currentScreens() -> [MonitorDDCTransport.Screen] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                CGDisplayIsBuiltin(id) == 0, CGDisplayIsOnline(id) != 0,
                CGDisplayIsInMirrorSet(id) == 0, CGDisplayIsInHWMirrorSet(id) == 0 else { return nil }
            return .init(id: id, name: screen.localizedName, bounds: CGDisplayBounds(id))
        }
    }

    private func screenSignature(_ screens: [MonitorDDCTransport.Screen]) -> String {
        screens.map { "\($0.id):\($0.bounds)" }.sorted().joined(separator: "|")
    }

    private func observe(
        _ name: Notification.Name, center: NotificationCenter,
        action: @escaping @MainActor @Sendable (MonitorControlCoordinator) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, active else { return }
                action(self)
            }
        }
        notifications.append(NotificationToken(token, center: center))
    }

    private static var audioAddress: AudioObjectPropertyAddress {
        .init(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
