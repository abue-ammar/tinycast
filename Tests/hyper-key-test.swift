import Foundation

@main
@MainActor
struct HyperKeyTest {
    static var failures = 0

    static func main() {
        keyMappingReconcile()
        keyMappingConflicts()
        keyMappingParsing()
        knownApps()
        modifierKeysPreferences()
        karabinerConfig()
        remapperLifecycle()
        print(failures == 0 ? "All hyper key checks passed" : "\(failures) hyper key check(s) failed")
        if failures > 0 { exit(1) }
    }

    static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }

    static let toF18 = HIDKeyMapping.capsLockToF18
    static let toRightControl = HIDKeyMapping.capsLockToRightControl
    static let toF20 = HIDKeyMapping.dictationKeyToF20
    static let otherTool = HIDKeyMapping(source: 0x7_0000_0029, destination: 0x7_0000_0035)

    static func keyMappingReconcile() {
        let otherCapsLock = HIDKeyMapping(source: HIDKeyMapping.capsLock, destination: 0x7_0000_0029)
        check("placing on an empty keyboard adds just ours", toF18.replacingSource(in: []) == [toF18])
        check(
            "placing keeps another tool's entry for a different key",
            toF18.replacingSource(in: [otherTool]) == [otherTool, toF18])
        check(
            "placing replaces another entry for the same key",
            toF18.replacingSource(in: [otherCapsLock, otherTool]) == [otherTool, toF18])
        check(
            "switching routes swaps one Hyper entry for the other",
            toRightControl.replacingSource(in: [toF18, otherTool]) == [otherTool, toRightControl])
        check(
            "an entry already in place is left as it is",
            toF18.replacingSource(in: [otherTool, toF18]) == [otherTool, toF18])
        check(
            "restoring removes only the mapping still owned",
            toF18.restoring([], in: [otherTool, toF18]) == [otherTool])
        check(
            "restoring leaves another tool's replacement alone",
            toF18.restoring([], in: [otherCapsLock]) == [otherCapsLock])
    }

    static func keyMappingConflicts() {
        check("the same key sent elsewhere is a conflict", toF18.conflicts(with: [toRightControl]))
        check("our own mapping already in place is not a conflict", !toF18.conflicts(with: [toF18]))
        check("a mapping for another key is not a conflict", !toF18.conflicts(with: [otherTool]))
    }

    static func keyMappingParsing() {
        let raw: [Any] = [
            [
                HIDKeyMapping.sourceKey: NSNumber(value: HIDKeyMapping.capsLock),
                HIDKeyMapping.destinationKey: NSNumber(value: HIDKeyMapping.f18)
            ],
            [HIDKeyMapping.sourceKey: Int(0x7_0000_0029), HIDKeyMapping.destinationKey: Int(0x7_0000_0035)],
            [HIDKeyMapping.sourceKey: NSNumber(value: HIDKeyMapping.capsLock)],
            "not a mapping"
        ]
        check(
            "a UserKeyMapping array reads numbers and integers, skipping malformed entries",
            HIDKeyMapping.mappings(from: raw) == [toF18, otherTool])
        check("a missing UserKeyMapping reads as no mappings", HIDKeyMapping.mappings(from: nil).isEmpty)
        check(
            "a mapping survives a round trip through its dictionary",
            HIDKeyMapping(dictionary: toRightControl.dictionary) == toRightControl)
    }

    static func knownApps() {
        check(
            "Hyperkey and Superkey block the Hyper Key",
            HyperKeyConflictPolicy.severity(ofBundleID: "com.knollsoft.Hyperkey") == .blocking
                && HyperKeyConflictPolicy.severity(ofBundleID: "com.knollsoft.Superkey") == .blocking)
        check(
            "BetterTouchTool is only a warning",
            HyperKeyConflictPolicy.severity(ofBundleID: "com.hegenberg.BetterTouchTool") == .warning)
        check(
            "an unknown app is no conflict",
            HyperKeyConflictPolicy.severity(ofBundleID: "com.apple.Safari") == nil)
        check(
            "Karabiner's virtual keyboard is recognised by name",
            HyperKeyConflictPolicy.isKarabinerVirtualKeyboard(
                named: "Karabiner DriverKit VirtualHIDKeyboard 1.8.0")
                && !HyperKeyConflictPolicy.isKarabinerVirtualKeyboard(named: "Apple Internal Keyboard"))
        check(
            "1Password is a likely Secure Input holder",
            HyperKeyConflictPolicy.secureInputSuspects.contains("com.1password.1password"))
    }

    static func modifierKeysPreferences() {
        let prefix = HyperKeyConflictPolicy.modifierMappingPrefix
        let preferences: [String: Any] = [
            prefix + "1452-834-0": [toRightControl.dictionary],
            prefix + "1133-49948-0": [
                HIDKeyMapping(source: HIDKeyMapping.capsLock, destination: HIDKeyMapping.capsLock).dictionary
            ],
            prefix + "0-0-0": [toF18.dictionary],
            prefix + "1234-5-0": [otherTool.dictionary],
            "AppleKeyboardUIMode": 2
        ]
        let remaps = HyperKeyConflictPolicy.capsLockRemaps(in: preferences)
        check(
            "keyboards whose Caps Lock is moved are reported, sorted",
            remaps == [.init(vendorID: 0, productID: 0), .init(vendorID: 1452, productID: 834)])
        check("the 0-0-0 entry reads as the default keyboard", remaps.first?.isDefault == true)
        check(
            "no preferences means no Caps Lock conflicts",
            HyperKeyConflictPolicy.capsLockRemaps(in: [:]).isEmpty)
    }

    static func remapperLifecycle() {
        let recoveryKey = "hyperKeyKeyboardMappings"
        func fixture(_ body: (KeyboardRemapper, UserDefaults) -> Void) {
            HIDEventSystem.reset()
            let domain = "tinycast.hyper-key-test.\(UUID())"
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain) }
            body(KeyboardRemapper(defaults: defaults), defaults)
        }
        fixture { remapper, defaults in
            HIDEventSystem.mappings[1] = [otherTool]
            check("enable succeeds", remapper.apply(toF18))
            check("enable preserves unrelated mappings", HIDEventSystem.mappings[1] == [otherTool, toF18])
            check("enable journals recovery", defaults.data(forKey: recoveryKey) != nil)
            let writes = HIDEventSystem.writeCount
            check(
                "idempotent apply avoids writes", remapper.apply(toF18) && HIDEventSystem.writeCount == writes
            )
            HIDEventSystem.connect(2)
            check("hot plug remaps new keyboards", HIDEventSystem.mappings[2] == [toF18])
            HIDEventSystem.mappings[2] = []
            check(
                "repair restores a lost mapping", remapper.repair() && HIDEventSystem.mappings[2] == [toF18])
            check("repair avoids writes when correct", !remapper.repair())
            check("route switching succeeds", remapper.apply(toRightControl))
            check(
                "route switching reaches both keyboards",
                HIDEventSystem.mappings.values.allSatisfy {
                    $0.contains(toRightControl) && !$0.contains(toF18)
                })
            check("cleanup succeeds", remapper.apply(nil))
            check(
                "cleanup preserves unrelated mappings",
                HIDEventSystem.mappings[1] == [otherTool] && HIDEventSystem.mappings[2] == [])
            check("completed cleanup removes recovery", defaults.data(forKey: recoveryKey) == nil)
        }
        fixture { remapper, _ in
            HIDEventSystem.rejectedKeyboards = [1]
            check("rejected writes report failure", !remapper.apply(toF18))
            HIDEventSystem.rejectedKeyboards = []
            check("the same route retries after failure", remapper.apply(toF18))
        }
        fixture { remapper, defaults in
            HIDEventSystem.connect(2)
            HIDEventSystem.rejectedKeyboards = [2]
            check("a keyboard that rejects the remap is skipped", remapper.apply(toF18))
            check(
                "only accepted writes change keyboards",
                HIDEventSystem.mappings[1] == [toF18] && HIDEventSystem.mappings[2] == nil)
            check(
                "partial success can be cleaned up", remapper.apply(nil) && HIDEventSystem.mappings[1] == [])
            check("partial cleanup removes recovery", defaults.data(forKey: recoveryKey) == nil)
        }
        fixture { remapper, defaults in
            remapper.apply(toF18)
            HIDEventSystem.rejectedKeyboards = [1]
            check("rejected cleanup reports failure", !remapper.apply(nil))
            check("rejected cleanup keeps recovery", defaults.data(forKey: recoveryKey) != nil)
            HIDEventSystem.rejectedKeyboards = []
            KeyboardRemapper(defaults: defaults).clearLeftovers()
            check("relaunch retries rejected cleanup", HIDEventSystem.mappings[1] == [])
            check("relaunch clears successful recovery", defaults.data(forKey: recoveryKey) == nil)
        }
        fixture { remapper, defaults in
            let original = HIDKeyMapping(source: HIDKeyMapping.capsLock, destination: 0x7_0000_0029)
            HIDEventSystem.mappings[1] = [original, otherTool]
            remapper.apply(toF18)
            remapper.apply(toRightControl)
            check(
                "disable restores displaced Caps Lock mapping",
                remapper.apply(nil) && Set(HIDEventSystem.mappings[1] ?? []) == [original, otherTool])
            remapper.apply(toF18)
            KeyboardRemapper(defaults: defaults).clearLeftovers()
            check(
                "crash recovery restores displaced mapping",
                Set(HIDEventSystem.mappings[1] ?? []) == [original, otherTool])
        }
        fixture { remapper, _ in
            HIDEventSystem.mappings[1] = [toF18, otherTool]
            remapper.apply(toF18)
            remapper.apply(nil)
            check(
                "an identical pre-existing mapping is never owned",
                HIDEventSystem.mappings[1] == [toF18, otherTool])
            remapper.apply(toRightControl)
            remapper.apply(nil)
            check(
                "another tool's Hyper mapping is restored",
                Set(HIDEventSystem.mappings[1] ?? []) == [toF18, otherTool])
        }
        fixture { remapper, _ in
            remapper.apply(toF18)
            let replacement = HIDKeyMapping(source: HIDKeyMapping.capsLock, destination: 0x7_0000_0029)
            HIDEventSystem.mappings[1] = [replacement, otherTool]
            remapper.apply(nil)
            check(
                "cleanup preserves another tool's later replacement",
                HIDEventSystem.mappings[1] == [replacement, otherTool])
        }
        fixture { remapper, defaults in
            remapper.apply(toF18)
            var journal: Data?
            HIDEventSystem.beforeWrite = { journal = defaults.data(forKey: recoveryKey) }
            remapper.apply(toRightControl)
            HIDEventSystem.beforeWrite = nil
            for installed in [toF18, toRightControl] {
                defaults.set(journal, forKey: recoveryKey)
                HIDEventSystem.mappings[1] = [installed, otherTool]
                KeyboardRemapper(defaults: defaults).clearLeftovers()
                check(
                    "route-change crash recovers \(installed.destination)",
                    HIDEventSystem.mappings[1] == [otherTool])
            }
        }
        fixture { remapper, defaults in
            remapper.apply(toF18)
            HIDEventSystem.devices = []
            check(
                "disconnected keyboard keeps recovery pending",
                !remapper.apply(nil) && defaults.data(forKey: recoveryKey) != nil)
            HIDEventSystem.connect(1)
            check(
                "reconnection completes deferred cleanup",
                HIDEventSystem.mappings[1] == [] && defaults.data(forKey: recoveryKey) == nil)
        }
        fixture { remapper, defaults in
            remapper.apply(toF18)
            guard let data = defaults.data(forKey: recoveryKey),
                var recovery = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else {
                check("recovery journal decodes", false)
                return
            }
            recovery["bootSessionID"] = "previous-boot"
            guard let previousBoot = try? JSONSerialization.data(withJSONObject: recovery) else {
                check("previous-boot journal encodes", false)
                return
            }
            defaults.set(previousBoot, forKey: recoveryKey)
            KeyboardRemapper(defaults: defaults).clearLeftovers()
            check(
                "recovery from another boot cannot claim a reused registry ID",
                HIDEventSystem.mappings[1] == [toF18])
        }
        fixture { remapper, _ in
            HIDEventSystem.available = false
            check("missing HID SPI reports failure", !remapper.apply(toF18))
        }
        fixture { remapper, defaults in
            let dictationKey = "dictationKeyKeyboardMappings"
            let dictation = KeyboardRemapper(defaults: defaults, recoveryKey: dictationKey)
            HIDEventSystem.mappings[1] = [otherTool]
            remapper.apply(toF18)
            dictation.apply(toF20)
            check(
                "Caps Lock and 🎤 remaps share a keyboard",
                HIDEventSystem.mappings[1] == [otherTool, toF18, toF20])
            check(
                "each remapper keeps its own recovery journal",
                defaults.data(forKey: recoveryKey) != nil && defaults.data(forKey: dictationKey) != nil)
            dictation.apply(nil)
            check("removing 🎤 keeps Caps Lock", HIDEventSystem.mappings[1] == [otherTool, toF18])
            dictation.apply(toF20)
            remapper.apply(nil)
            check("removing Caps Lock keeps 🎤", HIDEventSystem.mappings[1] == [otherTool, toF20])
        }
        fixture { remapper, _ in
            HIDEventSystem.devices = []
            check("no keyboard yet still succeeds", remapper.apply(toF18))
            HIDEventSystem.connect(1)
            check("the first keyboard to connect gets the remap", HIDEventSystem.mappings[1] == [toF18])
        }
        fixture { remapper, _ in
            remapper.apply(toF18)
            HIDEventSystem.rejectedKeyboards = [2]
            HIDEventSystem.connect(2)
            check(
                "a rejected hot-plug write leaves the other keyboards remapped",
                remapper.mapping == toF18 && HIDEventSystem.mappings[1] == [toF18]
                    && HIDEventSystem.mappings[2] == nil)
        }
    }

    static func karabinerConfig() {
        func config(_ profiles: [[String: Any]]) -> Data {
            (try? JSONSerialization.data(withJSONObject: ["profiles": profiles])) ?? Data()
        }
        let simple: [String: Any] = [
            "selected": true,
            "simple_modifications": [["from": ["key_code": "caps_lock"], "to": [["key_code": "escape"]]]]
        ]
        let complex: [String: Any] = [
            "selected": true,
            "complex_modifications": [
                "rules": [["manipulators": [["from": ["key_code": "right_command"], "type": "basic"]]]]
            ]
        ]
        let perDevice: [String: Any] = [
            "selected": true,
            "devices": [["simple_modifications": [["from": ["key_code": "left_option"]]]]]
        ]
        let unselected: [String: Any] = [
            "selected": false,
            "simple_modifications": [["from": ["key_code": "caps_lock"]]]
        ]
        check(
            "a simple modification of the key is a conflict",
            HyperKeyConflictPolicy.karabinerRemaps("capsLock", config: config([simple])))
        check(
            "a complex modification of the key is a conflict",
            HyperKeyConflictPolicy.karabinerRemaps("rightCommand", config: config([complex])))
        check(
            "a per-device modification of the key is a conflict",
            HyperKeyConflictPolicy.karabinerRemaps("leftOption", config: config([perDevice])))
        check(
            "a profile that is not selected does not count",
            !HyperKeyConflictPolicy.karabinerRemaps("capsLock", config: config([unselected, complex])))
        check(
            "a modification of another key is not a conflict",
            !HyperKeyConflictPolicy.karabinerRemaps("rightShift", config: config([simple])))
        check(
            "an unreadable config is not a conflict",
            !HyperKeyConflictPolicy.karabinerRemaps("capsLock", config: Data("{".utf8)))
    }
}
