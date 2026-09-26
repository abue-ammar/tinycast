// Adapted from MonitorControl, © MonitorControl contributors; MIT notice in NOTICE.md.
import Foundation

enum MonitorDDCPacket {
    static func request(_ control: MonitorControlKind, value: UInt16? = nil) -> [UInt8] {
        let payload: [UInt8]
        if let value {
            payload = [0x03, control.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)]
        } else {
            payload = [0x01, control.rawValue]
        }
        var packet = [UInt8(0x80 | payload.count)] + payload
        packet.append(packet.reduce(value == nil ? 0x6E : 0x6E ^ 0x51, ^))
        return packet
    }

    static func response(_ bytes: [UInt8], control: MonitorControlKind) -> MonitorControlValue? {
        guard bytes.count == 11 else { return nil }
        var bytes = bytes
        // LG HDR DQHD returns a zero length byte but checksums the standard 0x88 header.
        if bytes[1] == 0 { bytes[1] = 0x88 }
        guard bytes[0] == 0x6E, bytes[1] == 0x88,
            bytes[2] == 0x02, bytes[3] == 0, bytes[4] == control.rawValue,
            bytes.dropLast().reduce(UInt8(0x50), ^) == bytes.last
        else { return nil }
        let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        if control == .mute {
            guard current == 1 || current == 2 else { return nil }
        } else {
            guard maximum > 0, current <= maximum else { return nil }
        }
        return MonitorControlValue(current: current, maximum: maximum)
    }
}
