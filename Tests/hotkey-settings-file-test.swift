import AppKit
import Carbon.HIToolbox
import Foundation

@main
@MainActor
struct HotKeySettingsFileTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(label)")
        }
    }

    static func main() {
        unchangedEntry(
            KeyShortcut(carbonKeyCode: kVK_ANSI_Keypad1, carbonModifiers: cmdKey)
                .usingKeyEquivalent("1"), label: "keypad character")
        unchangedEntry(
            KeyShortcut(carbonKeyCode: kVK_ANSI_K, carbonModifiers: cmdKey)
                .settingSide(.right, for: .command).usingKeyEquivalent("x"),
            label: "character from a different base or Command layout")
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func unchangedEntry(_ shortcut: KeyShortcut, label: String) {
        let original = HotKeyBinding.combo(shortcut)
        let hotKeys = HotKeyManager(bindings: [.togglePalette: original])
        let file = HotKeySettingsFile(hotKeys: hotKeys)
        let binding = file.binding(for: .launcherShortcut, action: .togglePalette, name: "App Launcher")
        let exported = binding.read()
        expect(binding.write(exported).isEmpty, "\(label): rereading a file reports no issue")
        expect(file.commit().isEmpty, "\(label): committing a file reports no conflict")
        expect(hotKeys.writes == 0, "\(label): an unrelated settings edit never clears or rebinds the entry")
        expect(
            hotKeys.binding(for: .togglePalette) == original,
            "\(label): the launcher keeps its full original binding")
        expect(
            hotKeys.binding(for: .togglePalette)?.shortcut?.usingPhysicalKey().carbonKeyCode
                == shortcut.carbonKeyCode, "\(label): returning to Pos keeps its anchor")
    }
}

// The settings adapter runs against in-memory bindings, without Carbon or UserDefaults effects.
@MainActor
final class HotKeyManager {
    private var bindings: [HotKeyAction: HotKeyBinding]
    private(set) var writes = 0

    init(bindings: [HotKeyAction: HotKeyBinding]) {
        self.bindings = bindings
    }

    func binding(for action: HotKeyAction) -> HotKeyBinding? { bindings[action] }

    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        writes += 1
        bindings[action] = binding
    }

    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? { nil }
}
