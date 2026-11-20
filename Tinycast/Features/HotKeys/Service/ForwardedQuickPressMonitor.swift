import CoreAudio
import Foundation
import IOKit.hid

@MainActor
final class ForwardedQuickPressMonitor {
    private let manager: IOHIDManager
    private var press: PhysicalHyperKeyPress
    private let onSoloRelease: (UInt64, TimeInterval) -> Void

    var mapping: HIDKeyMapping { press.mapping }

    init?(mapping: HIDKeyMapping, onSoloRelease: @escaping (UInt64, TimeInterval) -> Void) {
        let manager = IOHIDManagerCreate(nil, 0)
        let devices = [kHIDUsage_GD_Keyboard, kHIDUsage_GD_Keypad].map {
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, devices as CFArray)
        let fn = PhysicalHyperKeyPress.fnUsages.map {
            [
                kIOHIDElementUsagePageKey: Int($0 >> 32),
                kIOHIDElementUsageKey: Int(UInt32(truncatingIfNeeded: $0))
            ]
        }
        IOHIDManagerSetInputValueMatchingMultiple(
            manager, ([[kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad]] + fn) as CFArray)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else { return nil }
        self.manager = manager
        press = PhysicalHyperKeyPress(mapping: mapping)
        self.onSoloRelease = onSoloRelease
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, status, _, value in
                guard let context, status == kIOReturnSuccess else { return }
                Unmanaged<ForwardedQuickPressMonitor>.fromOpaque(context).takeUnretainedValue().receive(value)
            }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                let monitor = Unmanaged<ForwardedQuickPressMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.press.remove(device: IOHIDDeviceGetService(device))
            }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    isolated deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, 0)
    }

    func cancelHold() {
        press = PhysicalHyperKeyPress(mapping: mapping)
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let key = IOHIDElementGetUsage(element)
        let page = IOHIDElementGetUsagePage(element)
        if page == kHIDPage_KeyboardOrKeypad
            && !(kHIDUsage_KeyboardA...kHIDUsage_KeyboardRightGUI).contains(Int(key))
        {
            return
        }
        let usage = UInt64(page) << 32 | UInt64(key)
        // Quartz preserves the hardware release stamp; convert only the duration clock.
        let stamp = IOHIDValueGetTimeStamp(value)
        let time = TimeInterval(AudioConvertHostTimeToNanos(stamp)) / 1_000_000_000
        if let duration = press.handle(
            device: IOHIDDeviceGetService(IOHIDElementGetDevice(element)), usage: usage,
            down: IOHIDValueGetIntegerValue(value) != 0, at: time)
        {
            onSoloRelease(stamp, duration)
        }
    }
}
