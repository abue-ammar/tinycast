import Foundation
import OSLog
import Synchronization

final class MonitorHardwareSession: Sendable {
    enum Result: Sendable {
        case discovered(UInt64, [MonitorKeyRouting.Display], available: Bool)
        case applied(MonitorKeyRouting.Command, MonitorControlValue?)
        case muteState(UInt64, UInt32, MonitorControlValue)
    }

    private struct Control: Hashable, Sendable {
        let display: UInt32
        let kind: MonitorControlKind

        init(_ command: MonitorKeyRouting.Command) {
            display = command.displayID
            kind = command.control
        }

        init(_ display: UInt32, _ kind: MonitorControlKind) {
            self.display = display
            self.kind = kind
        }
    }

    private struct Activity: Sendable {
        let revision: UInt64
        let time: ContinuousClock.Instant
    }

    private struct Inbox: Sendable {
        var queue = MonitorCommandQueue()
        var discovery: (UInt64, [MonitorDDCTransport.Screen])?
        var activity: [Control: Activity] = [:]
    }

    private final class Mailbox: Sendable {
        let state = Mutex(Inbox())

        func valid(_ generation: UInt64) -> Bool {
            !Task.isCancelled && state.withLock { $0.queue.generation == generation }
        }

        func current(_ command: MonitorKeyRouting.Command) -> Bool {
            valid(command.generation) && state.withLock { $0.activity[Control(command)]?.revision == command.revision }
        }

        func settled(_ command: MonitorKeyRouting.Command) -> Bool {
            state.withLock {
                guard let activity = $0.activity[Control(command)] else { return false }
                return activity.revision == command.revision && activity.time.duration(to: .now) >= .milliseconds(350)
            }
        }

        func volumeOwnsMute(_ command: MonitorKeyRouting.Command) -> Bool {
            state.withLock { ($0.activity[Control(command.displayID, .mute)]?.revision ?? 0) <= command.revision }
        }
    }

    private final class Worker {
        let transport: any MonitorHardwareTransport
        let mailbox: Mailbox
        let output: AsyncStream<Result>.Continuation
        var values: [Control: MonitorControlValue] = [:]
        var pending: [Control: MonitorKeyRouting.Command] = [:]
        var failed: Set<Control> = []
        private let logger = Logger(subsystem: "com.tinycast.monitor-control", category: "Hardware")

        init(transport: any MonitorHardwareTransport, mailbox: Mailbox, output: AsyncStream<Result>.Continuation) {
            self.transport = transport
            self.mailbox = mailbox
            self.output = output
        }

        func run() async {
            while !Task.isCancelled {
                if let discovery = mailbox.state.withLock({ state in
                    let discovery = state.discovery
                    state.discovery = nil
                    return discovery
                }) {
                    values.removeAll()
                    pending.removeAll()
                    failed.removeAll()
                    let displays = transport.discover(discovery.1, valid: { self.mailbox.valid(discovery.0) })
                    guard mailbox.valid(discovery.0) else { continue }
                    for display in displays {
                        for (kind, value) in display.values { values[Control(display.id, kind)] = value }
                    }
                    output.yield(.discovered(discovery.0, displays, available: transport.available))
                }
                if let command = mailbox.state.withLock({ $0.queue.next() }) {
                    await apply(command)
                    continue
                }
                guard !pending.isEmpty else { return }
                for command in Array(pending.values) where mailbox.settled(command) {
                    await verify(command)
                }
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }

        func apply(_ command: MonitorKeyRouting.Command) async {
            let key = Control(command)
            let valid = { self.mailbox.valid(command.generation) }
            guard valid(), !failed.contains(key), var current = values[key] else { return }
            let beginning = pending[key] == nil
            if beginning, let refreshed = transport.read(key.display, control: key.kind, valid: valid) {
                current = refreshed
            }
            let target = command.adjustment.apply(to: current)
            let written = target == current ? true : await write(key, value: target.current, valid: valid)
            guard written else {
                if valid() { fail(command, stage: "write") }
                return
            }
            guard valid() else { return }
            values[key] = target
            pending[key] = command
            let mute = Control(key.display, .mute)
            if key.kind == .volume, target.current > 0, let muteValue = values[mute], beginning || muteValue.current != 2 {
                guard await write(mute, value: 2, valid: valid) else {
                    if valid() { fail(command, stage: "unmute write") }
                    return
                }
                values[mute] = .init(current: 2, maximum: muteValue.maximum)
            }
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
        }

        func write(_ key: Control, value: UInt16, valid: () -> Bool) async -> Bool {
            for attempt in 0..<3 {
                guard valid() else { return false }
                if transport.write(key.display, control: key.kind, value: value, valid: valid) { return true }
                do { try await Task.sleep(for: .milliseconds(100 * (attempt + 1))) } catch { return false }
            }
            return false
        }

        func verify(_ command: MonitorKeyRouting.Command) async {
            let key = Control(command)
            let valid = { self.mailbox.current(command) }
            guard let target = values[key], valid() else { return }
            let value = await readSettled(key, target: target.current, valid: valid)
            guard valid() else { return }
            guard let value else { fail(command, stage: "settled readback"); return }
            let mute = Control(key.display, .mute)
            if key.kind == .volume, value.current > 0, values[mute] != nil, mailbox.volumeOwnsMute(command) {
                let muteValid = { valid() && self.mailbox.volumeOwnsMute(command) }
                let muteValue = await readSettled(mute, target: 2, valid: muteValid)
                guard valid() else { return }
                if mailbox.volumeOwnsMute(command) {
                    guard let muteValue, muteValue.current == 2 else { fail(command, stage: "unmute readback"); return }
                    values[mute] = muteValue
                    output.yield(.muteState(command.generation, key.display, muteValue))
                }
            }
            values[key] = value
            pending.removeValue(forKey: key)
            output.yield(.applied(command, value))
        }

        func readSettled(_ key: Control, target: UInt16, valid: () -> Bool) async -> MonitorControlValue? {
            var latest: MonitorControlValue?
            for delay in [80, 160, 320] {
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return nil }
                guard valid() else { return nil }
                if let value = transport.read(key.display, control: key.kind, valid: valid) {
                    latest = value
                    if value.current == target { return value }
                }
            }
            return latest
        }

        func fail(_ command: MonitorKeyRouting.Command, stage: String) {
            let key = Control(command)
            logger.error("Monitor \(key.display) control \(key.kind.rawValue) failed at \(stage, privacy: .public)")
            failed.insert(key)
            pending.removeValue(forKey: key)
            output.yield(.applied(command, nil))
        }
    }

    private let mailbox = Mailbox()
    private let wake: AsyncStream<Void>.Continuation
    private let task: Task<Void, Never>
    let results: AsyncStream<Result>

    init(makeTransport: @escaping @Sendable () -> any MonitorHardwareTransport = { MonitorDDCTransport() }) {
        let (signals, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (results, output) = AsyncStream<Result>.makeStream()
        self.wake = wake
        self.results = results
        let mailbox = self.mailbox
        task = Task.detached(priority: .userInitiated) {
            let worker = Worker(transport: makeTransport(), mailbox: mailbox, output: output)
            defer { output.finish() }
            for await _ in signals {
                guard !Task.isCancelled else { break }
                await worker.run()
            }
        }
    }

    func discover(generation: UInt64, screens: [MonitorDDCTransport.Screen]) {
        mailbox.state.withLock {
            $0.queue.reset(generation: generation)
            $0.activity.removeAll()
            $0.discovery = (generation, screens)
        }
        wake.yield(())
    }

    func enqueue(_ command: MonitorKeyRouting.Command) {
        mailbox.state.withLock {
            guard $0.queue.generation == command.generation else { return }
            $0.queue.enqueue(command)
            $0.activity[Control(command)] = Activity(revision: command.revision, time: .now)
        }
        wake.yield(())
    }

    func stop() {
        task.cancel()
        wake.finish()
    }

    deinit {
        task.cancel()
        wake.finish()
    }
}
