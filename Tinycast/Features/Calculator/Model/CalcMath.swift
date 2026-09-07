import Foundation

enum CalcMath {
    static let multipleArguments: Set<String> = [
        "hypot", "round", "log", "gcd", "lcm", "atan2", "pow", "root", "fmod",
        "min", "max", "sum", "avg", "mean", "average"
    ]
    static let measurements: Set<String> = [
        "hypot", "round", "min", "max", "sum", "avg", "mean", "average"
    ]

    static func isFunction(_ name: String) -> Bool {
        CalcParser.functions[name] != nil || multipleArguments.contains(name)
    }

    static func evaluate(_ name: String, _ values: [Double]) -> Double? {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
        let first = values[0]
        let result: Double
        switch name {
        case "min": result = values.min() ?? first
        case "max": result = values.max() ?? first
        case "sum": result = values.reduce(0, +)
        case "avg", "mean", "average": result = values.reduce(0) { $0 + $1 / Double(values.count) }
        case "hypot": result = values.reduce(0) { hypot($0, $1) }
        case "gcd", "lcm":
            var accumulator: Int64 = name == "gcd" ? 0 : 1
            for value in values {
                guard let integer = exactInteger(value) else { return nil }
                let positive = abs(integer)
                var a = accumulator
                var b = positive
                while b != 0 { (a, b) = (b, a % b) }
                if name == "gcd" { accumulator = a } else if a == 0 {
                    accumulator = 0
                } else {
                    let product = (accumulator / a).multipliedReportingOverflow(by: positive)
                    guard !product.overflow else { return nil }
                    accumulator = product.partialValue
                }
            }
            return abs(Double(accumulator)) < 9_007_199_254_740_992 ? Double(accumulator) : nil
        default:
            if values.count == 1, let function = CalcParser.functions[name] {
                result = function(first)
            } else {
                guard values.count == 2 else { return nil }
                let second = values[1]
                switch name {
                case "round":
                    guard let digits = Int(exactly: second), (-308...308).contains(digits) else { return nil }
                    let factor = pow(10, second)
                    let scaled = first * factor
                    result = scaled.isFinite ? scaled.rounded() / factor : first
                case "log":
                    guard first > 0, second > 0, second != 1 else { return nil }
                    result = log(first) / log(second)
                case "atan2": result = atan2(first, second)
                case "pow": result = pow(first, second)
                case "root":
                    guard second != 0 else { return nil }
                    result = first < 0 && second.truncatingRemainder(dividingBy: 2) != 0 && second.rounded() == second
                        ? -pow(-first, 1 / second) : pow(first, 1 / second)
                case "fmod": result = first.truncatingRemainder(dividingBy: second)
                default: return nil
                }
            }
        }
        return result.isFinite ? result : nil
    }

    static func bindingPower(_ op: Character) -> Int? {
        switch op {
        case "≡", "≠", "<", ">", "≤", "≥": return 2
        case "|": return 5
        case "⊻": return 6
        case "&": return 7
        case "«", "»": return 8
        case "+", "-": return 10
        case "*", "/": return 20
        case "^": return 30
        default: return nil
        }
    }

    private static func exactInteger(_ value: Double) -> Int64? {
        guard abs(value) < 9_007_199_254_740_992 else { return nil }
        return Int64(exactly: value)
    }

    static func operatorText(_ op: Character) -> String {
        switch op {
        case "≡": return "=="
        case "«": return "<<"
        case "»": return ">>"
        case "⊻": return "xor"
        default: return String(op)
        }
    }

    static func bitwise(_ op: Character, _ left: Double, _ right: Double = 0) -> Double? {
        guard let lhs = exactInteger(left), let rhs = exactInteger(right) else { return nil }
        let result: Int64
        switch op {
        case "&": result = lhs & rhs
        case "|": result = lhs | rhs
        case "⊻": result = lhs ^ rhs
        case "~": result = ~lhs
        case "«":
            guard (0..<64).contains(rhs) else { return nil }
            result = lhs << rhs
            guard result >> rhs == lhs else { return nil }
        case "»":
            guard (0..<64).contains(rhs) else { return nil }
            result = lhs >> rhs
        default: return nil
        }
        return abs(Double(result)) < 9_007_199_254_740_992 ? Double(result) : nil
    }
}
