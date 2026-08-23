import Foundation

/// Shared by Raycast readers whose binary fields are hex strings.
extension Data {
    /// Parses an even-length hex string; returns nil on any non-hex character.
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)

        func nibble(_ char: UInt8) -> UInt8? {
            switch char {
            case 0x30...0x39: return char - 0x30
            case 0x61...0x66: return char - 0x61 + 10
            case 0x41...0x46: return char - 0x41 + 10
            default: return nil
            }
        }

        var index = 0
        while index < chars.count {
            guard let high = nibble(chars[index]),
                let low = nibble(chars[index + 1])
            else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        self = Data(bytes)
    }

    /// Lowercase two-digit-per-byte hex.
    var hexEncoded: String { map { String(format: "%02x", $0) }.joined() }
}
