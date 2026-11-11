import Foundation

@main
@MainActor
struct DictationKeyTests {
    static var failures = 0

    static func main() {
        for sharedPreferences in [false, true] {
            for termination in [false, true] {
                handoff(sharedPreferences: sharedPreferences, termination: termination)
            }
        }
        cancelRetry(termination: false)
        cancelRetry(termination: true)
        print(failures == 0 ? "All Dictation key checks passed" : "\(failures) Dictation key check(s) failed")
        if failures > 0 { exit(1) }
    }

    static func check(_ name: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL") \(name)")
        if !condition { failures += 1 }
    }

    static func wait(until condition: () -> Bool, timeout: TimeInterval = 2.5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    static func fixture(
        sharedPreferences: Bool = true,
        _ body: (DictationKeyManager, DictationKeyManager, HotKeyManager, HotKeyManager, URL) -> Void
    ) {
        HIDEventSystem.reset()
        let domain = "tinycast.dictation-key-test.\(UUID())"
        let ownerDefaults = UserDefaults(suiteName: domain)!
        let waitingDefaults = sharedPreferences ? ownerDefaults : UserDefaults(suiteName: domain + ".dev")!
        let lockURL = FileManager.default.temporaryDirectory.appending(path: "\(domain).lock")
        let ownerKeys = HotKeyManager()
        let waitingKeys = HotKeyManager()
        let owner = DictationKeyManager(hotKeys: ownerKeys, defaults: ownerDefaults, lockURL: lockURL)
        let waiting = DictationKeyManager(hotKeys: waitingKeys, defaults: waitingDefaults, lockURL: lockURL)
        let ticker = HealthTicker()
        owner.healthTicker = ticker
        waiting.healthTicker = ticker
        defer {
            owner.prepareForTermination()
            waiting.prepareForTermination()
            ownerDefaults.removePersistentDomain(forName: domain)
            waitingDefaults.removePersistentDomain(forName: domain + ".dev")
            try? FileManager.default.removeItem(at: lockURL)
            withExtendedLifetime(ticker) {}
        }
        owner.start()
        waiting.start()
        body(owner, waiting, ownerKeys, waitingKeys, lockURL)
    }

    static func handoff(sharedPreferences: Bool, termination: Bool) {
        fixture(sharedPreferences: sharedPreferences) { owner, waiting, ownerKeys, _, lockURL in
            let context = "shared=\(sharedPreferences) termination=\(termination)"
            check(
                "\(context): waiting startup preserves F20",
                HIDEventSystem.mappings[1] == [.dictationKeyToF20])
            let contender = RemapInstanceLock(url: lockURL)
            check("\(context): owner holds the lock", !contender.acquire())
            if termination {
                owner.prepareForTermination()
            } else {
                ownerKeys.bindsDictationKey = false
            }
            wait { HIDEventSystem.writeCount >= 3 }
            check(
                "\(context): watchdog restores F20 after handoff",
                HIDEventSystem.mappings[1] == [.dictationKeyToF20])
            check("\(context): waiting copy acquired ownership", !contender.acquire())
            check("\(context): handoff removed then restored the mapping", HIDEventSystem.writeCount == 3)
            waiting.prepareForTermination()
            check("\(context): stopping the new owner restores the key", HIDEventSystem.mappings[1] == [])
            check("\(context): stopping releases ownership immediately", contender.acquire())
            contender.release()
        }
    }

    static func cancelRetry(termination: Bool) {
        fixture { owner, waiting, _, waitingKeys, lockURL in
            if termination {
                waitingKeys.recordingAction = 1
                waiting.prepareForTermination()
            } else {
                waitingKeys.bindsDictationKey = false
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            owner.prepareForTermination()
            let writes = HIDEventSystem.writeCount
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            check(
                "cancel termination=\(termination): no retry after stop", HIDEventSystem.writeCount == writes)
            check("cancel termination=\(termination): key stays restored", HIDEventSystem.mappings[1] == [])
            let contender = RemapInstanceLock(url: lockURL)
            check("cancel termination=\(termination): lock stays free", contender.acquire())
            contender.release()
        }
    }
}
