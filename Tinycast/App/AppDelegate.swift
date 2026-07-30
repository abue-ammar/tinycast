import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shouldStart = true
    private var instanceLock: SingleInstanceLock?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        // Elect the survivor before looking for anyone to defer to: two copies launched in the same instant would each see the other and both quit.
        if let lock = SingleInstanceLock.acquire(bundleIdentifier: bundleIdentifier) {
            instanceLock = lock
            return
        }
        shouldStart = false
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
            .activate()
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard shouldStart else { return }
        AppCore.shared.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppCore.shared.applicationShouldTerminate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCore.shared.prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCore.shared.handleReopen()
        return true
    }
}

/// Channel-scoped `flock` in this bundle id's Application Support folder: the kernel elects one owner however many copies race, and releases it when that process dies — no stale pid to reap.
private final class SingleInstanceLock {
    private let descriptor: Int32?

    /// `nil` only when another live instance owns this channel; any other failure fails open, so a broken container never blocks launch.
    static func acquire(bundleIdentifier: String) -> SingleInstanceLock? {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("instance.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return SingleInstanceLock(descriptor: nil) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let contended = errno == EWOULDBLOCK
            close(descriptor)
            return contended ? nil : SingleInstanceLock(descriptor: nil)
        }
        return SingleInstanceLock(descriptor: descriptor)
    }

    private init(descriptor: Int32?) {
        self.descriptor = descriptor
    }

    deinit {
        guard let descriptor else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
