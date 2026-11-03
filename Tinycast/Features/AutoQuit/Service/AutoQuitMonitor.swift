import AppKit

/// Quits opted-in apps after they leave the foreground. One wake tracks the soonest deadline.
@MainActor
final class AutoQuitMonitor {
    private let settings: AppSettings
    private let activity = AutoQuitActivity()
    private let ownBundleID = Bundle.main.bundleIdentifier ?? ""
    private var armedAt: [String: Date] = [:]
    private var recording = false
    private var playing: Set<String> = []
    private var wake: Task<Void, Never>?
    private var workspaceTokens: [NotificationCenter.ObservationToken] = []
    private var started = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard !started else { return }
        started = true
        observeWorkspace()
        activity.start { [weak self] in self?.apply($0) }
        sync()
    }

    /// Rules or the default duration changed. Existing deadlines stay.
    func sync() {
        let now = Date()
        armedAt = AutoQuitSchedule.reconcile(
            armedAt: armedAt, rules: settings.autoQuitRules, running: runningBundleIDs(),
            runningRegular: runningRegularBundleIDs(), frontmost: frontmostBundleID(),
            ownBundleID: ownBundleID, now: now)
        schedule(now: now)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let workspace = NSWorkspace.shared
        workspaceTokens = [
            center.addObserver(
                of: workspace, for: NSWorkspace.DidActivateApplicationMessage.self
            ) { [weak self] in
                self?.disarm($0.application)
            },
            center.addObserver(
                of: workspace, for: NSWorkspace.DidDeactivateApplicationMessage.self
            ) { [weak self] in
                self?.arm($0.application)
            },
            center.addObserver(
                of: workspace, for: NSWorkspace.DidHideApplicationMessage.self
            ) { [weak self] in
                self?.arm($0.application)
            },
            center.addObserver(
                of: workspace, for: NSWorkspace.DidLaunchApplicationMessage.self
            ) { [weak self] in
                self?.launched($0.application)
            },
            center.addObserver(
                of: workspace, for: NSWorkspace.DidTerminateApplicationMessage.self
            ) { [weak self] in
                self?.disarm($0.application)
            },
            center.addObserver(of: workspace, for: NSWorkspace.DidWakeMessage.self) { [weak self] _ in
                self?.schedule(now: Date())
            }
        ]
    }

    private func launched(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        arm(app)
    }

    private func arm(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, tracks(id), frontmostBundleID() != id else { return }
        guard armedAt[id] == nil else { return }
        armedAt[id] = Date()
        schedule(now: Date())
    }

    private func disarm(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, armedAt.removeValue(forKey: id) != nil else { return }
        schedule(now: Date())
    }

    private func apply(_ snapshot: AutoQuitActivity.Snapshot) {
        let wasRecording = recording
        let wasPlaying = playing
        recording = snapshot.recording
        playing = snapshot.playing
        let now = Date()
        if wasRecording && !recording {
            for id in armedAt.keys { armedAt[id] = now }
        } else if !recording {
            for id in wasPlaying.subtracting(playing) where armedAt[id] != nil {
                armedAt[id] = now
            }
        }
        schedule(now: now)
    }

    private func schedule(now: Date) {
        wake?.cancel()
        var decision = AutoQuitSchedule.decide(snapshot(now: now))
        if !decision.quit.isEmpty {
            for id in decision.quit {
                // A save sheet leaves the app running, so the interval starts over.
                armedAt[id] = AppLauncher.quit(bundleID: id) ? now : nil
            }
            decision = AutoQuitSchedule.decide(snapshot(now: now))
        }
        guard let next = decision.nextWake else { return }
        let delay = max(next.timeIntervalSince(now), 0)
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.schedule(now: Date())
        }
    }

    private func snapshot(now: Date) -> AutoQuitSnapshot {
        AutoQuitSnapshot(
            rules: settings.autoQuitRules, defaultMinutes: settings.autoQuitMinutes,
            armedAt: armedAt, now: now, recording: recording, playing: playing,
            frontmost: frontmostBundleID(), ownBundleID: ownBundleID)
    }

    private func tracks(_ bundleID: String) -> Bool {
        !AutoQuitSchedule.isExcluded(bundleID, ownBundleID: ownBundleID)
            && settings.autoQuitRules.contains { $0.bundleID == bundleID }
    }

    private func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Accessory apps never become frontmost, so only a deactivate arms them.
    private func runningRegularBundleIDs() -> Set<String> {
        Set(
            NSWorkspace.shared.runningApplications.compactMap { app in
                guard app.activationPolicy == .regular else { return nil }
                return app.bundleIdentifier
            })
    }
}
