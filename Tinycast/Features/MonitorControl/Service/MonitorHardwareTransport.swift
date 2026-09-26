import Foundation

protocol MonitorHardwareTransport {
    var available: Bool { get }
    func discover(_ screens: [MonitorDDCTransport.Screen], valid: () -> Bool) -> [MonitorKeyRouting.Display]
    func read(_ display: UInt32, control: MonitorControlKind, valid: () -> Bool) -> MonitorControlValue?
    func write(_ display: UInt32, control: MonitorControlKind, value: UInt16, valid: () -> Bool) -> Bool
}
