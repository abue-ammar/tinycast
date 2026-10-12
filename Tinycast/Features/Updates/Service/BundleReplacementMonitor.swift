import Darwin
import Foundation

/// Reports changes to the folder holding the app, where a bundle swapped in by name shows up.
@MainActor
final class BundleReplacementMonitor {
    var onChange: (() -> Void)?

    private let folderURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var settleTask: Task<Void, Never>?

    /// Long enough to fold a move out and a move in, which Homebrew makes as separate renames.
    private static let settleDelay = Duration.milliseconds(500)

    init(bundleURL: URL) {
        folderURL = bundleURL.deletingLastPathComponent()
    }

    isolated deinit {
        settleTask?.cancel()
        source?.cancel()
    }

    /// The bundle's own descriptor would follow the old copy wherever it was moved.
    func start() {
        guard source == nil else { return }
        let descriptor = Darwin.open(folderURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.settle() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        self.source = source
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
}
