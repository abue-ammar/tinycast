import AppKit

@main
struct MonitorHardwareProbe {
    static func main() {
        let screens: [MonitorDDCTransport.Screen] = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                CGDisplayIsBuiltin(id) == 0 else { return nil }
            return .init(id: id, name: screen.localizedName, bounds: CGDisplayBounds(id))
        }
        let transport = MonitorDDCTransport(diagnostic: { print($0) })
        print("Transport available: \(transport.available); external displays: \(screens.count)")
        let displays = transport.discover(screens, valid: { true })
        for display in displays {
            print("\(display.name) [\(display.id)]")
            for control in MonitorControlKind.allCases {
                if let value = display.values[control] {
                    print("  \(control): \(value.current)/\(value.maximum)")
                } else {
                    print("  \(control): unavailable")
                }
            }
        }
        print("Matched audio output: \(MonitorAudioOutput.target(displays: displays).map(String.init) ?? "none")")
        if CommandLine.arguments.contains("--verify-writes") {
            for display in displays {
                for control in MonitorControlKind.allCases where display.values[control] != nil {
                    guard verify(transport, display: display.id, control: control) else { exit(1) }
                }
            }
        }
    }

    static func verify(_ transport: MonitorDDCTransport, display: UInt32, control: MonitorControlKind) -> Bool {
        guard let original = transport.read(display, control: control, valid: { true }) else { return false }
        let target: UInt16 = control == .mute ? (original.current == 1 ? 2 : 1)
            : (original.current > 0 ? original.current - 1 : min(1, original.maximum))
        let wrote = transport.write(display, control: control, value: target, valid: { true })
        let changed = transport.read(display, control: control, valid: { true })
        let restored = transport.write(display, control: control, value: original.current, valid: { true })
        let final = transport.read(display, control: control, valid: { true })
        let passed = wrote && changed?.current == target && restored && final?.current == original.current
        print("\(control): \(original.current) → \(changed?.current.description ?? "unreadable") "
            + "→ \(final?.current.description ?? "unreadable"); \(passed ? "verified and restored" : "FAILED")")
        return passed
    }
}
