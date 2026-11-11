import AppKit
import Carbon.HIToolbox
import Synchronization

private struct InstallationGate: Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
}

// The immutable callback handles are invoked only on their recorded worker run loop.
private struct TapRecord: @unchecked Sendable {
    let port: CFMachPort
    let runLoop: CFRunLoop
    let callback: CGEventTapCallBack
    let userInfo: UnsafeMutableRawPointer?
    var enables = 0
}

private struct TapFixture {
    var records: [TapRecord] = []
    var attempts = 0
    var failNext = false
    var gate: InstallationGate?
    var wrongConfiguration = false
    var touchedMainThread = false
}

private let fixture = Mutex(TapFixture())

// Module-local overloads exercise the shipped worker without installing a global input filter.
extension CGEvent {
    static func tapCreate(
        tap: CGEventTapLocation, place: CGEventTapPlacement, options: CGEventTapOptions,
        eventsOfInterest: CGEventMask, callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        let (fail, gate) = fixture.withLock { fixture in
            fixture.attempts += 1
            fixture.touchedMainThread = fixture.touchedMainThread || Thread.isMainThread
            fixture.wrongConfiguration =
                fixture.wrongConfiguration
                || tap != .cghidEventTap || place != .headInsertEventTap
                || options != .defaultTap || eventsOfInterest != 1 << CGEventType.keyDown.rawValue
            let fail = fixture.failNext
            fixture.failNext = false
            let gate = fixture.gate
            fixture.gate = nil
            return (fail, gate)
        }
        guard !fail else { return nil }
        var context = CFMachPortContext()
        guard let port = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &context, nil)
        else { return nil }
        fixture.withLock {
            $0.records.append(
                TapRecord(
                    port: port, runLoop: CFRunLoopGetCurrent(), callback: callback, userInfo: userInfo))
        }
        if let gate {
            gate.entered.signal()
            _ = gate.resume.wait(timeout: .now() + 5)
        }
        return port
    }

    static func tapEnable(tap: CFMachPort, enable: Bool) {
        fixture.withLock { fixture in
            fixture.touchedMainThread = fixture.touchedMainThread || Thread.isMainThread
            if enable, let index = fixture.records.firstIndex(where: { $0.port === tap }) {
                fixture.records[index].enables += 1
            }
        }
    }
}

@main
@MainActor
struct CommandEscapeTapTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func waitFor(_ message: String, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        expect(condition(), message)
    }

    private nonisolated static func schedule(
        _ index: Int, _ body: @escaping @Sendable (TapRecord) -> Void
    ) {
        fixture.withLock { fixture in
            let record = fixture.records[index]
            CFRunLoopPerformBlock(record.runLoop, CFRunLoopMode.defaultMode.rawValue) {
                body(record)
            }
            CFRunLoopWakeUp(record.runLoop)
        }
    }

    private nonisolated static func invoke(
        _ record: TapRecord, type: CGEventType = .keyDown,
        keyCode: Int = kVK_Escape, flags: CGEventFlags = .maskCommand
    ) -> Bool {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
        event.flags = flags
        let proxy = OpaquePointer(Unmanaged.passUnretained(record.port).toOpaque())
        return record.callback(proxy, type, event, record.userInfo) == nil
    }

    static func deliver(
        _ index: Int, type: CGEventType = .keyDown,
        keyCode: Int = kVK_Escape, flags: CGEventFlags = .maskCommand
    ) -> Bool? {
        let result = Mutex<Bool?>(nil)
        let completed = DispatchSemaphore(value: 0)
        schedule(index) { record in
            let claimed = invoke(record, type: type, keyCode: keyCode, flags: flags)
            result.withLock { $0 = claimed }
            completed.signal()
        }
        expect(
            completed.wait(timeout: .now() + 2) == .success,
            "the worker returns while the main thread is blocked")
        return result.withLock { $0 }
    }

    static func expectSignal(_ semaphore: DispatchSemaphore, _ message: String) {
        expect(semaphore.wait(timeout: .now() + 2) == .success, message)
    }

    static func isClosed(_ index: Int) -> Bool {
        fixture.withLock { !CFMachPortIsValid($0.records[index].port) }
    }

    static func enables(_ index: Int) -> Int {
        fixture.withLock { $0.records[index].enables }
    }

    static func main() async {
        var fires = 0
        let tap = CommandEscapeTap { fires += 1 }
        tap.enable()
        await waitFor("the tap installs", { fixture.withLock { $0.records.count == 1 } })
        tap.enable()
        expect(fixture.withLock { $0.attempts == 1 }, "repeated enable does not create another worker")
        expect(deliver(0, keyCode: kVK_ANSI_A, flags: []) == false, "ordinary typing passes through")
        expect(deliver(0, flags: [.maskCommand, .maskAlternate]) == false, "Force Quit passes through")
        expect(deliver(0) == true, "the worker swallows Command-Escape without waiting for main")
        expect(fires == 0, "the UI action is queued while main is blocked")
        await waitFor("the UI action arrives on main", { fires == 1 })
        expect(deliver(0, type: .tapDisabledByTimeout) == false, "timeout notification passes through")
        expect(enables(0) == 1, "an active tap recovers from timeout")
        expect(deliver(0, type: .tapDisabledByUserInput) == false, "disable notification passes through")
        expect(enables(0) == 2, "an active tap recovers from user-input disable")

        expect(deliver(0) == true, "a second chord is queued")
        tap.disable()
        tap.enable()
        await waitFor("a new session installs", { fixture.withLock { $0.records.count == 2 } })
        expect(fires == 1, "a queued action cannot affect a reopened palette")
        await waitFor("the previous session tears down", { isClosed(0) })
        expect(deliver(1) == true, "the new session accepts its own chord")
        await waitFor("the new session's action arrives", { fires == 2 })

        let gate = InstallationGate()
        let completed = DispatchSemaphore(value: 0)
        let claimedAfterClose = Mutex<Bool?>(nil)
        let beforeClose = enables(1)
        schedule(1) { record in
            gate.entered.signal()
            _ = gate.resume.wait(timeout: .now() + 5)
            _ = invoke(record, type: .tapDisabledByTimeout)
            _ = invoke(record, type: .tapDisabledByUserInput)
            let claimed = invoke(record)
            claimedAfterClose.withLock { $0 = claimed }
            completed.signal()
        }
        expectSignal(gate.entered, "the late notification is pending")
        tap.disable()
        gate.resume.signal()
        expectSignal(completed, "the late callbacks complete")
        expect(enables(1) == beforeClose, "late notifications cannot resurrect a closed session")
        expect(claimedAfterClose.withLock { $0 } == false, "a closing session stops swallowing chords")
        await waitFor("the stopped run loop exits", { isClosed(1) })

        let installing = InstallationGate()
        fixture.withLock { $0.gate = installing }
        tap.enable()
        expectSignal(installing.entered, "installation is pending")
        tap.disable()
        installing.resume.signal()
        await waitFor("closing during installation cleans up the port", { isClosed(2) })

        fixture.withLock { $0.failNext = true }
        let attempts = fixture.withLock { $0.attempts }
        tap.enable()
        await waitFor(
            "a refused tap can retry on the next enable",
            {
                tap.enable()
                return fixture.withLock { $0.attempts >= attempts + 2 && $0.records.count == 4 }
            })
        expect(deliver(3) == true, "a retried installation handles the chord")
        await waitFor("the retry dispatches normally", { fires == 3 })
        tap.disable()
        await waitFor("the retried tap tears down", { isClosed(3) })

        var disposable: CommandEscapeTap? = CommandEscapeTap {}
        let isReleased = { [weak disposable] in disposable == nil }
        disposable?.enable()
        await waitFor("the disposable tap installs", { fixture.withLock { $0.records.count == 5 } })
        _ = deliver(4, keyCode: kVK_ANSI_A)
        disposable = nil
        expect(isReleased(), "the worker does not retain its owner")
        await waitFor("owner deinit stops the worker", { isClosed(4) })

        for _ in 0..<100 {
            tap.enable()
            tap.disable()
        }
        await waitFor(
            "rapid show and hide leaves no valid ports",
            {
                fixture.withLock { $0.records.allSatisfy { !CFMachPortIsValid($0.port) } }
            })
        expect(fixture.withLock { !$0.wrongConfiguration }, "the tap keeps the required HID signature")
        expect(fixture.withLock { !$0.touchedMainThread }, "tap installation and control stay off main")
        expect(fires == 3, "closed sessions never deliver an action")
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
