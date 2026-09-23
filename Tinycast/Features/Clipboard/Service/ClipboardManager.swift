import AppKit

@MainActor
final class ClipboardManager {
    /// Marker we attach to the pasteboard when *we* write to it, so polling ignores our own pastes.
    nonisolated static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")

    /// Longest text captured; bigger copies are skipped, truncation losing the tail.
    nonisolated static let maxTextLength = 32_000

    /// Markers put on secret copies by password managers, browsers and the OS.
    nonisolated static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive")
    ]

    private let store: ClipboardStore
    private let settings: AppSettings
    private var timer: Timer?
    private var sessionTokens: [NotificationToken] = []
    private let pasteboard: NSPasteboard
    private var lastChangeCount = 0
    private var isCapturing = false
    private var captureTask: Task<Void, Never>?
    private var captureGeneration = 0

    init(store: ClipboardStore, settings: AppSettings, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.settings = settings
        self.pasteboard = pasteboard
    }

    // Isolated so teardown can touch the main-actor timer; the poll block is already weak.
    isolated deinit {
        timer?.invalidate()
        captureTask?.cancel()
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
        stopPolling()
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
                    MainActor.assumeIsolated { self?.stopPolling() }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.startPolling() }
                }, center: center)
        ]
    }

    // Re-baselining first is what stops a clip made in another session reading as new on resume.
    private func startPolling() {
        guard isCapturing, timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        captureGeneration += 1
        captureTask?.cancel()
        captureTask = nil
    }

    // Drain first: the real copy must reach history before we overwrite the pasteboard.
    func prepareForTinycastPasteboardMutation() async -> Bool {
        guard isCapturing else { return true }
        guard timer != nil else { return false }
        let generation = captureGeneration
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !Task.isCancelled {
            guard isCapturing, timer != nil, generation == captureGeneration else { return false }
            poll()
            if captureTask == nil { return true }
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// Named pasteboards in the harness do not advance `changeCount` across processes.
    func captureCurrentPasteboardForTesting() {
        lastChangeCount = pasteboard.changeCount &- 1
        poll()
    }

    // Load-bearing: a mismatched count means a foreign write the next poll must still see.
    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        lastChangeCount = changeCount
    }

    /// A Finder select-all must not insert ten thousand rows on one poll tick.
    nonisolated static let maxCapturedFiles = 32

    /// Reclaimable roots, without the `/private` that `resolvingSymlinksInPath` strips.
    nonisolated static let volatileRoots = [
        "/tmp/", "/var/tmp/", "/var/folders/", NSHomeDirectory() + "/Library/Caches/"
    ]

    /// Both parameters are injected environment facts, so a harness can drive its own scratch.
    nonisolated static func fileURLs(
        on pasteboard: NSPasteboard, volatileRoots roots: [String] = volatileRoots
    ) -> [String]? {
        let durable = PasteboardFiles.urls(on: pasteboard, limit: maxCapturedFiles) {
            isDurable($0, roots: roots)
        }
        // Nil rather than empty, so a copied `http` URL falls through and stays a link.
        guard !durable.isEmpty else { return nil }
        // Reversed on insert, so the first file copied ends up leading the history.
        return durable.map(\.standardizedFileURL.path).reversed()
    }

    /// An app that stages a temp file beside better inline content must keep the inline content.
    nonisolated private static func isDurable(_ url: URL, roots: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var path = url.resolvingSymlinksInPath().path
        if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
        return !roots.contains { path.hasPrefix($0) }
    }

    private func poll() {
        guard isCapturing, timer != nil, captureTask == nil else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        // The pasteboard carries no source, so attribute it to the frontmost app.
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, settings.clipboardDisabledApps.contains(sourceBundleID) { return }
        let boardName = pasteboard.name.rawValue
        let generation = captureGeneration
        captureTask = Task.detached(priority: .utility) { [weak self] in
            let capture = Self.read(NSPasteboard(name: .init(boardName)))
            await self?.finish(capture, changeCount: changeCount, generation: generation,
                sourceBundleID: sourceBundleID)
        }
    }

    private enum Capture: Sendable {
        case files([String])
        case text(String)
        case image(Data)
    }

    nonisolated private static func read(_ pb: NSPasteboard) -> Capture? {
        if pb.types?.contains(internalType) == true { return nil }
        // Never record secrets: skip copies tagged sensitive by any of the marker owners.
        if let types = pb.types, !Set(types).isDisjoint(with: sensitiveTypes) { return nil }

        // Ahead of the text branch: Finder puts the file's *name* on `.string` beside its URL.
        if let paths = fileURLs(on: pb) { return .files(paths) }

        if let text = pb.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            guard text.count <= maxTextLength else { return nil }
            return .text(text)
        }

        if let type = pb.availableType(from: [.png, .tiff]), let data = pb.data(forType: type) {
            let png = type == .png
                ? data
                : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
            if let png { return .image(png) }
        }
        return nil
    }

    private func finish(
        _ capture: Capture?, changeCount: Int, generation: Int, sourceBundleID: String?
    ) {
        guard generation == captureGeneration else { return }
        captureTask = nil
        guard isCapturing, timer != nil else { return }
        if pasteboard.changeCount == changeCount, let capture {
            switch capture {
            case .files(let paths): store.addFiles(paths, sourceBundleID: sourceBundleID)
            case .text(let text): store.addText(text, sourceBundleID: sourceBundleID)
            case .image(let data): store.addImage(data, sourceBundleID: sourceBundleID)
            }
        }
        poll()
    }
}
