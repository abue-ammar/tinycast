import Foundation
import Synchronization

final class FakeMonitorTransport: MonitorHardwareTransport, Sendable {
    struct State: Sendable {
        var values: [MonitorControlKind: MonitorControlValue] = [
            .brightness: .init(current: 50, maximum: 100),
            .volume: .init(current: 20, maximum: 100),
            .mute: .init(current: 2, maximum: 100)
        ]
        var writes: [(MonitorControlKind, UInt16)] = []
        var enteredWrite = false
        var blocked = false
        var fail = false
        var readbackLag = 0
        var staleReads: [MonitorControlKind: Int] = [:]
        var previous: [MonitorControlKind: MonitorControlValue] = [:]
        var missingReadback = false
        var quantize = false
        var reads = 0
        var readQuietTime: Duration = .zero
        var lastWrite: ContinuousClock.Instant?
        var failReads = 0
        var failWrites = 0
        var blockedRead = false
        var enteredRead = false
    }

    let state = Mutex(State())
    var available: Bool { true }

    func discover(_ screens: [MonitorDDCTransport.Screen], valid: () -> Bool) -> [MonitorKeyRouting.Display] {
        guard valid() else { return [] }
        return screens.map { screen in
            .init(id: screen.id, name: screen.name, bounds: screen.bounds, values: state.withLock { $0.values })
        }
    }

    func read(_ display: UInt32, control: MonitorControlKind, valid: () -> Bool) -> MonitorControlValue? {
        state.withLock { $0.enteredRead = true }
        while state.withLock({ $0.blockedRead }) && valid() { Thread.sleep(forTimeInterval: 0.005) }
        guard valid() else { return nil }
        return state.withLock {
            $0.reads += 1
            guard !$0.fail else { return nil }
            if $0.failReads > 0 { $0.failReads -= 1; return nil }
            if let lastWrite = $0.lastWrite, lastWrite.duration(to: .now) < $0.readQuietTime { return nil }
            if $0.staleReads[control, default: 0] > 0 {
                $0.staleReads[control, default: 0] -= 1
                return $0.missingReadback ? nil : $0.previous[control]
            }
            return $0.values[control]
        }
    }

    func write(_ display: UInt32, control: MonitorControlKind, value: UInt16, valid: () -> Bool) -> Bool {
        state.withLock { $0.enteredWrite = true }
        while state.withLock({ $0.blocked }) && valid() { Thread.sleep(forTimeInterval: 0.005) }
        guard valid() else { return false }
        return state.withLock {
            $0.writes.append((control, value))
            guard !$0.fail else { return false }
            if $0.failWrites > 0 { $0.failWrites -= 1; return false }
            $0.lastWrite = .now
            $0.previous[control] = $0.values[control]
            $0.staleReads[control] = $0.readbackLag
            $0.values[control]?.current = $0.quantize ? value / 5 * 5 : value
            return true
        }
    }
}

@main
struct MonitorSessionTests {
    final class Received: Sendable {
        let values = Mutex<[MonitorHardwareSession.Result]>([])
    }

    static func eventually(_ check: @Sendable () -> Bool) async {
        for _ in 0..<500 {
            if check() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Timed out waiting for the hardware worker")
    }

    static func command(_ value: UInt16, generation: UInt64 = 1,
                        control: MonitorControlKind = .brightness) -> MonitorKeyRouting.Command {
        .init(generation: generation, displayID: 1, control: control,
              value: .init(current: value, maximum: 100), revision: UInt64(value),
              adjustment: .level(offset: 0, minimum: Int(value), maximum: Int(value)))
    }

    static func main() async {
        await muteDuringVolume()
        await supersededReadback()
        await sustainedKeys()
        await delayedReadback()
        let fake = FakeMonitorTransport()
        let session = MonitorHardwareSession(makeTransport: { fake })
        let received = Received()
        let reader = Task {
            for await result in session.results { received.values.withLock { $0.append(result) } }
        }
        defer { session.stop(); reader.cancel() }
        let screens = [MonitorDDCTransport.Screen(id: 1, name: "Fake", bounds: CGRect())]
        session.discover(generation: 1, screens: screens)
        await eventually { received.values.withLock { !$0.isEmpty } }

        fake.state.withLock { $0.blocked = true }
        session.enqueue(command(10))
        await eventually { fake.state.withLock { $0.enteredWrite } }
        for value in 11...30 { session.enqueue(command(UInt16(value))) }
        fake.state.withLock { $0.blocked = false }
        await eventually { fake.state.withLock { $0.writes.last?.1 == 30 } }
        assert(fake.state.withLock { $0.writes.count == 2 })

        fake.state.withLock { $0.fail = true }
        session.enqueue(command(12, control: .volume))
        await eventually {
            received.values.withLock { values in
                values.contains {
                    if case .applied(let command, nil) = $0 { return command.control == .volume }
                    return false
                }
            }
        }
        let writeCount = fake.state.withLock { $0.writes.count }
        session.enqueue(command(14, control: .volume))
        try? await Task.sleep(for: .milliseconds(50))
        assert(fake.state.withLock { $0.writes.count == writeCount })

        fake.state.withLock { $0.fail = false; $0.values[.mute]?.current = 1 }
        session.discover(generation: 2, screens: screens)
        session.enqueue(command(16, generation: 2, control: .volume))
        await eventually { fake.state.withLock { $0.values[.volume]?.current == 16 && $0.writes.last?.0 == .mute } }
        let countAfterRecovery = fake.state.withLock { $0.writes.count }
        session.enqueue(command(80, generation: 1))
        try? await Task.sleep(for: .milliseconds(50))
        assert(fake.state.withLock { $0.writes.count == countAfterRecovery })

        fake.state.withLock { $0.enteredWrite = false; $0.blocked = true }
        session.enqueue(command(90, generation: 2))
        await eventually { fake.state.withLock { $0.enteredWrite } }
        session.discover(generation: 3, screens: [])
        fake.state.withLock { $0.blocked = false }
        await eventually {
            received.values.withLock { values in
                values.contains {
                    if case .discovered(3, let displays, _) = $0 { return displays.isEmpty }
                    return false
                }
            }
        }
        assert(fake.state.withLock { $0.writes.count == countAfterRecovery })
        print("Monitor worker coalescing, failure, recovery and disconnect tests passed")
    }

    static func delayedReadback() async {
        let fake = FakeMonitorTransport()
        fake.state.withLock { $0.readbackLag = 2 }
        let session = MonitorHardwareSession(makeTransport: { fake })
        defer { session.stop() }
        var results = session.results.makeAsyncIterator()
        session.discover(generation: 1, screens: [.init(id: 1, name: "Fake", bounds: CGRect())])
        _ = await results.next()
        session.enqueue(command(48))
        guard case .applied(_, let value) = await results.next() else { fatalError("Missing result") }
        assert(value?.current == 48, "Delayed readback must not disable a working monitor")

        fake.state.withLock { $0.missingReadback = true }
        session.enqueue(command(46))
        guard case .applied(_, let recovered) = await results.next() else { fatalError("Missing result") }
        assert(recovered?.current == 46, "Temporary missing replies must recover before disabling control")

        fake.state.withLock { $0.missingReadback = false; $0.blocked = true; $0.enteredWrite = false }
        session.enqueue(command(44))
        await eventually { fake.state.withLock { $0.enteredWrite } }
        for level in stride(from: 42, through: 0, by: -2) { session.enqueue(command(UInt16(level))) }
        fake.state.withLock { $0.blocked = false }
        guard case .applied(_, let final) = await results.next() else { fatalError("Missing held-key result") }
        assert(final?.current == 0, "Held down must reach zero without losing control")
        let count = fake.state.withLock { $0.writes.count }
        for _ in 0..<5 {
            session.enqueue(command(0))
            guard case .applied(_, let minimum) = await results.next() else { fatalError("Missing minimum result") }
            assert(minimum?.current == 0)
        }
        assert(fake.state.withLock { $0.writes.count == count }, "Repeats at minimum must not rewrite hardware")

        fake.state.withLock { $0.quantize = true; $0.readbackLag = 0 }
        session.enqueue(command(12))
        guard case .applied(_, let rounded) = await results.next() else { fatalError("Missing rounded result") }
        assert(rounded?.current == 10, "Valid hardware rounding must reconcile, not disable the monitor")
        session.enqueue(command(20))
        guard case .applied(_, let next) = await results.next() else { fatalError("Missing subsequent press") }
        assert(next?.current == 20, "A subsequent press must still control the monitor")

        fake.state.withLock { $0.readbackLag = 2; $0.enteredWrite = false }
        session.enqueue(command(25))
        await eventually { fake.state.withLock { $0.enteredWrite } }
        session.discover(generation: 2, screens: [])
        guard case .discovered(2, let displays, _) = await results.next() else {
            fatalError("Disconnect while settling must discard the stale result")
        }
        assert(displays.isEmpty)
    }

    static func muteDuringVolume() async {
        let fake = FakeMonitorTransport()
        let session = MonitorHardwareSession(makeTransport: { fake })
        defer { session.stop() }
        var results = session.results.makeAsyncIterator()
        session.discover(generation: 1, screens: [.init(id: 1, name: "Fake", bounds: CGRect())])
        _ = await results.next()
        session.enqueue(command(25, control: .volume))
        await eventually { fake.state.withLock { $0.values[.volume]?.current == 25 } }
        session.enqueue(.init(generation: 1, displayID: 1, control: .mute,
                              value: .init(current: 1, maximum: 100), revision: 26, adjustment: .mute(toggle: true)))
        for _ in 0..<2 {
            guard case .applied(_, let value) = await results.next() else { fatalError("Unexpected mute result") }
            assert(value != nil, "A newer mute press must not fail earlier volume verification")
        }
        assert(fake.state.withLock { $0.values[.mute]?.current == 1 })
    }

    static func supersededReadback() async {
        let fake = FakeMonitorTransport()
        let session = MonitorHardwareSession(makeTransport: { fake })
        defer { session.stop() }
        var results = session.results.makeAsyncIterator()
        session.discover(generation: 1, screens: [.init(id: 1, name: "Fake", bounds: CGRect())])
        _ = await results.next()
        session.enqueue(command(30))
        await eventually { fake.state.withLock { $0.enteredWrite } }
        fake.state.withLock { $0.enteredRead = false; $0.blockedRead = true }
        await eventually { fake.state.withLock { $0.enteredRead } }
        session.enqueue(command(35))
        await eventually { fake.state.withLock { $0.values[.brightness]?.current == 35 } }
        fake.state.withLock { $0.blockedRead = false }
        guard case .applied(let command, let value) = await results.next() else { fatalError("Missing latest readback") }
        assert(command.revision == 35 && value?.current == 35, "New input must supersede an in-flight read without failure")
    }

    static func sustainedKeys() async {
        let fake = FakeMonitorTransport()
        fake.state.withLock { $0.readQuietTime = .milliseconds(250); $0.failReads = 1; $0.failWrites = 1 }
        let session = MonitorHardwareSession(makeTransport: { fake })
        let received = Received()
        let reader = Task {
            for await result in session.results { received.values.withLock { $0.append(result) } }
        }
        defer { session.stop(); reader.cancel() }
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        session.discover(generation: 1, screens: [.init(id: 1, name: "Fake", bounds: bounds)])
        await eventually { received.values.withLock { !$0.isEmpty } }
        var router = MonitorKeyRouting()
        router.generation = 1
        router.enabled = true
        router.displays = [.init(id: 1, name: "Fake", bounds: bounds, values: fake.state.withLock { $0.values })]
        for action: MonitorMediaKey.Action in [.brightnessUp, .brightnessDown] {
            let readsBefore = fake.state.withLock { $0.reads }
            let resultsBefore = received.values.withLock { $0.count }
            var feedback = MonitorFeedbackState()
            for index in 0..<100 {
                let key = MonitorMediaKey(action: action, pressed: true, repeated: index > 0, flags: 0,
                                          token: action.rawValue)
                let route = router.handle(key, point: CGPoint(x: 50, y: 50))
                guard let command = route.command else { fatalError("Held key lost its target") }
                feedback.begin(command)
                session.enqueue(command)
                try? await Task.sleep(for: .milliseconds(20))
                assert(feedback.pending, "HUD must remain held throughout a sustained key press")
            }
            assert(fake.state.withLock { $0.reads - readsBefore <= 1 }, "No readback traffic during key repeats")
            assert(received.values.withLock { $0.count == resultsBefore }, "Only the settled result is published")
            _ = router.handle(.init(action: action, pressed: false, repeated: false, flags: 0, token: action.rawValue),
                              point: CGPoint(x: 50, y: 50))
            await eventually { received.values.withLock { $0.count > resultsBefore } }
            guard case .applied(let command, let value) = received.values.withLock({ $0.last }) else {
                fatalError("Missing final readback")
            }
            assert(value?.current == (action == .brightnessUp ? 100 : 0))
            assert(router.complete(command, value: value), "Settled result must reconcile routing")
            assert(feedback.finish(command, failed: value == nil) && !feedback.pending)
            assert(router.displays[0].values[.brightness] != nil, "Monitor must remain supported")
        }
        assert(fake.state.withLock { $0.writes.count < 100 }, "Repeats must coalesce and skip duplicate endpoints")
    }
}
