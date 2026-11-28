import Foundation
import Observation
import os

/// One extension process, from spawn to exit: its link, its latest render and the calls it makes.
@MainActor
@Observable
final class ExtensionSession {
    /// `spawning` until the slot is free and the checks pass; `stopping` still answers requests.
    enum State: Sendable, Equatable {
        case spawning, running, stopping, gone
    }

    typealias Perform = @MainActor (ExtensionWire.HostCall) -> Result<String?, ExtensionWire.HostCallError>
    private typealias Link = ProcessLink<ExtensionWire.ToExtension, ExtensionWire.ToMainApp>

    let extensionID: String
    let start: ExtensionWire.Start
    private(set) var state = State.spawning
    private(set) var ui: ExtensionUI?
    private(set) var revision = 0
    /// Set while a surface shows it; the idle delay counts only while nothing does.
    @ObservationIgnored var isShown = false {
        didSet { lastActivity = .now }
    }
    @ObservationIgnored var onFinish: ((_ hud: String?) -> Void)?
    /// Once, whichever way the session ends.
    @ObservationIgnored var onGone: (() -> Void)?

    @ObservationIgnored private let executable: URL
    @ObservationIgnored private let perform: Perform
    @ObservationIgnored private let idleDelay: Duration
    @ObservationIgnored private let stopTimeout: Duration
    @ObservationIgnored private let standardErrorLimit: Int
    @ObservationIgnored private var link: Link?
    @ObservationIgnored private var lastActivity = ContinuousClock.now
    @ObservationIgnored private var idleTimer: Task<Void, Never>?
    @ObservationIgnored private var killTimer: Task<Void, Never>?

    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abueammar.tinycast", category: "Extensions")

    init(
        extensionID: String, executable: URL, start: ExtensionWire.Start,
        idleDelay: Duration = .seconds(30), stopTimeout: Duration = .seconds(5),
        standardErrorLimit: Int = 16 << 10, perform: @escaping Perform
    ) {
        self.extensionID = extensionID
        self.executable = executable
        self.start = start
        self.idleDelay = idleDelay
        self.stopTimeout = stopTimeout
        self.standardErrorLimit = standardErrorLimit
        self.perform = perform
    }

    /// Spawns the process and sends `start`; a failure ends the session before it throws.
    func launch() throws {
        guard state == .spawning else { return }
        let errors = Pipe()
        let link: Link
        do {
            link = try Link.spawn(
                executable, arguments: [], maximumFrameBytes: ExtensionWire.maximumFrameBytes,
                standardError: errors)
        } catch {
            end()
            throw error
        }
        Self.keepTail(of: errors.fileHandleForReading, limit: standardErrorLimit, extensionID: extensionID)
        self.link = link
        link.onReceive = { [weak self] in self?.receive($0) }
        link.onClose = { [weak self] _ in self?.end() }
        link.start()
        state = .running
        link.send(.start(start))
        lastActivity = .now
        startIdleTimer()
    }

    /// Carries the revision of the render the user saw when they acted.
    func send(_ input: ExtensionWire.Input) {
        guard state == .running else { return }
        lastActivity = .now
        link?.send(.event(ExtensionWire.Event(revision: revision, input: input)))
    }

    func stop(_ reason: ExtensionWire.Stop.Reason) {
        switch state {
        case .spawning:
            end()
        case .running:
            state = .stopping
            idleTimer?.cancel()
            link?.send(.stop(ExtensionWire.Stop(reason: reason)))
            killTimer = Task { [weak self, stopTimeout] in
                try? await Task.sleep(for: stopTimeout)
                guard !Task.isCancelled, let self, state == .stopping else { return }
                Self.logger.error("\(self.extensionID, privacy: .public) outlived its stop and was killed")
                link?.terminate()
            }
        case .stopping, .gone:
            return
        }
    }

    private func receive(_ message: ExtensionWire.ToMainApp) {
        lastActivity = .now
        switch message {
        case .request(let request):
            reply(to: request)
        case .render(let render):
            guard state == .running, render.revision > revision else { return }
            revision = render.revision
            ui = render.ui
        case .finish(let finish):
            guard state == .running else { return }
            onFinish?(finish.hud)
            stop(.closed)
        }
    }

    /// A text reply can pass the frame limit, and sent as is it would close the link instead.
    private func reply(to request: ExtensionWire.Request) {
        var result = perform(request.call)
        if case .success(let text?) = result,
            (try? PipeFraming.encode(text, maximum: ExtensionWire.maximumFrameBytes - 1024)) == nil
        {
            result = .failure(.failure(message: "The reply is larger than one frame."))
        }
        link?.send(.reply(ExtensionWire.Reply(id: request.id, result: result)))
    }

    private func end() {
        guard state != .gone else { return }
        state = .gone
        idleTimer?.cancel()
        killTimer?.cancel()
        onGone?()
    }

    /// One task re-reads `lastActivity` when it wakes, so traffic never restarts a timer.
    private func startIdleTimer() {
        idleTimer = Task { [weak self] in
            while let wake = self?.idleDeadline {
                try? await Task.sleep(until: wake, clock: .continuous)
                guard !Task.isCancelled, let self else { return }
                if !isShown, ContinuousClock.now >= lastActivity + idleDelay { return stop(.idle) }
            }
        }
    }

    private var idleDeadline: ContinuousClock.Instant? {
        guard state == .running else { return nil }
        return isShown ? .now + idleDelay : lastActivity + idleDelay
    }

    /// Read all the time, or a full pipe blocks the extension; only the end is kept for the log.
    private nonisolated static func keepTail(of handle: FileHandle, limit: Int, extensionID: String) {
        DispatchQueue(label: "com.tinycast.extension.stderr").async {
            var tail = Data()
            while let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty {
                tail.append(chunk)
                if tail.count > limit { tail.removeFirst(tail.count - limit) }
            }
            // The cut can land inside a character; its continuation bytes go with it.
            while let first = tail.first, first & 0xC0 == 0x80 { tail.removeFirst() }
            guard let text = String(bytes: tail, encoding: .utf8), !text.isEmpty else { return }
            logger.debug("\(extensionID, privacy: .public) wrote: \(text, privacy: .private)")
        }
    }
}
