enum CalcOperator: Character, Sendable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case power = "^"
    case factorial = "!"
    case percent = "%"
    case open = "("
    case close = ")"
    case bitAnd = "&"
    case bitOr = "|"
    case bitNot = "~"
    case bitXor = "⊻"
    case shiftLeft = "«"
    case shiftRight = "»"
    case equal = "≡"
    case notEqual = "≠"
    case less = "<"
    case greater = ">"
    case lessEqual = "≤"
    case greaterEqual = "≥"

    var bindingPower: Int? {
        switch self {
        case .equal, .notEqual, .less, .greater, .lessEqual, .greaterEqual: return 2
        case .bitOr: return 5
        case .bitXor: return 6
        case .bitAnd: return 7
        case .shiftLeft, .shiftRight: return 8
        case .add, .subtract: return 10
        case .multiply, .divide: return 20
        case .power: return 30
        default: return nil
        }
    }

    var text: String {
        switch self {
        case .equal: return "=="
        case .shiftLeft: return "<<"
        case .shiftRight: return ">>"
        case .bitXor: return "xor"
        default: return String(rawValue)
        }
    }

}
