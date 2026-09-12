import Foundation

/// Every command's row metadata in one small file, deliberately not in `extension-data`: drawing a
/// launcher row must never fault in an extension's whole `LocalStorage` and `Cache`.
@MainActor
@Observable
final class ExtensionCommandMetadataStore {
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    private var records: [String: [String: ExtensionCommandMetadata]]

    init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        records =
            (try? Data(contentsOf: fileURL))
            .flatMap {
                try? JSONDecoder().decode(
                    [String: [String: ExtensionCommandMetadata]].self, from: $0)
            } ?? [:]
    }

    func metadata(extension name: String, command: String) -> ExtensionCommandMetadata {
        records[name]?[command] ?? ExtensionCommandMetadata()
    }

    func setSubtitle(_ subtitle: String?, extension name: String, command: String) {
        mutate(name, command) { $0.subtitle = subtitle }
    }

    func setBackgroundEnabled(_ enabled: Bool, extension name: String, command: String) {
        mutate(name, command) { $0.backgroundEnabled = enabled }
    }

    /// Disabling retires the last error with the schedule; a stale warning would outlive its cause.
    func clearBackgroundError(extension name: String, command: String) {
        mutate(name, command) {
            $0.lastError = nil
            $0.consecutiveFailures = 0
        }
    }

    /// A manual run counts as a refresh, so the scheduler doesn't re-fire right behind it.
    func activateBackgroundRefresh(extension name: String, command: String, now: Date) {
        mutate(name, command) {
            $0.backgroundEnabled = true
            $0.lastRun = now
        }
    }

    func recordBackgroundResult(
        extension name: String, command: String, success: Bool, error: String?, now: Date
    ) {
        mutate(name, command) {
            $0.lastRun = now
            $0.lastError = success ? nil : error
            $0.consecutiveFailures = success ? 0 : $0.consecutiveFailures + 1
        }
    }

    func removeAll(extension name: String) {
        guard records.removeValue(forKey: name) != nil else { return }
        scheduleFlush()
    }

    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard isDirty, let data = try? JSONEncoder().encode(records) else { return }
        isDirty = false
        try? data.write(to: fileURL, options: .atomic)
    }

    private func mutate(
        _ name: String, _ command: String, _ body: (inout ExtensionCommandMetadata) -> Void
    ) {
        var record = records[name]?[command] ?? ExtensionCommandMetadata()
        body(&record)
        records[name, default: [:]][command] = record
        scheduleFlush()
    }

    /// Ticks write on a timer, so the file is coalesced the way `ExtensionStorage` coalesces its own.
    private func scheduleFlush() {
        isDirty = true
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.flush()
        }
    }
}
