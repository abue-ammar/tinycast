import Foundation

enum CalcMath {
    static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { sqrt($0) }, "log": { log10($0) }, "ln": { log($0) }, "sin": { sin($0) },
        "cos": { cos($0) }, "tan": { tan($0) }, "abs": { abs($0) }, "floor": { floor($0) },
        "ceil": { ceil($0) }, "round": { $0.rounded() },
        "cot": { 1 / tan($0) }, "sec": { 1 / cos($0) }, "csc": { 1 / sin($0) },
        "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
        "arcsin": { asin($0) }, "arccos": { acos($0) }, "arctan": { atan($0) },
        "sinh": { sinh($0) }, "cosh": { cosh($0) }, "tanh": { tanh($0) },
        "asinh": { asinh($0) }, "acosh": { acosh($0) }, "atanh": { atanh($0) },
        "cbrt": { cbrt($0) }, "exp": { exp($0) }, "log2": { log2($0) },
        "sign": { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) }, "trunc": { $0.rounded(.towardZero) }
    ]

    static let constants: [String: Double] = [
        "pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi, "τ": 2 * .pi, "phi": (1 + sqrt(5.0)) / 2
    ]

    /// Factorial for non-negative integers; 170! is the last value representable as a Double.
    static func factorial(_ value: Double) -> Double? {
        guard value >= 0, value.rounded() == value, value <= 170 else { return nil }
        var result = 1.0
        var next = 2.0
        while next <= value {
            result *= next
            next += 1
        }
        return result
    }

    static let multipleArguments: Set<String> = [
        "hypot", "round", "log", "gcd", "lcm", "atan2", "pow", "root", "fmod",
        "min", "max", "sum", "avg", "mean", "average"
    ]
    static let measurements: Set<String> = [
        "hypot", "round", "min", "max", "sum", "avg", "mean", "average"
    ]

    static func isFunction(_ name: String) -> Bool {
        CalcMath.functions[name] != nil || multipleArguments.contains(name)
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
            if values.count == 1, let function = CalcMath.functions[name] {
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

    private static func exactInteger(_ value: Double) -> Int64? {
        guard abs(value) < 9_007_199_254_740_992 else { return nil }
        return Int64(exactly: value)
    }

    static func bitwise(_ op: CalcOperator, _ left: Double, _ right: Double = 0) -> Double? {
        guard let lhs = exactInteger(left), let rhs = exactInteger(right) else { return nil }
        let result: Int64
        switch op {
        case .bitAnd: result = lhs & rhs
        case .bitOr: result = lhs | rhs
        case .bitXor: result = lhs ^ rhs
        case .bitNot: result = ~lhs
        case .shiftLeft:
            guard (0..<64).contains(rhs) else { return nil }
            result = lhs << rhs
            guard result >> rhs == lhs else { return nil }
        case .shiftRight:
            guard (0..<64).contains(rhs) else { return nil }
            result = lhs >> rhs
        default: return nil
        }
        return abs(Double(result)) < 9_007_199_254_740_992 ? Double(result) : nil
    }
}
