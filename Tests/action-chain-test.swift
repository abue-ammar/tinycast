import Foundation

@main
@MainActor
struct ActionChainTests {
    static var failures = 0
    static var passes = 0

    static func main() async {
        let first = ActionChainStep.application(bundleID: "com.apple.Safari")
        let second = ActionChainStep.windowCommand(id: "left-half")
        let chain = ActionChain(name: "Focus", steps: [first, second])

        var performed: [ActionChainStep] = []
        let completed = await ActionChainRunner.run(chain) { step in
            performed.append(step)
        }
        expect(performed == [first, second], "runs every step in order")
        expect(completed == .completed, "reports a completed chain")

        if let encoded = try? JSONEncoder().encode(chain),
            let decoded = try? JSONDecoder().decode(ActionChain.self, from: encoded)
        {
            expect(decoded == chain, "round-trips a chain through JSON")
        } else {
            expect(false, "round-trips a chain through JSON")
        }

        let defaults = UserDefaults(suiteName: "action-chain-test-\(UUID().uuidString)")!
        if let stored = try? ActionChainStore(defaults: defaults).add(chain) {
            expect(
                ActionChainStore(defaults: defaults).chain(id: stored.id) == chain,
                "loads a persisted chain after a store reload")
        } else {
            expect(false, "loads a persisted chain after a store reload")
        }

        let blocked = ActionChainStep.systemAction(id: "lock-screen")
        let skipped = ActionChainStep.quicklink(id: UUID())
        var attempted: [ActionChainStep] = []
        let failed = await ActionChainRunner.run(ActionChain(name: "Stop", steps: [first, blocked, skipped]))
        { step in
            attempted.append(step)
            if step == blocked { throw ActionChainFailure.unavailable }
        }
        expect(attempted == [first, blocked], "stops after the first failed step")
        expect(failed == .failed(step: blocked), "reports the failed step")

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(name)")
        }
    }
}
