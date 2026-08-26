import Foundation

/// Fast on-device evaluator using Tinycast's native math, unit, currency, and date engines.
public final class CalculatorToolRunner: Sendable {
    public init() {}

    public func calculate(expression: String) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: Expression cannot be empty."
        }

        // Load cached currency rates if available
        var rates: CurrencyRates?
        let cacheURL = AppPaths.caches().appendingPathComponent("currency-rates.json")
        if let data = try? Data(contentsOf: cacheURL) {
            rates = try? JSONDecoder().decode(CurrencyRates.self, from: data)
        }

        if let result = CalcEngine.evaluate(trimmed, rates: rates) {
            switch result.payload {
            case .value(let display, let copyText):
                var response = "Result: \(display)"
                if display != copyText && !copyText.isEmpty {
                    response += " (Exact: \(copyText))"
                }
                if let src = result.sourceBadge, let tgt = result.targetBadge {
                    response += " [\(src) → \(tgt)]"
                }
                return response
            case .error(let message):
                return "Calculation Error: \(message)"
            }
        }

        return "Could not evaluate expression: '\(trimmed)'. Ensure it is a valid math expression, unit conversion, currency exchange, or date calculation."
    }
}
