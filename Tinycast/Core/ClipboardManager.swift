import AppKit

@MainActor
final class ClipboardManager {
    /// Marker we attach to the pasteboard when *we* write to it, so polling ignores our own pastes.
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")

    /// Longest text we capture into history; bigger copies are skipped outright (truncating would silently drop the tail on paste).
    static let maxTextLength = 32_000

    /// Pasteboard markers password managers, browsers, and the OS put on secret copies (passwords, OTPs, autofill) — never recorded, regardless of source app.
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive"),
    ]

    private let store: ClipboardStore
    private let settings: AppSettings
    private var timer: Timer?
    private var lastChangeCount = 0

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    // Isolated so teardown can touch the main-actor timer; AppCore only releases the manager on the main actor, so no hop. The poll block is `[weak self]`, so this isn't fixing a leak — it stops a stray timer firing if the manager is ever recreated.
    isolated deinit {
        timer?.invalidate()
    }

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // Drains the pending change first: the user's real copy has to reach history before our temporary text overwrites the pasteboard.
    func prepareForTinycastPasteboardMutation() {
        poll()
    }

    // The guard is load-bearing: a foreign write that landed after ours leaves the count mismatched, and skipping the assignment keeps that write capturable by the next poll.
    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {
        guard NSPasteboard.general.changeCount == changeCount else { return }
        lastChangeCount = changeCount
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if pb.types?.contains(Self.internalType) == true { return }

        // Never record secrets: skip copies tagged sensitive by password managers, browsers, or the OS.
        if let types = pb.types, !Set(types).isDisjoint(with: Self.sensitiveTypes) { return }

        // The pasteboard doesn't carry its source, so attribute the change to the frontmost app (the copy happened within the last 0.5s poll).
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, settings.clipboardDisabledApps.contains(sourceBundleID) { return }

        if let text = pb.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            guard text.count <= Self.maxTextLength else { return }
            store.addText(text, sourceBundleID: sourceBundleID)
            return
        }

        if let type = pb.availableType(from: [.png, .tiff]), let data = pb.data(forType: type) {
            let isPNG = type == .png
            let store = store
            // A big copy's TIFF→PNG re-encode can take 100ms+; keep the poll (and the UI) off that path.
            Task.detached(priority: .utility) {
                let png =
                    isPNG
                    ? data
                    : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                guard let png else { return }
                await store.addImage(png, sourceBundleID: sourceBundleID)
            }
        }
    }
}
