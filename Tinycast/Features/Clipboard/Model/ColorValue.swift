import Foundation

/// A parsed colour, stored as the sRGB components every format derives from.
struct ColorValue: Equatable, Sendable {
    /// Each 0…1, already clamped; alpha is 1 for a notation that carries none.
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// NaN survives `min`/`max` and `Int(NaN)` traps, so a non-finite channel becomes zero.
    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    /// Every notation states 8 bits, so alpha that rounds back to opaque is opaque.
    var hasAlpha: Bool { (alpha * 255).rounded() < 255 }
}

extension ColorValue {
    /// HSL in, sRGB stored: one set of components means every format derives from one source.
    init(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1) {
        let saturation = min(max(saturation, 0), 1)
        let lightness = min(max(lightness, 0), 1)
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base = lightness - chroma / 2
        let (red, green, blue): (Double, Double, Double) =
            switch sector {
            case ..<1: (chroma, second, 0)
            case ..<2: (second, chroma, 0)
            case ..<3: (0, chroma, second)
            case ..<4: (0, second, chroma)
            case ..<5: (second, 0, chroma)
            default: (chroma, 0, second)
            }
        self.init(red: red + base, green: green + base, blue: blue + base, alpha: alpha)
    }

    /// Hue, saturation and lightness, the inverse of the HSL initialiser.
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let chroma = maximum - minimum
        let lightness = (maximum + minimum) / 2
        // Rounding leaves a chroma of ~1e-16 at a lightness of 1, whose divisor below is 0.
        let span = 1 - abs(2 * lightness - 1)
        guard chroma > 0, span > 0 else { return (0, 0, lightness) }
        let hue: Double =
            switch maximum {
            case red: 60 * ((green - blue) / chroma).truncatingRemainder(dividingBy: 6)
            case green: 60 * ((blue - red) / chroma + 2)
            default: 60 * ((red - green) / chroma + 4)
            }
        return (
            hue < 0 ? hue + 360 : hue, min(chroma / span, 1), lightness
        )
    }

    /// A colour is one bare token, so anything past the longest `hsla()` form is not one.
    private static let detectionLimit = 64

    /// How much untrimmed text is worth trimming first; past this nothing can be a colour anyway.
    private static let scanLimit = 2048

    /// Parse a whole trimmed token, or nil when it is not a colour.
    static func parse(_ text: String) -> ColorValue? {
        // Every visible row runs this per render, so the shape is rejected before allocating.
        guard text.utf8.count <= scanLimit, couldBeColor(text.utf8) else { return nil }
        // Trimmed before the cap, as the classifier is; else a newline files an unreadable row.
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= detectionLimit else { return nil }
        if token.hasPrefix("#") { return parseHex(token.dropFirst()) }
        return parseFunctional(token)
    }

    /// Prose and links fail on the closing byte alone: a colour ends in a hex digit or a `)`.
    private static func couldBeColor(_ bytes: String.UTF8View) -> Bool {
        guard let first = bytes.first(where: { !isSpace($0) }),
            let last = bytes.reversed().first(where: { !isSpace($0) })
        else { return false }
        if first == UInt8(ascii: "#") { return isHex(last) }
        return isLetter(first) && last == UInt8(ascii: ")")
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "z")
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || ((byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "f"))
    }

    /// `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa` — the four lengths CSS defines.
    private static func parseHex(_ digits: Substring) -> ColorValue? {
        // ASCII, since `isHexDigit` also accepts the fullwidth forms no colour is written in.
        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let channels: [Double]
        switch digits.count {
        case 3, 4:
            // Shorthand doubles each digit, so `#0f0` is `#00ff00` rather than `#0f0f00`.
            channels = digits.compactMap { $0.hexDigitValue.map { Double($0 * 17) / 255 } }
        case 6, 8:
            channels = stride(from: 0, to: digits.count, by: 2).compactMap { offset in
                let start = digits.index(digits.startIndex, offsetBy: offset)
                let end = digits.index(start, offsetBy: 2)
                return UInt8(digits[start..<end], radix: 16).map { Double($0) / 255 }
            }
        default:
            return nil
        }
        guard channels.count == digits.count / (digits.count <= 4 ? 1 : 2) else { return nil }
        return ColorValue(
            red: channels[0], green: channels[1], blue: channels[2],
            alpha: channels.count == 4 ? channels[3] : 1)
    }

    /// `rgb()` / `rgba()` / `hsl()` / `hsla()`, in both the comma and the CSS4 space form.
    private static func parseFunctional(_ token: String) -> ColorValue? {
        guard let open = token.firstIndex(of: "("), token.hasSuffix(")") else { return nil }
        let function = token[token.startIndex..<open].lowercased()
        let body = token[token.index(after: open)..<token.index(before: token.endIndex)]
        // `rgba` is an alias of `rgb` rather than its own function, so alpha is always optional.
        guard let parts = arguments(of: body), parts.count == 3 || parts.count == 4,
            let alpha = parts.count == 4 ? component(parts[3], scale: 1) : 1
        else { return nil }
        switch function {
        case "rgb", "rgba":
            guard let red = component(parts[0], scale: 255),
                let green = component(parts[1], scale: 255),
                let blue = component(parts[2], scale: 255)
            else { return nil }
            return ColorValue(red: red, green: green, blue: blue, alpha: alpha)
        case "hsl", "hsla":
            // CSS spells both as percentages; a bare `100` would read as 1.0 and answer white.
            guard let hue = angle(parts[0]), let saturation = percentage(parts[1]),
                let lightness = percentage(parts[2])
            else { return nil }
            return ColorValue(
                hue: hue, saturation: saturation, lightness: lightness, alpha: alpha)
        default:
            return nil
        }
    }

    /// One channel as a fraction of `scale`; a trailing `%` is always a fraction of the whole.
    private static func component(_ text: String, scale: Double) -> Double? {
        // `Double` reads `nan`, `inf` and Swift literals CSS never writes, like `0x10` as 16.
        guard text.allSatisfy({ $0.isASCII && ($0.isNumber || ".-%".contains($0)) }) else {
            return nil
        }
        let value =
            text.hasSuffix("%")
            ? Double(text.dropLast()).map { $0 / 100 } : Double(text).map { $0 / scale }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }

    /// A channel CSS only ever writes as a percentage.
    private static func percentage(_ text: String) -> Double? {
        text.hasSuffix("%") ? component(text, scale: 1) : nil
    }

    /// Comma-separated or space-with-slash, never mixed — so the comma decides which is read.
    private static func arguments(of body: Substring) -> [String]? {
        let parts: [String]
        if body.contains(",") {
            guard !body.contains("/") else { return nil }
            parts = body.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            // Counted per side: flattened, `rgb(0 255 / 0.5)` reads an alpha as its blue channel.
            let sides = body.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" })
                .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            switch sides.count {
            // Alpha is spelled behind the slash, so an unseparated fourth argument is malformed.
            case 1 where sides[0].count == 3: parts = sides[0]
            case 2 where sides[0].count == 3 && sides[1].count == 1: parts = sides[0] + sides[1]
            default: return nil
            }
        }
        return parts.allSatisfy { !$0.isEmpty } ? parts : nil
    }

    /// A hue in degrees, normalised into 0…<360 so `-30deg` and `330` agree.
    private static func angle(_ text: String) -> Double? {
        let digits = text.lowercased().hasSuffix("deg") ? String(text.dropLast(3)) : text
        guard let degrees = Double(digits), degrees.isFinite else { return nil }
        return degrees.truncatingRemainder(dividingBy: 360) + (degrees < 0 ? 360 : 0)
    }
}
