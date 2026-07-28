import AppKit
import Carbon.HIToolbox

@MainActor
final class AppCore {
    static let shared = AppCore()
    let settings = AppSettings()
}

@MainActor
final class AppSettings {
    var hyperKey: HyperKeyPhysicalKey = .none
    var hyperKeyReplacesGlyph = false
    var hyperKeyIncludesShift = false
}

enum HyperKeyPhysicalKey {
    case none

    static let hyperGlyph = "✦"
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

@main
struct HotKeyTest {
    static func main() throws {
        let legacyJSON = #"{"carbonKeyCode":12,"carbonModifiers":256}"#
        let legacy = try JSONDecoder().decode(KeyShortcut.self, from: Data(legacyJSON.utf8))
        expect(legacy == KeyShortcut(carbonKeyCode: 12, carbonModifiers: cmdKey), "legacy equality")
        let reencoded = try JSONEncoder().encode(legacy)
        let legacyObject = try JSONSerialization.jsonObject(with: reencoded) as? [String: Int]
        expect(
            legacyObject == ["carbonKeyCode": 12, "carbonModifiers": cmdKey],
            "legacy encoding"
        )

        let leftCommand = KeyShortcut(
            carbonKeyCode: 12,
            carbonModifiers: cmdKey,
            sideModifiers: .init([.leftCommand])
        )
        let rightCommand = KeyShortcut(
            carbonKeyCode: 12,
            carbonModifiers: cmdKey,
            sideModifiers: .init([.rightCommand])
        )
        expect(legacy.conflicts(with: leftCommand), "legacy conflicts with side-aware")
        expect(leftCommand.conflicts(with: leftCommand), "same side conflicts")
        expect(!leftCommand.conflicts(with: rightCommand), "opposite sides are distinct")

        var state = SideModifierState()
        state.handleFlagsChanged(keyCode: kVK_Command)
        expect(
            SideHotKeyMatcher.matches(
                leftCommand,
                keyCode: 12,
                modifierFlags: [.command],
                pressedModifiers: state.pressedModifiers),
            "left modifier matches"
        )
        state.handleFlagsChanged(keyCode: kVK_Command)
        expect(state.pressedModifiers.isEmpty, "modifier release clears state")
        expect(
            !SideHotKeyMatcher.matches(
                leftCommand,
                keyCode: 12,
                modifierFlags: [.command],
                pressedModifiers: state.pressedModifiers),
            "released modifier does not match"
        )
        state.handleFlagsChanged(keyCode: kVK_RightCommand)
        state.reset()
        expect(state.pressedModifiers.isEmpty, "reset clears stale modifier state")
    }
}
