import Foundation

@MainActor
final class HIDEventSystem {
    struct Keyboard {
        let registryID: UInt64
        let name: String
        let vendorID = 1
        let productID = 1
    }

    static var available = true
    static var rejectedKeyboards: Set<UInt64> = []
    static var devices = [Keyboard(registryID: 1, name: "Built-in")]
    static var mappings: [UInt64: [HIDKeyMapping]] = [:]
    static var writeCount = 0
    static var beforeWrite: (() -> Void)?
    static weak var current: HIDEventSystem?
    var onKeyboardConnected: ((Keyboard) -> Void)?

    init?() {
        guard Self.available else { return nil }
        Self.current = self
    }

    var keyboards: [Keyboard] { Self.devices }
    func watchConnections() {}
    func keyMappings(of keyboard: Keyboard) -> [HIDKeyMapping] { Self.mappings[keyboard.registryID] ?? [] }

    func setKeyMappings(_ mappings: [HIDKeyMapping], on keyboard: Keyboard) -> Bool {
        Self.beforeWrite?()
        Self.writeCount += 1
        guard !Self.rejectedKeyboards.contains(keyboard.registryID) else { return false }
        Self.mappings[keyboard.registryID] = mappings
        return true
    }

    static func reset() {
        available = true
        rejectedKeyboards = []
        devices = [Keyboard(registryID: 1, name: "Built-in")]
        mappings = [:]
        writeCount = 0
        beforeWrite = nil
    }

    static func connect(_ id: UInt64) {
        let keyboard = Keyboard(registryID: id, name: "External")
        devices.append(keyboard)
        current?.onKeyboardConnected?(keyboard)
    }
}
