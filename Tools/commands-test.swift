import Foundation

/// Minimal test double: `CommandRegistry` only needs the launcher entry's value shape.
struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case application
        case systemSettings
        case command
    }

    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let kind: Kind
}

@main
struct CommandsTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        check(
            "lock screen has a stable command ID",
            CommandID.lockScreen.rawValue == "command:lock-screen")
        check("lock screen has the expected title", CommandID.lockScreen.name == "Lock Screen")
        check("lock screen has an SF Symbol", CommandID.lockScreen.sfSymbol == "lock.fill")
        check("lock screen maps to its system action", CommandID.lockScreen.systemAction == .lockScreen)

        check("sleep has a stable command ID", CommandID.sleep.rawValue == "command:sleep")
        check("sleep has the expected title", CommandID.sleep.name == "Sleep")
        check("sleep has an SF Symbol", CommandID.sleep.sfSymbol == "moon.zzz.fill")
        check("sleep maps to its system action", CommandID.sleep.systemAction == .sleep)

        let names = CommandRegistry.all.map(\.name)
        check(
            "the registry includes both system commands",
            names.contains("Lock Screen") && names.contains("Sleep"))
        check(
            "the registry remains alphabetically sorted",
            names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        check(
            "registry entries round-trip to command IDs",
            CommandRegistry.all.allSatisfy { CommandRegistry.command(for: $0) != nil })

        var calls: [SystemAction] = []
        let lockSucceeded = SystemActions.perform(
            .lockScreen,
            lockScreen: {
                calls.append(.lockScreen)
                return .success
            },
            sleep: {
                calls.append(.sleep)
                return .systemFailure
            })
        check("lock dispatch reports the selected handler result", lockSucceeded == .success)
        check("lock dispatch invokes only the lock handler", calls == [.lockScreen])

        calls.removeAll()
        let sleepSucceeded = SystemActions.perform(
            .sleep,
            lockScreen: {
                calls.append(.lockScreen)
                return .systemFailure
            },
            sleep: {
                calls.append(.sleep)
                return .success
            })
        check("sleep dispatch reports the selected handler result", sleepSucceeded == .success)
        check("sleep dispatch invokes only the sleep handler", calls == [.sleep])

        calls.removeAll()
        let denied = SystemActions.perform(
            .lockScreen,
            lockScreen: {
                calls.append(.lockScreen)
                return .permissionDenied
            },
            sleep: {
                calls.append(.sleep)
                return .success
            })
        check("a rejected system action preserves the reason", denied == .permissionDenied)
        check("a rejected action still invokes only its handler", calls == [.lockScreen])

        let failed = SystemActions.perform(
            .sleep,
            lockScreen: { .success },
            sleep: { .systemFailure })
        check("a system failure remains distinct from permission denial", failed == .systemFailure)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
