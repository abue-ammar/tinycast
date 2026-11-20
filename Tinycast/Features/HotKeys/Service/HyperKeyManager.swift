import AppKit
import Carbon.HIToolbox

/// Owns the Hyper Key's lifecycle and policy. See docs/features/hotkeys.md#the-hyper-key.
@MainActor
@Observable
final class HyperKeyManager: HealthCheckable {
    enum Status: Equatable {
        case off
        case active
        case needsAccessibility
        case blocked(appName: String)
        case remapUnavailable
        case paused
    }

    private(set) var status: Status = .off

    @ObservationIgnored var onProblem: ((String) -> Void)?
    @ObservationIgnored weak var healthTicker: HealthTicker?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let hotKeys: HotKeyManager
    @ObservationIgnored private let tap = HyperKeyTap()
    @ObservationIgnored private lazy var remapper = KeyboardRemapper(instanceLock: instanceLock)
    @ObservationIgnored private let secureInput = SecureInputMonitor()
    @ObservationIgnored private let instanceLock = RemapInstanceLock(
        url: .temporaryDirectory.appending(path: "com.tinycast.hyper-key.lock"))
    @ObservationIgnored private var observers: [NotificationToken] = []
    @ObservationIgnored private var darwinObservers: [DarwinNotificationToken] = []
    @ObservationIgnored private var runningAppsObservation: NSKeyValueObservation?
    @ObservationIgnored private var permissionRetry: Task<Void, Never>?
    @ObservationIgnored private var pauseReasons: Set<PauseReason> = []

    private enum PauseReason {
        case asleep, screenLocked, sessionInactive
    }

    init(settings: AppSettings, hotKeys: HotKeyManager) {
        self.settings = settings
        self.hotKeys = hotKeys
    }

    func start() {
        secureInput.onChange = { [weak self] _ in self?.secureInputChanged() }
        tap.onUnmappedCapsLock = { [weak self] in self?.repairRemap() }
        remapper.onKeyboardConnected = { [weak self] in self?.updateForwarding() }
        remapper.clearLeftovers()
        observeSettings()
        observeSystem()
        secureInput.start()
        apply()
    }

    func restart() {
        stop(.off)
        apply()
    }

    /// The HID remap outlives the process, so hand the key back before exiting.
    func prepareForTermination() {
        stop(.off)
    }

    func diagnostics() -> HyperKeyDiagnostics {
        let key = settings.hyperKey
        let keyboards = remapper.keyboards
        return HyperKeyDiagnostics(
            isActive: status == .active,
            activeKeyTitle: status == .active ? key.title : nil,
            eventTapEnabled: tap.isEnabled,
            runLoopSourceValid: tap.runLoopSourceIsValid,
            remappedKeyboards: remapper.remappedKeyboardNames,
            conflictingApps: HyperKeyConflictScanner.runningConflicts(),
            karabinerVirtualKeyboards: keyboards.map(\.name).filter(
                HyperKeyConflictPolicy.isKarabinerVirtualKeyboard),
            karabinerConflict: remapper.sawKarabinerConflict
                || HyperKeyConflictScanner.karabinerRemaps(key),
            capsLockMappingConflicts: key == .capsLock
                ? HyperKeyConflictScanner.capsLockRemaps().map { name(of: $0, among: keyboards) }
                : [],
            takeover: takeover(),
            keyboardTaps: HyperKeyConflictScanner.keyboardTaps(),
            secureInputCompatibilityActive: status == .active && isSecureInputCompatible,
            secureInput: secureInput.report())
    }

    /// Read on demand: another app taking the key over leaves nothing for Tinycast to observe.
    func takeover() -> HyperKeyDiagnostics.Takeover? {
        guard status == .active else { return nil }
        let keyboards = remapper.overriddenKeyboardNames
        guard !keyboards.isEmpty else { return nil }
        let suspects =
            HyperKeyConflictScanner.runningConflicts().map(\.name)
            + HyperKeyConflictScanner.keyboardTaps().map(\.appName)
        return HyperKeyDiagnostics.Takeover(
            keyboards: keyboards,
            likelyApps: suspects.reduce(into: []) { apps, app in
                if !apps.contains(app) { apps.append(app) }
            })
    }

    // MARK: - Applying

    /// Idempotent: every input funnels here, and it converges on what the settings ask for.
    private func apply() {
        let key = settings.hyperKey
        guard let route = key.route(secureInputCompatible: isSecureInputCompatible) else {
            return stop(.off)
        }
        if let blocker = HyperKeyConflictScanner.runningBlocker() { return block(by: blocker) }
        guard pauseReasons.isEmpty else { return stop(.paused) }
        guard Permissions.isAccessibilityTrusted() else { return retryLater(.needsAccessibility) }
        guard instanceLock.acquire() else { return block(by: otherInstanceName) }
        setRoute(route)
        guard tap.install() else { return retryLater(.needsAccessibility) }
        if key == .capsLock, remapper.mapping == nil { tap.unlatchCapsLock() }
        // A modifier needs no remap, so cleanup still pending on some keyboard cannot block it.
        guard remapper.apply(route.remap) || route.remap == nil else { return retryLater(.remapUnavailable) }
        healthTicker?.unsubscribe(self)
        status = .active
        updateForwarding()
        syncSecureInputHotKeys()
    }

    private func block(by appName: String) {
        if status != .blocked(appName: appName) {
            onProblem?(String(localized: "Quit \(appName) to use the Hyper Key"))
        }
        retryLater(.blocked(appName: appName))
    }

    private func retryLater(_ status: Status) {
        stop(status, retrying: true)
    }

    private func stop(_ status: Status, retrying: Bool = false) {
        setRoute(nil)
        tap.tearDown()
        remapper.apply(nil)
        instanceLock.release()
        if retrying { healthTicker?.subscribe(self) } else { healthTicker?.unsubscribe(self) }
        if self.status != status { self.status = status }
        syncSecureInputHotKeys()
    }

    private func setRoute(_ route: HyperKeyRoute?) {
        tap.configure(
            route: route, includesShift: settings.hyperKeyIncludesShift,
            quickPress: settings.hyperKeyQuickPress)
        hotKeys.capture.hyperRoute = route
    }

    private var otherInstanceName: String {
        instanceLock.holder().flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            ?? "Tinycast"
    }

    /// That press latched Caps Lock on a keyboard that lost the remap, so undo it once repaired.
    private func repairRemap() {
        guard status == .active else { return }
        let result = remapper.repair()
        guard result.succeeded else { return retryLater(.remapUnavailable) }
        if result.changed, settings.hyperKey == .capsLock { tap.unlatchCapsLock() }
    }

    private var isSecureInputCompatible: Bool {
        settings.hyperKey.supportsSecureInputCompatibility && settings.hyperKeySecureInputCompatibility
    }

    /// One-second retry while waiting, never while active. See docs/features/hotkeys.md#lifecycle.
    func healthCheck() {
        apply()
    }

    /// macOS drops a tap whose grant is revoked, so rebuilding also re-checks the grant.
    private func recoverTap() {
        guard status == .active, tap.isEnabled != true else { return }
        tap.tearDown()
        apply()
    }

    /// tccd announces a change before the new grant reads back, so the retry waits a beat.
    private func permissionsChanged() {
        permissionRetry?.cancel()
        permissionRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.apply()
        }
    }

    // MARK: - Secure Input

    private func secureInputChanged() {
        // The tap saw neither end of anything typed inside, so a half-held chord is stale.
        tap.cancelHold()
        updateForwarding()
        syncSecureInputHotKeys()
    }

    /// Inside Secure Input only Carbon hotkeys fire: ⌃ equivalents when compatible, else a hint.
    private func syncSecureInputHotKeys() {
        let isInside = status == .active && secureInput.isActive
        hotKeys.setSecureInputEquivalents(
            includesShift: isInside && isSecureInputCompatible ? settings.hyperKeyIncludesShift : nil)
        let swallowsCapsLock = isInside && settings.hyperKey == .capsLock && !isSecureInputCompatible
        hotKeys.setSecureInputHint(
            swallowsCapsLock ? KeyShortcut(carbonKeyCode: kVK_F18, carbonModifiers: 0) : nil
        ) { [weak self] in
            self?.onProblem?(String(localized: "The Hyper Key can't work while Secure Input is on"))
        }
    }

    // MARK: - Observation

    private func updateForwarding() {
        if status == .active { tap.updateForwarding() }
    }

    /// Fires synchronously on main before the write lands, so the task re-arms, then applies.
    private func observeSettings() {
        withObservationTracking {
            _ = settings.hyperKey
            _ = settings.hyperKeySecureInputCompatibility
            _ = settings.hyperKeyIncludesShift
            _ = settings.hyperKeyQuickPress
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSettings()
                self.apply()
            }
        }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observers = [
            observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.updateForwarding() },
            observe(workspace, NSWorkspace.willSleepNotification) { $0.pause(.asleep) },
            observe(workspace, NSWorkspace.didWakeNotification) { $0.resume(.asleep) },
            observe(workspace, NSWorkspace.sessionDidResignActiveNotification) {
                $0.pause(.sessionInactive)
            },
            observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) {
                $0.resume(.sessionInactive)
            },
            // Caps Lock has to be Caps Lock again for a password typed at the lock screen.
            observe(distributed, Notification.Name("com.apple.screenIsLocked")) {
                $0.pause(.screenLocked)
            },
            observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
                $0.resume(.screenLocked)
            }
        ]
        darwinObservers = [
            DarwinNotificationToken("com.apple.coregraphics.eventTapRemoved") { [weak self] in
                self?.recoverTap()
            },
            DarwinNotificationToken("com.apple.tcc.access.changed") { [weak self] in
                self?.permissionsChanged()
            }
        ]
        observeBlockingApps()
    }

    private func pause(_ reason: PauseReason) {
        pauseReasons.insert(reason)
        apply()
    }

    private func resume(_ reason: PauseReason) {
        pauseReasons.remove(reason)
        apply()
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        _ handler: @escaping @Sendable @MainActor (HyperKeyManager) -> Void
    ) -> NotificationToken {
        NotificationToken(
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self)
                }
            }, center: center)
    }

    /// KVO, because launch notifications skip menu-bar apps such as the known blockers.
    private func observeBlockingApps() {
        runningAppsObservation = NSWorkspace.shared.observe(
            \.runningApplications, options: [.old, .new]
        ) { [weak self] _, change in
            let bundleIDs = ((change.newValue ?? []) + (change.oldValue ?? [])).compactMap(\.bundleIdentifier)
            MainActor.assumeIsolated {
                let isBlocker = { HyperKeyConflictPolicy.severity(ofBundleID: $0) == .blocking }
                guard bundleIDs.contains(where: isBlocker) else { return }
                self?.apply()
            }
        }
    }

    private func name(
        of identity: HyperKeyConflictPolicy.KeyboardIdentity, among keyboards: [HIDEventSystem.Keyboard]
    ) -> String {
        if identity.isDefault { return String(localized: "All keyboards") }
        return keyboards.first {
            $0.vendorID == identity.vendorID && $0.productID == identity.productID
        }?.name ?? String(localized: "Keyboard \(String(identity.vendorID))-\(String(identity.productID))")
    }
}
