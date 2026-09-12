enum CalcNumberBase: Int, Sendable {
    case binary = 2
    case octal = 8
    case decimal = 10
    case hexadecimal = 16

    init?(name: String) {
        switch name {
        case "bin", "binary": self = .binary
        case "oct", "octal": self = .octal
        case "dec", "decimal": self = .decimal
        case "hex", "hexadecimal": self = .hexadecimal
        default: return nil
        }
    }

    var name: String {
        switch self {
        case .binary: "Binary"
        case .octal: "Octal"
        case .decimal: "Decimal"
        case .hexadecimal: "Hexadecimal"
        }
    }

    var prefix: String {
        switch self {
        case .binary: "0b"
        case .octal: "0o"
        case .decimal: ""
        case .hexadecimal: "0x"
        }
    }
}
