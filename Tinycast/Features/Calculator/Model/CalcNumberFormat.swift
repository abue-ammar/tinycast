import Foundation

/// Whether the calculator follows the Mac's number format or always reads and writes English.
enum CalcNumberStyle: String, CaseIterable, Identifiable, Sendable {
    case system
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .english: "English"
        }
    }
}

/// Separators the user writes; the engine only reads English. See docs/features/calculator.md.
struct CalcNumberFormat: Equatable, Sendable {
    let decimalSeparator: Unicode.Scalar
    /// nil when numbers are written without grouping.
    let groupingSeparator: Unicode.Scalar?

    static let english = CalcNumberFormat(decimal: ".", grouping: ",")

    /// Separators macOS offers that can never be mistaken for calculator syntax.
    private static let groupingScalars: Set<Unicode.Scalar> = [
        ".", ",", "'", "\u{2019}", "\u{00A0}", "\u{202F}", "\u{2009}"
    ]

    private init(decimal: Unicode.Scalar, grouping: Unicode.Scalar?) {
        decimalSeparator = decimal
        groupingSeparator = grouping
    }

    /// nil for a decimal separator canonical syntax can't express, such as the Arabic `٫`.
    init?(decimalSeparator: String, groupingSeparator: String?) {
        guard let decimal = Self.single(decimalSeparator), decimal == "." || decimal == "," else {
            return nil
        }
        let grouping = groupingSeparator.flatMap(Self.single).flatMap {
            $0 != decimal && Self.groupingScalars.contains($0) ? $0 : nil
        }
        self.init(decimal: decimal, grouping: grouping)
    }

    private static func single(_ text: String) -> Unicode.Scalar? {
        let scalars = text.unicodeScalars
        return scalars.count == 1 ? scalars.first : nil
    }

    /// A decimal comma can't also split arguments, so `;` does, as in spreadsheets.
    var argumentSeparator: Character { decimalSeparator == "," ? ";" : "," }

    private var usesDecimalComma: Bool { decimalSeparator == "," }

    // MARK: - Input

    /// The query in canonical syntax, or nil when a number in it has no single reading.
    func canonical(_ query: String) -> String? {
        guard self != .english else { return query }
        let scalars = Array(query.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if usesDecimalComma, scalar == ";" {
                // Spaced, so the canonical comma can never be read as grouping between two digits.
                output.append(contentsOf: ", ".unicodeScalars)
                index += 1
                continue
            }
            guard startsNumber(scalars, at: index, decimal: decimalSeparator) else {
                output.append(scalar)
                index += 1
                continue
            }
            let end = numberEnd(
                scalars, from: index, decimal: decimalSeparator, grouping: groupingSeparator)
            let run = scalars[index..<end]
            if Self.isClockFragment(scalars, run: index..<end) {
                output.append(contentsOf: run)
            } else {
                guard let number = canonicalNumber(run) else { return nil }
                output.append(contentsOf: number)
            }
            index = end
        }
        return String(output)
    }

    private func canonicalNumber(_ run: ArraySlice<Unicode.Scalar>) -> [Unicode.Scalar]? {
        let parts = run.split(separator: decimalSeparator, omittingEmptySubsequences: false)
        // Where the dot is the decimal, `19.2.27` is a date exactly as English reads it.
        if parts.count > 2 {
            return !usesDecimalComma && !run.contains(where: isGrouping) ? Array(run) : nil
        }
        if parts.count == 2, parts[1].contains(where: isGrouping) { return nil }
        let groups = parts[0].split(
            omittingEmptySubsequences: false, whereSeparator: isGrouping)
        if groups.count > 1, !Self.isValidGrouping(groups) {
            // A dotted date's dots are grouping dots here, and no valid grouping has short groups.
            let isDottedDate = groupingSeparator == "." && parts.count == 1 && groups.count > 2
            return isDottedDate ? Array(run) : nil
        }
        var number = groups.flatMap { $0 }
        if parts.count == 2 {
            number.append(".")
            number.append(contentsOf: parts[1])
        }
        return number
    }

    private func isGrouping(_ scalar: Unicode.Scalar) -> Bool { scalar == groupingSeparator }

    // MARK: - Output

    /// An answer's numbers in this format; any other text, commas included, is left as written.
    func localized(_ text: String) -> String {
        rewrite(text, separatingArguments: false)
    }

    /// An echoed expression, whose canonical argument commas also take this format's separator.
    func localizedExpression(_ text: String) -> String {
        rewrite(text, separatingArguments: true)
    }

    func localized(_ result: CalcResult) -> CalcResult {
        guard self != .english else { return result }
        let payload: CalcResult.Payload
        switch result.payload {
        case .value(let display, let copyText):
            payload = .value(display: localized(display), copyText: localized(copyText))
        case .error:
            payload = result.payload
        }
        return CalcResult(
            expression: localizedExpression(result.expression), sourceBadge: result.sourceBadge,
            targetBadge: result.targetBadge, payload: payload, canChain: result.canChain)
    }

    private func rewrite(_ text: String, separatingArguments: Bool) -> String {
        guard self != .english else { return text }
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var depth = 0
        // Inside a call every comma separates arguments, exactly as `CalcTokenizer` reads it.
        var functionDepth: Int?
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard startsNumber(scalars, at: index, decimal: ".") else {
                if scalar == "(" {
                    if functionDepth == nil, Self.namesFunction(scalars, before: index) {
                        functionDepth = depth
                    }
                    depth += 1
                } else if scalar == ")" {
                    depth -= 1
                    if functionDepth == depth { functionDepth = nil }
                }
                if separatingArguments, usesDecimalComma, scalar == "," {
                    output.append(contentsOf: argumentSeparator.unicodeScalars)
                } else {
                    output.append(scalar)
                }
                index += 1
                continue
            }
            let end = numberEnd(
                scalars, from: index, decimal: ".", grouping: functionDepth == nil ? "," : nil)
            let run = scalars[index..<end]
            if !Self.isClockFragment(scalars, run: index..<end), let number = localizedNumber(run) {
                output.append(contentsOf: number)
            } else {
                output.append(contentsOf: run)
            }
            index = end
        }
        return String(output)
    }

    /// nil for a run that isn't one canonical number, so a dotted date stays as written.
    private func localizedNumber(_ run: ArraySlice<Unicode.Scalar>) -> [Unicode.Scalar]? {
        let parts = run.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.count == 1 || !parts[1].contains(",") else { return nil }
        let groups = parts[0].split(separator: ",", omittingEmptySubsequences: false)
        guard groups.count == 1 || Self.isValidGrouping(groups) else { return nil }
        var number: [Unicode.Scalar] = []
        for (index, group) in groups.enumerated() {
            if index > 0, let groupingSeparator { number.append(groupingSeparator) }
            number.append(contentsOf: group)
        }
        if parts.count == 2 {
            number.append(decimalSeparator)
            number.append(contentsOf: parts[1])
        }
        return number
    }

    // MARK: - Scanning

    /// A digit, or a decimal separator leading one (`,5`) that no digit precedes.
    private func startsNumber(
        _ scalars: [Unicode.Scalar], at index: Int, decimal: Unicode.Scalar
    ) -> Bool {
        let scalar = scalars[index]
        if Self.isDigit(scalar) { return true }
        guard scalar == decimal, index + 1 < scalars.count, Self.isDigit(scalars[index + 1]) else {
            return false
        }
        return index == 0 || !Self.isDigit(scalars[index - 1])
    }

    /// Digits and the separators between them; a trailing decimal stays, so `2,` still answers.
    private func numberEnd(
        _ scalars: [Unicode.Scalar], from start: Int, decimal: Unicode.Scalar,
        grouping: Unicode.Scalar?
    ) -> Int {
        var end = start
        while end < scalars.count {
            let scalar = scalars[end]
            if Self.isDigit(scalar) {
                end += 1
                continue
            }
            guard scalar == decimal || scalar == grouping else { break }
            let next = end + 1
            if next < scalars.count, Self.isDigit(scalars[next]) {
                end = next
            } else {
                if scalar == decimal, next == scalars.count, end > start { end = next }
                break
            }
        }
        return end
    }

    /// `00:18:00.123` belongs to a clock, whose fractional seconds are always written with a dot.
    private static func isClockFragment(_ scalars: [Unicode.Scalar], run: Range<Int>) -> Bool {
        (run.lowerBound > 0 && scalars[run.lowerBound - 1] == ":")
            || (run.upperBound < scalars.count && scalars[run.upperBound] == ":")
    }

    /// Whether the word before `index`, spaces allowed, is a function; `2max(` is `2 × max(`.
    private static func namesFunction(_ scalars: [Unicode.Scalar], before index: Int) -> Bool {
        var end = index
        while end > 0, scalars[end - 1].properties.isWhitespace { end -= 1 }
        var start = end
        while start > 0, scalars[start - 1].properties.isAlphabetic || isDigit(scalars[start - 1]) {
            start -= 1
        }
        while start < end, isDigit(scalars[start]) { start += 1 }
        guard start < end else { return false }
        return CalcMath.isFunction(String(String.UnicodeScalarView(scalars[start..<end])).lowercased())
    }

    private static func isValidGrouping(_ groups: [ArraySlice<Unicode.Scalar>]) -> Bool {
        guard let first = groups.first, (1...3).contains(first.count) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool { (48...57).contains(scalar.value) }
}
