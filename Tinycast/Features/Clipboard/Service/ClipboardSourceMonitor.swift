import AppKit
import ObjectiveC

@objc(TinycastClipboardLogStream)
private protocol ClipboardLogStream: NSObjectProtocol {
    func setFilterPredicate(_ predicate: NSPredicate)
    func setFlags(_ flags: UInt64)
    func setEventHandler(_ handler: @escaping @convention(block) (NSObject) -> Void)
    func setInvalidationHandler(_ handler: @escaping @convention(block) () -> Void)
    func setDroppedEventHandler(_ handler: @escaping @convention(block) () -> Void)
    func activate()
    func invalidate()
}

@MainActor
final class ClipboardSourceMonitor {
    private let pasteboardName: String
    private var stream: (any ClipboardLogStream)?
    private var history = ClipboardSourceHistory()
    private var session = UUID()
    private var retryAfter: ContinuousClock.Instant?

    var isActive: Bool { stream != nil }

    init(pasteboardName: String = "Apple CFPasteboard general") {
        self.pasteboardName = pasteboardName
    }

    isolated deinit {
        stream?.invalidate()
    }

    func start() {
        guard stream == nil, retryAfter.map({ .now >= $0 }) != false else { return }
        retryAfter = .now.advanced(by: .seconds(5))
        guard let stream = Self.makeStream() else { return }
        let session = session
        let pasteboardName = pasteboardName
        stream.setFlags(0x1f)
        stream.setFilterPredicate(NSPredicate(
            format: "process == %@ AND category == %@", "pboard", "general"))
        stream.setEventHandler { [weak self] event in
            guard let message = event.value(forKey: "composedMessage") as? String,
                message.hasPrefix("\(pasteboardName) has new generation ")
            else { return }
            Task { @MainActor [weak self] in
                guard let self, self.session == session, self.isActive else { return }
                self.history.record(message, pasteboardName: pasteboardName)
            }
        }
        stream.setInvalidationHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.session == session else { return }
                self.stop()
                self.retryAfter = .now.advanced(by: .seconds(5))
            }
        }
        stream.setDroppedEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.session == session else { return }
                self.history.reset()
            }
        }
        self.stream = stream
        stream.activate()
    }

    func stop() {
        session = UUID()
        let stream = stream
        self.stream = nil
        history.reset()
        retryAfter = nil
        stream?.invalidate()
    }

    func source(for changeCount: Int) -> ClipboardSource? {
        guard let pid = writerPID(for: changeCount),
            let app = NSRunningApplication(processIdentifier: pid)
        else { return nil }
        return Self.source(for: app)
    }

    func writerPID(for changeCount: Int) -> Int32? {
        history.writers[changeCount]
    }

    static func source(for app: NSRunningApplication) -> ClipboardSource? {
        source(bundleID: app.bundleIdentifier, bundleURL: app.bundleURL)
    }

    static func source(bundleID: String?, bundleURL: URL?) -> ClipboardSource? {
        var ids = bundleID.map { [$0] } ?? []
        if var url = bundleURL {
            while url.path != "/" {
                if url.pathExtension == "app", let id = Bundle(url: url)?.bundleIdentifier,
                    !ids.contains(id)
                {
                    ids.append(id)
                }
                url.deleteLastPathComponent()
            }
        }
        guard !ids.isEmpty else { return nil }
        return ClipboardSource(bundleIDs: ids)
    }

    // Public pasteboard APIs omit the writer; pboard's live log names its PID and generation.
    private static func makeStream() -> (any ClipboardLogStream)? {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/LoggingSupport.framework"),
            bundle.load(),
            let sourceClass = NSClassFromString("OSLogEventLiveSource") as? NSObject.Type,
            let streamClass = NSClassFromString("OSLogEventLiveStream") as? NSObject.Type,
            let bridge = objc_getProtocol("TinycastClipboardLogStream")
        else { return nil }
        let selectors = [
            "initWithLiveSource:", "setFilterPredicate:", "setFlags:", "setEventHandler:",
            "setInvalidationHandler:", "setDroppedEventHandler:", "activate", "invalidate"
        ]
        guard selectors.allSatisfy({ class_getInstanceMethod(streamClass, NSSelectorFromString($0)) != nil })
        else { return nil }
        class_addProtocol(streamClass, bridge)
        guard let allocated = (streamClass as AnyObject).perform(NSSelectorFromString("alloc"))?
            .takeRetainedValue() as? NSObject
        else { return nil }
        return allocated.perform(NSSelectorFromString("initWithLiveSource:"), with: sourceClass.init())?
            .takeUnretainedValue() as? any ClipboardLogStream
    }
}
