import Darwin
import Foundation

@MainActor
protocol NoteFileMonitoring: AnyObject {
    var onChange: (() -> Void)? { get set }

    func start(directory: URL, fileURL: URL)
    func stop()
}

@MainActor
final class NoteFileMonitor: NoteFileMonitoring {
    var onChange: (() -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var generation = 0

    isolated deinit {
        directorySource?.cancel()
        fileSource?.cancel()
    }

    func start(directory: URL, fileURL: URL) {
        stop()
        generation &+= 1
        let installedGeneration = generation
        directorySource = makeSource(
            path: directory.path,
            generation: installedGeneration,
            events: [.write, .extend, .attrib, .delete, .rename, .revoke])
        fileSource = makeSource(
            path: fileURL.path,
            generation: installedGeneration,
            events: [.write, .extend, .attrib, .delete, .rename, .revoke])
    }

    func stop() {
        generation &+= 1
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
    }

    private func makeSource(
        path: String,
        generation installedGeneration: Int,
        events: DispatchSource.FileSystemEvent
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = Darwin.open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: events,
            queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == installedGeneration else { return }
                self.stop()
                self.onChange?()
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        return source
    }
}
