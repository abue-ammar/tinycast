import Foundation

enum CalcScience {
    /// `.some(nil)` when a phrase is named but does not solve, so the engine stops there.
    static func evaluate(_ query: String, solve: (String) -> CalcResult?) -> CalcResult?? {
        let found = anchors(in: query)
        guard !found.isEmpty else { return nil }
        if found.contains("molar") || found.contains("molecular"), let mass = molarMass(query) { return mass }
        return constant(query, among: found.flatMap { byAnchor[$0] ?? [] }, solve: solve)
    }

    private static let anchors: Set<String> = [
        "molar", "molecular", "light", "sound", "gravity", "gravitational", "planck", "boltzmann", "avogadro",
        "gas", "elementary", "electron", "proton", "neutron", "earth", "solar", "sun", "absolute"
    ]

    private static func anchors(in query: String) -> [String] {
        var found: [String] = []
        let bytes = query.utf8
        var start: String.Index?
        var index = bytes.startIndex
        while true {
            let folded = index < bytes.endIndex ? bytes[index] | 0x20 : 0
            if (97...122).contains(folded) {
                if start == nil { start = index }
            } else if let begin = start {
                if (3...13).contains(bytes.distance(from: begin, to: index)) {
                    let word = query[begin..<index].lowercased()
                    if anchors.contains(word) { found.append(word) }
                }
                start = nil
            }
            guard index < bytes.endIndex else { return found }
            bytes.formIndex(after: &index)
        }
    }

    private static let constants: [(phrase: String, literal: String)] = [
        ("speed of light", "299792458 m/s"), ("light speed", "299792458 m/s"),
        ("speed of sound", "343 m/s"), ("standard gravity", "9.80665 m/s2"), ("gravity", "9.80665 m/s2"),
        ("gravitational constant", "6.6743e-11 m³/(kg·s²)"), ("planck constant", "6.62607015e-34 J*s"),
        ("planck's constant", "6.62607015e-34 J*s"), ("boltzmann constant", "1.380649e-23 J/K"),
        ("avogadro constant", "6.02214076e23 /mol"), ("avogadro number", "6.02214076e23"),
        ("avogadro's number", "6.02214076e23"), ("gas constant", "8.314462618 J/(mol·K)"),
        ("elementary charge", "1.602176634e-19 coulomb"), ("electron mass", "9.1093837015e-31 kg"),
        ("proton mass", "1.67262192369e-27 kg"), ("neutron mass", "1.67492749804e-27 kg"),
        ("earth mass", "5.9722e24 kg"), ("mass of earth", "5.9722e24 kg"), ("earth radius", "6371 km"),
        ("radius of earth", "6371 km"), ("solar mass", "1.98847e30 kg"), ("mass of the sun", "1.98847e30 kg"),
        ("absolute zero", "-273.15 °C")
    ]

    private static let byAnchor: [String: [(phrase: String, literal: String)]] = {
        var table: [String: [(phrase: String, literal: String)]] = [:]
        for constant in constants {
            for word in constant.phrase.split(whereSeparator: { !$0.isLetter })
            where anchors.contains(String(word)) {
                table[String(word), default: []].append(constant)
            }
        }
        return table
    }()

    private static func constant(
        _ query: String, among candidates: [(phrase: String, literal: String)], solve: (String) -> CalcResult?
    ) -> CalcResult?? {
        for (phrase, literal) in candidates {
            guard let range = query.range(of: phrase, options: .caseInsensitive), isWord(range, in: query)
            else { continue }
            var rest = query
            rest.removeSubrange(range)
            let name = phrase.capitalized
            if rest.allSatisfy({ $0 == " " })
                || rest.trimmingCharacters(in: .whitespaces).lowercased() == "the"
            {
                let value = literal.prefix { $0 != " " }
                let unit = literal.dropFirst(value.count)
                guard let number = Double(value) else { return .some(nil) }
                let text = CalcFormatter.grouped(CalcFormatter.copyText(number)) + unit
                return CalcResult(
                    expression: query, sourceBadge: name, targetBadge: String(localized: "Value"),
                    payload: .value(display: text, copyText: CalcFormatter.copyText(number) + unit))
            }
            guard let solved = solve(query.replacingCharacters(in: range, with: literal)),
                solved.isActionable
            else { return .some(nil) }
            return CalcResult(
                expression: query, sourceBadge: name, targetBadge: solved.targetBadge,
                payload: solved.payload, canChain: solved.canChain)
        }
        return nil
    }

    private static func isWord(_ range: Range<String.Index>, in text: String) -> Bool {
        (range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter)
            && (range.upperBound == text.endIndex || !text[range.upperBound].isLetter)
    }

    private static let leads = ["molar mass of ", "molar mass ", "molecular weight of ", "molecular mass of "]

    private static func molarMass(_ query: String) -> CalcResult?? {
        let lowered = query.lowercased()
        let formula: Substring
        if let lead = leads.first(where: lowered.hasPrefix) {
            formula = query.dropFirst(lead.count)
        } else if lowered.hasSuffix(" molar mass") {
            formula = query.dropLast(" molar mass".count)
        } else {
            return nil
        }
        let trimmed = formula.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 64, !trimmed.hasPrefix("of"), let grams = mass(of: trimmed)
        else {
            return .some(nil)
        }
        return CalcResult(
            expression: query, sourceBadge: trimmed, targetBadge: String(localized: "Molar Mass"),
            payload: .number((grams * 1000).rounded() / 1000, suffix: " g/mol"), canChain: false)
    }

    private static let weights: [String: Double] = {
        let table = """
            H 1.008 He 4.0026 Li 6.94 Be 9.0122 B 10.81 C 12.011 N 14.007 O 15.999 F 18.998 Ne 20.18 \
            Na 22.99 Mg 24.305 Al 26.982 Si 28.085 P 30.974 S 32.06 Cl 35.45 Ar 39.95 K 39.098 Ca 40.078 \
            Sc 44.956 Ti 47.867 V 50.942 Cr 51.996 Mn 54.938 Fe 55.845 Co 58.933 Ni 58.693 Cu 63.546 \
            Zn 65.38 Ga 69.723 Ge 72.63 As 74.922 Se 78.971 Br 79.904 Kr 83.798 Rb 85.468 Sr 87.62 \
            Y 88.906 Zr 91.224 Nb 92.906 Mo 95.95 Tc 98 Ru 101.07 Rh 102.91 Pd 106.42 Ag 107.87 \
            Cd 112.41 In 114.82 Sn 118.71 Sb 121.76 Te 127.6 I 126.9 Xe 131.29 Cs 132.91 Ba 137.33 \
            La 138.91 Ce 140.12 Pr 140.91 Nd 144.24 Pm 145 Sm 150.36 Eu 151.96 Gd 157.25 Tb 158.93 \
            Dy 162.5 Ho 164.93 Er 167.26 Tm 168.93 Yb 173.05 Lu 174.97 Hf 178.49 Ta 180.95 W 183.84 \
            Re 186.21 Os 190.23 Ir 192.22 Pt 195.08 Au 196.97 Hg 200.59 Tl 204.38 Pb 207.2 Bi 208.98 \
            Po 209 At 210 Rn 222 Fr 223 Ra 226 Ac 227 Th 232.04 Pa 231.04 U 238.03 Np 237 Pu 244 \
            Am 243 Cm 247 Bk 247 Cf 251 Es 252 Fm 257 Md 258 No 259 Lr 266
            """
        let fields = table.split(separator: " ")
        return Dictionary(
            uniqueKeysWithValues: stride(from: 0, to: fields.count - 1, by: 2).map {
                (String(fields[$0]), Double(fields[$0 + 1]) ?? 0)
            })
    }()

    private static func mass(of formula: String) -> Double? {
        let isCased = formula.contains(where: \.isUppercase)
        // Lowercase needs a digit, or a word such as `water` would read as W·At·Er.
        guard isCased || formula.contains(where: \.isNumber),
            let written = isCased ? formula : capitalized(formula)
        else { return nil }
        var total = 0.0
        for part in written.split(whereSeparator: { "·*•.".contains($0) }) {
            let digits = part.prefix(while: \.isNumber)
            var chars = Array(part.dropFirst(digits.count))
            chars.append("\0")
            var index = 0
            guard let mass = group(chars, &index, depth: 0), chars[index] == "\0" else { return nil }
            total += mass * (digits.isEmpty ? 1 : Double(digits) ?? 1)
        }
        return total > 0 ? total : nil
    }

    private static func group(_ chars: [Character], _ index: inout Int, depth: Int) -> Double? {
        guard depth < 8 else { return nil }
        var total = 0.0
        while true {
            let char = chars[index]
            let part: Double
            if char == "(" || char == "[" {
                index += 1
                guard let inner = group(chars, &index, depth: depth + 1),
                    chars[index] == ")" || chars[index] == "]"
                else { return nil }
                index += 1
                part = inner
            } else if char.isUppercase {
                var symbol = String(char)
                index += 1
                if chars[index].isLowercase {
                    symbol.append(chars[index])
                    index += 1
                }
                guard let weight = weights[symbol] else { return nil }
                part = weight
            } else {
                return total > 0 ? total : nil
            }
            var count = 0
            while let digit = chars[index].wholeNumberValue, chars[index].isASCII {
                guard count < 100_000 else { return nil }
                count = count * 10 + digit
                index += 1
            }
            total += part * Double(max(count, 1))
        }
    }

    /// Lowercase has no case to split on, so `co2` (CO₂ or Co₂) stays silent rather than guessing.
    private static func capitalized(_ formula: String) -> String? {
        var output = ""
        var run = ""
        for char in formula + " " {
            if char.isLetter {
                run.append(char)
                continue
            }
            if !run.isEmpty {
                guard let symbols = symbols(Substring(run)) else { return nil }
                output += symbols
                run = ""
            }
            output.append(char)
        }
        return String(output.dropLast())
    }

    private static func symbols(_ run: Substring) -> String? {
        let letters = Array(run)
        var tails: [String?] = Array(repeating: nil, count: letters.count + 1)
        var readings = Array(repeating: 0, count: letters.count + 1)
        tails[letters.count] = ""
        readings[letters.count] = 1
        for start in stride(from: letters.count - 1, through: 0, by: -1) {
            for length in 1...min(2, letters.count - start) {
                let symbol = String(letters[start..<start + length]).capitalized
                guard weights[symbol] != nil, let rest = tails[start + length] else { continue }
                tails[start] = symbol + rest
                readings[start] = min(readings[start] + readings[start + length], 2)
            }
        }
        return readings[0] == 1 ? tails[0] : nil
    }
}
