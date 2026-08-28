import Foundation

/// How a run ended, once it has.
struct CommandOutcome: Sendable {
    let summary: String
    /// The nudge for a failure the reader can fix, when the exit status names one.
    let hint: String?
    let succeeded: Bool
    let finishedAt: Date
}

/// One run of one command, from the moment it starts.
struct CommandRun: Identifiable, Sendable {
    let id = UUID()
    /// Which custom command this was, so the window can run it again.
    let commandID: UUID
    let name: String
    /// The shell text, shown under the name — "brew" alone says nothing about what ran.
    let commandText: String
    let symbol: String
    let startedAt: Date
    /// Everything printed so far, for copying and for a redraw from scratch.
    var log = ""
    /// The most recent append, and a counter for it: one step on means the view can add just this
    /// rather than walk the whole log to work out what changed.
    var delta = ""
    var revision = 0
    /// Bumped when the head of `log` is dropped, which is the text view's cue to redraw whole.
    var generation = 0
    /// Nil while the command is still running.
    var outcome: CommandOutcome?

    var isRunning: Bool { outcome == nil }
}

/// The window a command's output lands in, from launch to exit. One window, reused: a second run
/// replaces what it shows rather than stacking another, so a held-down hotkey can't paper the
/// screen. A superseded run is not cancelled — only the Stop button ends a command.
@MainActor
@Observable
final class CommandOutputPresenter {
    /// Past this the head is dropped: the tail is where a command says how it went.
    private static let logLimit = 256 * 1024

    private(set) var run: CommandRun?

    @ObservationIgnored private let activation: ActivationPolicy
    @ObservationIgnored private let rerun: (UUID) -> Void
    @ObservationIgnored private let stop: (UUID) -> Void
    @ObservationIgnored private let openSettings: () -> Void
    @ObservationIgnored private lazy var window = AppWindowController(
        title: "Command Output", contentSize: CommandOutputView.initialSize, resizable: true,
        autosaveName: "CommandOutputWindow", activation: activation)

    init(
        activation: ActivationPolicy, rerun: @escaping (UUID) -> Void,
        stop: @escaping (UUID) -> Void, openSettings: @escaping () -> Void
    ) {
        self.activation = activation
        self.rerun = rerun
        self.stop = stop
        self.openSettings = openSettings
    }

    /// Opens the window on an empty, running command and returns the id the run reports against.
    @discardableResult
    func begin(commandID: UUID, name: String, commandText: String, symbol: String) -> UUID {
        let run = CommandRun(
            commandID: commandID, name: name, commandText: commandText, symbol: symbol,
            startedAt: Date())
        self.run = run
        window.show { CommandOutputView(presenter: self) }
        return run.id
    }

    func append(_ text: String, to id: UUID) {
        guard var run, run.id == id else { return }
        run.log += text
        run.delta = text
        run.revision += 1
        if run.log.utf8.count > Self.logLimit {
            run.log = String(run.log.suffix(Self.logLimit / 2))
            // The delta no longer describes the change, so the view is told to redraw instead.
            run.generation += 1
        }
        self.run = run
    }

    func finish(_ outcome: CommandOutcome, for id: UUID) {
        guard var run, run.id == id else { return }
        run.outcome = outcome
        self.run = run
    }

    // MARK: - Actions the window offers

    func runAgain() {
        guard let run else { return }
        rerun(run.commandID)
    }

    func stopRunning() {
        guard let run, run.isRunning else { return }
        stop(run.id)
    }

    func showCommandSettings() {
        openSettings()
    }

    /// Re-raise an open output window; false when none is up, so a reopen falls through.
    func focusExisting() -> Bool {
        window.focus()
    }
}
