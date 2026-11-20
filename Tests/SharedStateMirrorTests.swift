import Foundation

/// Settings' defaults edits round-trip through the main app without losing or echoing a value.
@main
enum SharedStateMirrorTests {
    @MainActor
    static func main() throws {
        var failures = 0
        var checks = 0
        func check(_ name: String, _ passed: Bool) {
            checks += 1
            if !passed {
                failures += 1
                print("FAIL \(name)")
            }
        }

        try checkDefaultsRoundTrip(check)

        print("\(checks - failures)/\(checks) shared state checks passed")
        if failures > 0 { exit(1) }
    }

    @MainActor
    private static func checkDefaultsRoundTrip(_ check: (String, Bool) -> Void) throws {
        let mainDomain = "settings-mirror-main-\(UUID())"
        let settingsDomain = "settings-mirror-child-\(UUID())"
        let main = try require(UserDefaults(suiteName: mainDomain))
        let settings = try require(UserDefaults(suiteName: settingsDomain))
        defer {
            main.removePersistentDomain(forName: mainDomain)
            settings.removePersistentDomain(forName: settingsDomain)
        }
        let aliases = "launcherAliases"
        main.set(["existing": "existing", "removed": "old"], forKey: aliases)
        settings.set(["existing": "existing", "removed": "old"], forKey: aliases)

        var states: [SharedDefaultsState] = []
        var edits: [SharedDefaultsEdit] = []
        let owner = SharedDefaultsMirror(role: .main, defaults: main, domainName: mainDomain, reload: {}) {
            if case .defaultsState(let state) = $0 { states.append(state) }
        }
        let peer = SharedDefaultsMirror(
            role: .settings, defaults: settings, domainName: settingsDomain, reload: {}
        ) {
            if case .defaultsEdit(let edit) = $0 { edits.append(edit) }
        }
        owner.start()
        peer.start()

        main.set(["existing": "main edit", "removed": "old"], forKey: aliases)
        owner.flush()
        settings.set(["existing": "existing", "added": "first edit"], forKey: aliases)
        peer.apply(try require(states.first))
        check(
            "an incoming update preserves a pending edit and removal",
            settings.dictionary(forKey: aliases) as? [String: String] == [
                "existing": "main edit", "added": "first edit"
            ])

        owner.apply(try require(edits.first))
        settings.set(["existing": "main edit", "added": "second edit"], forKey: aliases)
        peer.apply(try require(states.last))
        check(
            "an acknowledgement preserves an edit made while the earlier edit was in flight",
            settings.dictionary(forKey: aliases) as? [String: String] == [
                "existing": "main edit", "added": "second edit"
            ])

        owner.apply(try require(edits.last))
        peer.apply(try require(states.last))
        let expected = ["existing": "main edit", "added": "second edit"]
        check(
            "both stores converge after acknowledgement",
            main.dictionary(forKey: aliases) as? [String: String] == expected
                && settings.dictionary(forKey: aliases) as? [String: String] == expected)
        peer.flush()
        owner.flush()
        check("applied states do not echo", edits.count == 2 && states.count == 3)

        main.set(false, forKey: "switch")
        settings.set(true, forKey: "switch")
        owner.flush()
        peer.apply(try require(states.last))
        check("a pending scalar remains visible until acknowledgement", settings.bool(forKey: "switch"))
        owner.apply(try require(edits.last))
        peer.apply(try require(states.last))
        check(
            "a scalar conflict resolves in the main app's edit order",
            main.bool(forKey: "switch") && settings.bool(forKey: "switch"))
    }

    private static func require<Value>(_ value: Value?) throws -> Value {
        guard let value else { throw CocoaError(.coderValueNotFound) }
        return value
    }
}
