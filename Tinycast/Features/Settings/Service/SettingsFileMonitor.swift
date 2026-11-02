import Darwin
import Foundation

/// Reports edits to settings.json, an editor's save-by-rename included, once the writes settle.
@MainActor
final class SettingsFileMonitor {
    var onChange: (() -> Void)?

    private let fileURL: URL
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var settleTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    private static let settleDelay = Duration.milliseconds(150)
    private static let retryDelay = Duration.seconds(1)

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    isolated deinit {
        settleTask?.cancel()
        retryTask?.cancel()
        folderSource?.cancel()
        fileSource?.cancel()
    }

    func start() {
        arm()
    }

    /// The file is reopened every time: a save by rename leaves the old descriptor on a dead inode.
    private func arm() {
        let folder = fileURL.deletingLastPathComponent()
        if folderSource == nil {
            folderSource = source(watching: folder, events: [.write, .delete, .rename, .revoke])
        }
        fileSource?.cancel()
        fileSource = source(watching: fileURL, events: [.write, .extend, .delete, .rename, .revoke])
        if !isWatching { scheduleRetry() }
    }

    private var isWatching: Bool {
        guard folderSource != nil else { return false }
        return fileSource != nil
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path)) == nil
    }

    private func source(
        watching url: URL, events: DispatchSource.FileSystemEvent
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.sourceDidFire() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        return source
    }

    private func sourceDidFire() {
        if !FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path) {
            folderSource?.cancel()
            folderSource = nil
        }
        arm()
        settle()
    }

    private func settle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.settleDelay)
            } catch {
                return
            }
            self?.onChange?()
        }
    }

    /// Polls only while the folder or a link's target is missing; the next save brings it back.
    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.retryDelay)
            } catch {
                return
            }
            guard let self else { return }
            retryTask = nil
            arm()
            if isWatching { settle() }
        }
    }
}
