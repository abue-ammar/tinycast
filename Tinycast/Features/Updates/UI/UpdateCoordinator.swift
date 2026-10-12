import AppKit
import SwiftUI

/// The installer only performs an update the coordinator has decided is safe.
@MainActor
@Observable
final class UpdateCoordinator {
    /// One surface for prompt, progress and report: a download cannot move into a dialog.
    enum Stage: Equatable {
        case checking
        case upToDate
        /// A local build has no release stream to compare against, and says so rather than lying.
        case localBuild
        case available(AvailableRelease)
        case blocked(UpdateReadiness.Blocker, AvailableRelease)
        case installing(AvailableRelease, UpdateInstaller.Phase)
        case readyToRelaunch
        case failed(UpdateFailure)
    }

    private(set) var stage: Stage = .checking

    private let store: UpdateCheckStore
    /// Environment injection and activity reads only — never for state this type owns.
    private unowned let core: AppCore
    @ObservationIgnored private lazy var window = AppWindowController(
        title: "Software Update", contentSize: UpdateWindowView.initialSize,
        activation: core.activationPolicy)
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var replacementTask: Task<Void, Never>?

    private static let replacementPollInterval = Duration.seconds(1)
    /// A copy still being written fails its seal; one that never passes is not ours to launch.
    private static let sealAttempts = 30

    init(store: UpdateCheckStore, core: AppCore) {
        self.store = store
        self.core = core
    }

    var channel: ReleaseChannel { store.channel }
    var runningVersion: String { store.runningVersion?.description ?? "unknown" }

    /// A local build has no release stream, so it does not advertise the command either.
    func applyEnabled() {
        core.appIndex.setCommandsVisible([.checkForUpdates], store.channel.updatesItself)
    }

    func applyAutomaticChecking() {
        if core.settings.automaticallyCheckForUpdates {
            store.start()
        } else {
            store.stop()
        }
    }

    func focusExisting() -> Bool {
        window.focus()
    }

    /// The window takes the height its content measured, so no stage pads itself out with space.
    func fit(height: CGFloat) {
        window.fitContent(width: UpdateWindowView.width, height: height)
    }

    // MARK: - Entry points

    /// The manual action: always opens the window and always asks GitHub.
    func checkForUpdates() {
        guard store.channel.updatesItself else {
            stage = .localBuild
            present()
            return
        }
        if case .installing = stage {
            present()
            return
        }
        stage = .checking
        present()
        Task { [weak self] in
            guard let self else { return }
            let answered = await store.check()
            guard case .checking = stage else { return }
            if let release = store.update {
                stage = .available(release)
            } else if answered {
                stage = .upToDate
            } else {
                stage = .failed(.downloadFailed("Tinycast could not reach GitHub."))
            }
        }
    }

    /// The automatic path: `false` answers that it withheld the prompt, so the store re-offers it.
    func presentIfAvailable(_ release: AvailableRelease) -> Bool {
        guard core.settings.automaticallyCheckForUpdates else { return false }
        switch stage {
        // Already in hand: re-offering would throw away a download or the relaunch it earned.
        case .installing, .readyToRelaunch:
            return true
        case .checking, .upToDate, .localBuild, .available, .blocked, .failed:
            guard UpdateReadiness.evaluate(core.currentActivity) == nil else { return false }
            stage = .available(release)
            present()
            return true
        }
    }

    // MARK: - Actions

    func install() {
        guard let release = pendingRelease else { return }
        // Re-asked at the moment of the click, never read from a flag that could have gone stale.
        if let blocker = UpdateReadiness.evaluate(core.currentActivity) {
            stage = .blocked(blocker, release)
            return
        }
        stage = .installing(release, .downloading(received: 0, expected: release.assetSize))
        let installer = self.installer
        // Hoisted: nesting the hop inside the task body would re-capture its weak `self`.
        let onProgress: @Sendable (UpdateInstaller.Phase) -> Void = { [weak self] phase in
            Task { @MainActor in self?.report(phase, for: release) }
        }
        installTask = Task { [weak self] in
            do {
                try await installer.install(release, onProgress: onProgress)
                self?.stage = .readyToRelaunch
            } catch is CancellationError {
                self?.stage = .available(release)
            } catch let failure as UpdateFailure {
                self?.stage = .failed(failure)
            } catch {
                self?.stage = .failed(.downloadFailed(error.localizedDescription))
            }
        }
    }

    /// Dismissing a version is what stops it asking again; a later one still will.
    func skip() {
        if let release = pendingRelease { store.skip(release) }
        window.close()
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    func retry() {
        guard let release = pendingRelease else { return }
        stage = .available(release)
    }

    func dismiss() {
        window.close()
    }

    /// `NSApp.terminate`, never `exit`: it flushes a note draft and returns the HID remap.
    func relaunch() {
        RelaunchRunner.relaunchAfterExit(Bundle.main.bundleURL)
        // From a timer, not a main-actor job: `.terminateLater` replies through a main-actor task.
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }

    /// Homebrew run from inside Tinycast never quits its host, so it never reopens it either.
    func installedCopyChanged() {
        guard replacementTask == nil else { return }
        replacementTask = Task { [weak self] in
            await self?.relaunchOnceReplacementSettles()
            self?.replacementTask = nil
        }
    }

    // MARK: - Private

    private func relaunchOnceReplacementSettles() async {
        var failedSeals = 0
        while !Task.isCancelled {
            switch replacementDecision() {
            case .keepRunning:
                return
            case .wait:
                break
            case .relaunch:
                guard await Self.isSealed(Bundle.main.bundleURL) else {
                    failedSeals += 1
                    if failedSeals >= Self.sealAttempts { return }
                    break
                }
                // Re-asked: the palette may have opened while the seal was being checked.
                guard !Task.isCancelled, replacementDecision() == .relaunch else { break }
                relaunch()
                return
            }
            do {
                try await Task.sleep(for: Self.replacementPollInterval)
            } catch {
                return
            }
        }
    }

    private func replacementDecision() -> BundleReplacementPolicy.Decision {
        guard let running = BundleReplacementPolicy.Identity(info: Bundle.main.infoDictionary)
        else { return .keepRunning }
        let installed = BundleReplacementPolicy.Identity(
            info: UpdateInstaller.info(at: Bundle.main.bundleURL))
        return BundleReplacementPolicy.decide(
            running: running, installed: installed, isInstallingItself: isInstallingItself,
            isHostingHomebrew: DescendantProcessScanner.executablePaths().contains(
                where: BundleReplacementPolicy.isHomebrew),
            blocker: UpdateReadiness.evaluate(core.currentActivity))
    }

    /// Our own install already offers Relaunch, and must not be pre-empted by its own swap.
    private var isInstallingItself: Bool {
        switch stage {
        case .installing, .readyToRelaunch: return true
        case .checking, .upToDate, .localBuild, .available, .blocked, .failed: return false
        }
    }

    @concurrent
    private nonisolated static func isSealed(_ bundleURL: URL) async -> Bool {
        BundleSignature.isTrusted(bundleURL)
    }

    private func report(_ phase: UpdateInstaller.Phase, for release: AvailableRelease) {
        guard case .installing = stage else { return }
        stage = .installing(release, phase)
    }

    private var pendingRelease: AvailableRelease? {
        switch stage {
        case .available(let release), .blocked(_, let release), .installing(let release, _):
            return release
        case .checking, .upToDate, .localBuild, .readyToRelaunch, .failed:
            return store.update
        }
    }

    private var installer: UpdateInstaller {
        UpdateInstaller(
            bundleURL: Bundle.main.bundleURL,
            stagingDirectory: AppPaths.caches().appendingPathComponent("Updates", isDirectory: true))
    }

    private func present() {
        window.show {
            UpdateWindowView()
                .environment(self)
        }
    }
}
