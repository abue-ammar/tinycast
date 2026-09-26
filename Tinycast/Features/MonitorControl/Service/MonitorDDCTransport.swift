// Adapted from MonitorControl, © MonitorControl contributors; MIT notice in NOTICE.md.
import CoreGraphics
import Foundation
import IOKit

final class MonitorDDCTransport: MonitorHardwareTransport {
    struct Screen: Sendable {
        let id: UInt32
        let name: String
        let bounds: CGRect
    }

    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias DisplayInfo = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?

    private let ioKit: UnsafeMutableRawPointer?
    private let coreDisplay: UnsafeMutableRawPointer?
    private var services: [UInt32: CFTypeRef] = [:]
    private let diagnostic: (String) -> Void

    init(diagnostic: @escaping (String) -> Void = { _ in }) {
        self.diagnostic = diagnostic
        ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
    }

    deinit {
        services.removeAll()
        if let ioKit { dlclose(ioKit) }
        if let coreDisplay { dlclose(coreDisplay) }
    }

    var available: Bool {
        #if arch(arm64)
        symbol("IOAVServiceCreateWithService", in: ioKit) != nil
            && symbol("IOAVServiceReadI2C", in: ioKit) != nil
            && symbol("IOAVServiceWriteI2C", in: ioKit) != nil
            && symbol("CoreDisplay_DisplayCreateInfoDictionary", in: coreDisplay) != nil
        #else
        false
        #endif
    }

    func discover(_ screens: [Screen], valid: () -> Bool) -> [MonitorKeyRouting.Display] {
        services.removeAll()
        guard available, valid(), !screens.isEmpty else { return [] }
        let candidates = registryServices()
        let identities = screens.map { identity(displayID: $0.id) }
        let matches = MonitorIdentity.matches(displays: identities, services: candidates.map(\.identity))
        diagnostic("DDC services: \(candidates.count); matched displays: \(matches.count)")
        for identity in identities {
            diagnostic("Display \(identity.name): location \(identity.location), "
                + "EDID \(identity.edidVendor)/\(identity.edidProduct)")
        }
        for candidate in candidates {
            diagnostic("Service \(candidate.identity.name): location \(candidate.identity.location), "
                + "EDID \(candidate.identity.edidVendor)/\(candidate.identity.edidProduct)")
        }
        var displays: [MonitorKeyRouting.Display] = []
        for (index, screen) in screens.enumerated() {
            guard valid() else { services.removeAll(); return [] }
            var values: [MonitorControlKind: MonitorControlValue] = [:]
            if let match = matches[index] {
                services[screen.id] = candidates[match].service
                for control in MonitorControlKind.allCases where valid() {
                    values[control] = read(screen.id, control: control, valid: valid)
                }
            }
            displays.append(.init(id: screen.id, name: screen.name, bounds: screen.bounds,
                                  values: values, hasHardwareService: matches[index] != nil))
        }
        return displays
    }

    func read(_ display: UInt32, control: MonitorControlKind, valid: () -> Bool) -> MonitorControlValue? {
        guard let service = services[display],
            let pointer = symbol("IOAVServiceReadI2C", in: ioKit) else { return nil }
        let transfer = unsafeBitCast(pointer, to: Transfer.self)
        for _ in 0..<5 where valid() {
            guard send(service, packet: MonitorDDCPacket.request(control), valid: valid) else { continue }
            Thread.sleep(forTimeInterval: 0.05)
            guard valid() else { return nil }
            var reply = [UInt8](repeating: 0, count: 11)
            let status = reply.withUnsafeMutableBytes {
                transfer(service, 0x37, 0, $0.baseAddress!, UInt32($0.count))
            }
            if status == 0, let value = MonitorDDCPacket.response(reply, control: control) { return value }
            diagnostic("DDC \(control) read status \(status), reply \(reply.map { String(format: "%02X", $0) }.joined())")
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    func write(_ display: UInt32, control: MonitorControlKind, value: UInt16, valid: () -> Bool) -> Bool {
        guard let service = services[display] else { return false }
        for _ in 0..<5 where valid() {
            if send(service, packet: MonitorDDCPacket.request(control, value: value), valid: valid) { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    private func send(_ service: CFTypeRef, packet: [UInt8], valid: () -> Bool) -> Bool {
        guard let pointer = symbol("IOAVServiceWriteI2C", in: ioKit) else { return false }
        let transfer = unsafeBitCast(pointer, to: Transfer.self)
        var packet = packet
        var success = false
        for _ in 0..<2 {
            Thread.sleep(forTimeInterval: 0.01)
            guard valid() else { return false }
            success = packet.withUnsafeMutableBytes {
                transfer(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) == 0
            }
        }
        return success
    }

    private func symbol(_ name: String, in handle: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let handle else { return nil }
        return dlsym(handle, name)
    }

    private func identity(displayID: UInt32) -> MonitorIdentity {
        guard let pointer = symbol("CoreDisplay_DisplayCreateInfoDictionary", in: coreDisplay),
            let info = unsafeBitCast(pointer, to: DisplayInfo.self)(displayID)?.takeRetainedValue() as? [String: Any]
        else { return MonitorIdentity() }
        guard info["kCGDisplayIsVirtualDevice"] as? Bool != true,
            info["kCGDisplayIsAirPlay"] as? Bool != true else { return MonitorIdentity() }
        let names = info["DisplayProductName"] as? [String: String] ?? [:]
        let vendor = (info["DisplayVendorID"] as? NSNumber)?.uint16Value ?? 0
        let product = (info["DisplayProductID"] as? NSNumber)?.uint16Value ?? 0
        return MonitorIdentity(
            location: info["IODisplayLocation"] as? String ?? "",
            name: names["en_US"] ?? names.values.first ?? "",
            serial: (info["DisplaySerialNumber"] as? NSNumber)?.int64Value ?? 0,
            edidVendor: vendor == 0 ? "" : String(format: "%04X", vendor),
            edidProduct: product == 0 ? "" : String(format: "%02X%02X", product & 255, product >> 8))
    }

    private func registryServices() -> [(identity: MonitorIdentity, service: CFTypeRef)] {
        guard let pointer = symbol("IOAVServiceCreateWithService", in: ioKit) else { return [] }
        let create = unsafeBitCast(pointer, to: Create.self)
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, kIOServicePlane,
                                           IOOptionBits(kIORegistryIterateRecursively), &iterator) == 0 else { return [] }
        defer { IOObjectRelease(iterator) }
        var identity = MonitorIdentity()
        var result: [(identity: MonitorIdentity, service: CFTypeRef)] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &name) == 0 else { continue }
            let entryName = string(name)
            if entryName == "AppleCLCD2" || entryName == "IOMobileFramebufferShim" {
                identity = registryIdentity(entry)
            } else if entryName == "DCPAVServiceProxy",
                property(entry, "Location") as? String == "External",
                let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                result.append((identity, service))
            }
        }
        return result
    }

    private func registryIdentity(_ entry: io_registry_entry_t) -> MonitorIdentity {
        let uuid = (property(entry, "EDID UUID") as? String ?? "").uppercased()
        let attributes = property(entry, "DisplayAttributes") as? [String: Any] ?? [:]
        let product = attributes["ProductAttributes"] as? [String: Any] ?? [:]
        var path = [CChar](repeating: 0, count: 512)
        let hasPath = IORegistryEntryGetPath(entry, kIOServicePlane, &path) == 0
        return MonitorIdentity(
            location: hasPath ? string(path) : "",
            name: product["ProductName"] as? String ?? "",
            serial: (product["SerialNumber"] as? NSNumber)?.int64Value ?? 0,
            edidVendor: uuid.count >= 8 ? String(uuid.prefix(4)) : "",
            edidProduct: uuid.count >= 8 ? String(uuid.dropFirst(4).prefix(4)) : "")
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private func string(_ bytes: [CChar]) -> String {
        String(bytes: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }
}
