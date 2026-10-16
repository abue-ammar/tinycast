import Foundation
import IOKit.hid

/// The private HID SPI behind `hidutil`. See docs/features/hotkeys.md#per-keyboard-remapping.
@MainActor
final class HIDEventSystem {
    struct Keyboard {
        fileprivate let service: AnyObject
        let registryID: UInt64
        let name: String
        let vendorID: Int
        let productID: Int
    }

    var onKeyboardConnected: ((Keyboard) -> Void)?

    private let functions: Functions
    private let client: AnyObject
    private var isWatchingConnections = false

    /// Nil when this macOS lacks the SPI, so the caller reports it rather than crashing.
    init?() {
        guard let functions = Functions(), let client = functions.createSimpleClient(kCFAllocatorDefault)
        else { return nil }
        self.functions = functions
        self.client = Unmanaged<AnyObject>.fromOpaque(client).takeRetainedValue()
    }

    // Isolated so teardown can unschedule the main-queue delivery it registered.
    isolated deinit {
        guard isWatchingConnections else { return }
        functions.unscheduleFromDispatchQueue(opaque(client), opaque(DispatchQueue.main))
    }

    var keyboards: [Keyboard] {
        guard let services = functions.copyServices(opaque(client))?.takeRetainedValue() else {
            return []
        }
        return (0..<CFArrayGetCount(services)).compactMap { index in
            CFArrayGetValueAtIndex(services, index).flatMap {
                keyboard(UnsafeMutableRawPointer(mutating: $0))
            }
        }
    }

    func keyMappings(of keyboard: Keyboard) -> [HIDKeyMapping] {
        HIDKeyMapping.mappings(from: property(Property.userKeyMapping, of: keyboard.service))
    }

    @discardableResult
    func setKeyMappings(_ mappings: [HIDKeyMapping], on keyboard: Keyboard) -> Bool {
        let value = mappings.map(\.dictionary) as CFArray
        return functions.setProperty(
            opaque(keyboard.service), Property.userKeyMapping as CFString, value
        ).boolValue
    }

    func watchConnections() {
        guard !isWatchingConnections else { return }
        isWatchingConnections = true
        functions.registerDeviceMatching(
            opaque(client),
            { @MainActor target, _, service in
                guard let target, let service else { return }
                let system = Unmanaged<HIDEventSystem>.fromOpaque(target).takeUnretainedValue()
                system.serviceMatched(service)
            }, Unmanaged.passUnretained(self).toOpaque(), nil)
        functions.scheduleWithDispatchQueue(opaque(client), opaque(DispatchQueue.main))
    }

    fileprivate func serviceMatched(_ service: UnsafeMutableRawPointer) {
        guard let keyboard = keyboard(service) else { return }
        onKeyboardConnected?(keyboard)
    }

    private func keyboard(_ service: UnsafeMutableRawPointer) -> Keyboard? {
        guard
            functions.conformsTo(
                service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)
            ) != 0
        else { return nil }
        let object = Unmanaged<AnyObject>.fromOpaque(service).takeUnretainedValue()
        guard let registryID = functions.registryID(service)?.takeUnretainedValue() as? NSNumber else {
            return nil
        }
        return Keyboard(
            service: object,
            registryID: registryID.uint64Value,
            name: property(Property.product, of: object) as? String ?? String(localized: "Keyboard"),
            vendorID: (property(Property.vendorID, of: object) as? NSNumber)?.intValue ?? 0,
            productID: (property(Property.productID, of: object) as? NSNumber)?.intValue ?? 0)
    }

    private func property(_ key: String, of service: AnyObject) -> Any? {
        functions.copyProperty(opaque(service), key as CFString)?.takeRetainedValue()
    }

    private func opaque(_ object: AnyObject) -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(object).toOpaque()
    }

    private enum Property {
        static let product = "Product"
        static let vendorID = "VendorID"
        static let productID = "ProductID"
        static let userKeyMapping = "UserKeyMapping"
    }
}

private struct Functions {
    typealias ServiceCallback =
        @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?)
        -> Void
    typealias CreateSimpleClient = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    typealias CopyServices = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    typealias ConformsTo = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> boolean_t
    typealias CopyProperty =
        @convention(c) (UnsafeMutableRawPointer, CFString) -> Unmanaged<AnyObject>?
    typealias RegistryID = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<AnyObject>?
    typealias SetProperty =
        @convention(c) (UnsafeMutableRawPointer, CFString, AnyObject) -> DarwinBoolean
    typealias RegisterDeviceMatching =
        @convention(c) (
            UnsafeMutableRawPointer, ServiceCallback, UnsafeMutableRawPointer?,
            UnsafeMutableRawPointer?
        ) -> Void
    /// The queue travels as an opaque pointer: a `dispatch_queue_t` is one at the C boundary.
    typealias QueueScheduling = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void

    let createSimpleClient: CreateSimpleClient
    let copyServices: CopyServices
    let conformsTo: ConformsTo
    let copyProperty: CopyProperty
    let registryID: RegistryID
    let setProperty: SetProperty
    let registerDeviceMatching: RegisterDeviceMatching
    let scheduleWithDispatchQueue: QueueScheduling
    let unscheduleFromDispatchQueue: QueueScheduling

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        else { return nil }
        func symbol<Function>(_ name: String) -> Function? {
            dlsym(handle, name).map { unsafeBitCast($0, to: Function.self) }
        }
        guard
            let createSimpleClient: CreateSimpleClient = symbol(
                "IOHIDEventSystemClientCreateSimpleClient"),
            let copyServices: CopyServices = symbol("IOHIDEventSystemClientCopyServices"),
            let conformsTo: ConformsTo = symbol("IOHIDServiceClientConformsTo"),
            let copyProperty: CopyProperty = symbol("IOHIDServiceClientCopyProperty"),
            let registryID: RegistryID = symbol("IOHIDServiceClientGetRegistryID"),
            let setProperty: SetProperty = symbol("IOHIDServiceClientSetProperty"),
            let registerDeviceMatching: RegisterDeviceMatching = symbol(
                "IOHIDEventSystemClientRegisterDeviceMatchingCallback"),
            let scheduleWithDispatchQueue: QueueScheduling = symbol(
                "IOHIDEventSystemClientScheduleWithDispatchQueue"),
            let unscheduleFromDispatchQueue: QueueScheduling = symbol(
                "IOHIDEventSystemClientUnscheduleFromDispatchQueue")
        else { return nil }
        self.createSimpleClient = createSimpleClient
        self.copyServices = copyServices
        self.conformsTo = conformsTo
        self.copyProperty = copyProperty
        self.registryID = registryID
        self.setProperty = setProperty
        self.registerDeviceMatching = registerDeviceMatching
        self.scheduleWithDispatchQueue = scheduleWithDispatchQueue
        self.unscheduleFromDispatchQueue = unscheduleFromDispatchQueue
    }
}
