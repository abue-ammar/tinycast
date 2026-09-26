// Event handling follows MediaKeyTap, © Nicholas Hurden and contributors; MIT in NOTICE.md.
import AppKit
import Synchronization

final class MonitorMediaKeyListener: Sendable {
    let routing = Mutex(MonitorKeyRouting())
    private let commands: AsyncStream<MonitorKeyRouting.Command>.Continuation
    let events: AsyncStream<MonitorKeyRouting.Command>
    @MainActor private var port: CFMachPort?
    @MainActor private var source: CFRunLoopSource?

    init() {
        (events, commands) = AsyncStream.makeStream()
    }

    @MainActor
    func install() -> Bool {
        if let port {
            if !CGEvent.tapIsEnabled(tap: port) { CGEvent.tapEnable(tap: port, enable: true) }
            return true
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: (1 << 14) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<MonitorMediaKeyListener>.fromOpaque(context).takeUnretainedValue()
                return listener.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return false }
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    @MainActor
    func stop() {
        routing.withLock { $0.enabled = false; $0.held.removeAll() }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        source = nil
        port = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard type.rawValue == 14 || type == .keyDown || type == .keyUp else { return false }
        let native = type.rawValue == 14 ? NSEvent(cgEvent: event) : nil
        guard let key = MonitorMediaKey.decode(
            type: type.rawValue, subtype: Int(native?.subtype.rawValue ?? 0), data: native?.data1 ?? 0,
            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
            repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, flags: event.flags.rawValue)
        else { return false }
        let point = CGEvent(source: nil)?.location ?? event.location
        let result = routing.withLock { $0.handle(key, point: point) }
        if let command = result.command { commands.yield(command) }
        return result.consume
    }
}
