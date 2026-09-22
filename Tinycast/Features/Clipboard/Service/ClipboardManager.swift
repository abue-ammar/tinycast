import AppKit
import os

@MainActor
final class ClipboardManager {
    /// Marker we attach to the pasteboard when *we* write to it, so polling ignores our own pastes.
    static let internalType = NSPasteboard.PasteboardType(ClipboardCapture.internalTypeName)

    /// Longest text captured; bigger copies are skipped, truncation losing the tail.
    static let maxTextLength = ClipboardCapture.maxTextLength

    /// Markers put on secret copies by password managers, browsers and the OS.
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = Set(
        ClipboardCapture.sensitiveTypeNames.map { NSPasteboard.PasteboardType($0) })

    private let store: ClipboardStore
    private let settings: AppSettings
    private let logger = Logger(subsystem: "com.tinycast", category: "Clipboard")
    private var timer: Timer?
    private var sessionTokens: [NotificationToken] = []
    private var watched = NSPasteboard.general
    private var lastChangeCount = 0
    private var isCapturing = false
    private var captureEpoch = 0
    private var isReading = false
    private var pendingCapture: Task<Void, Never>?
    private var reader: ClipboardCaptureClient?
    private var helperExecutable: URL
    private var didLogMissingHelper = false
    /// A hung owner must lose the helper, not the next paste.
    var captureTimeout: Duration = .milliseconds(1500)

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        helperExecutable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ClipboardCaptureHelper")
    }

    /// Tests point at a helper they just compiled. The app uses the bundled one.
    func useCaptureHelper(at executable: URL) {
        helperExecutable = executable
        reader?.cancel()
        reader = nil
    }

    /// Harness-only. Production watches `NSPasteboard.general`.
    func useWatchedPasteboard(_ pasteboard: NSPasteboard) {
        watched = pasteboard
        lastChangeCount = pasteboard.changeCount &- 1
    }

    // Isolated so teardown can touch the main-actor timer; the poll block is already weak.
    isolated deinit {
        timer?.invalidate()
        reader?.cancel()
    }

    func start() {
        guard !isCapturing else { return }
        isCapturing = true
        installSessionObservers()
        startPolling()
    }

    /// Turning the feature off: the poller, the observers and the drain all go with it.
    func stop() {
        isCapturing = false
        sessionTokens = []
        stopTimer()
        abandonCapture()
    }

    /// The real copy has to reach history before a Tinycast write replaces it.
    func drainPendingCapture() async {
        guard !Task.isCancelled else { return }
        if isCapturing { poll() }
        await pendingCapture?.value
        guard isCapturing, !Task.isCancelled else { return }
        poll()
        await pendingCapture?.value
    }

    // Load-bearing: a mismatched count means a foreign write the next poll must still see.
    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {
        guard watched.changeCount == changeCount else { return }
        lastChangeCount = changeCount
    }

    /// A Finder select-all must not insert ten thousand rows on one poll tick.
    nonisolated static let maxCapturedFiles = ClipboardCapture.maxCapturedFiles

    /// Reclaimable roots, without the `/private` that `resolvingSymlinksInPath` strips.
    nonisolated static let volatileRoots = ClipboardCapture.volatileRoots

    /// Both parameters are injected environment facts, so a harness can drive its own scratch.
    nonisolated static func fileURLs(
        on pasteboard: NSPasteboard, volatileRoots roots: [String] = volatileRoots
    ) -> [String]? {
        ClipboardCapture.filePaths(on: pasteboard, volatileRoots: roots)
    }

    /// Harness entry. Production goes through `poll`, which only samples `changeCount` here.
    func capture(pasteboard: NSPasteboard, sourceBundleID: String?) async {
        guard isCapturing else { return }
        beginCapture(board: pasteboard.name.rawValue, sourceBundleID: sourceBundleID)
        await pendingCapture?.value
    }

    // Fast user switching: another session's clipboard isn't ours, so stop waking up for it.
    private func installSessionObservers() {
        guard sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.sessionDidResign() }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.sessionDidBecomeActive() }
                }, center: center)
        ]
    }

    // Re-baselining first is what stops a clip made in another session reading as new on resume.
    private func startPolling() {
        guard isCapturing, timer == nil else { return }
        lastChangeCount = watched.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func sessionDidResign() {
        stopTimer()
        abandonCapture()
    }

    private func sessionDidBecomeActive() {
        startPolling()
    }

    /// Bumps the epoch so a helper that already read cannot still publish.
    private func abandonCapture() {
        captureEpoch += 1
        isReading = false
        pendingCapture?.cancel()
        pendingCapture = nil
        reader?.cancel()
    }

    private func poll() {
        let changeCount = watched.changeCount
        guard changeCount != lastChangeCount, !isReading else { return }
        // A timed-out copy is skipped: retrying it would make every drain wait out the timeout.
        lastChangeCount = changeCount
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        beginCapture(board: watched.name.rawValue, sourceBundleID: source)
    }

    private func beginCapture(board: String, sourceBundleID: String?) {
        guard isCapturing, !isReading else { return }
        if let sourceBundleID, settings.clipboardDisabledApps.contains(sourceBundleID) { return }
        guard let reader = makeReader() else { return }
        isReading = true
        let epoch = captureEpoch
        let timeout = captureTimeout
        pendingCapture = Task { [weak self] in
            let payload = await reader.read(board: board, timeout: timeout)
            guard let self, epoch == self.captureEpoch else { return }
            self.isReading = false
            guard self.isCapturing else { return }
            self.apply(payload, sourceBundleID: sourceBundleID)
        }
    }

    private func makeReader() -> ClipboardCaptureClient? {
        if let reader { return reader }
        guard FileManager.default.isExecutableFile(atPath: helperExecutable.path) else {
            if !didLogMissingHelper {
                didLogMissingHelper = true
                logger.error(
                    "capture helper missing at \(self.helperExecutable.path, privacy: .public)")
            }
            return nil
        }
        let reader = ClipboardCaptureClient(executable: helperExecutable)
        self.reader = reader
        return reader
    }

    private func apply(_ payload: ClipboardCapture.Payload, sourceBundleID: String?) {
        switch payload {
        case .text(let text):
            guard text.count <= Self.maxTextLength else { return }
            store.addText(text, sourceBundleID: sourceBundleID)
        case .files(let paths):
            store.addFiles(paths, sourceBundleID: sourceBundleID)
        case .png(let data):
            store.addImage(data, sourceBundleID: sourceBundleID)
        case .skipped, .timedOut, .unavailable:
            break
        }
    }
}
