import Foundation

/// Oklab and its polar form, the space behind the one perceptual notation a colour copies as.
extension ColorValue {
    /// Oklab is defined on light, not on the gamma-encoded numbers a hex triplet carries.
    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private var linearComponents: (r: Double, g: Double, b: Double) {
        (Self.linear(red), Self.linear(green), Self.linear(blue))
    }

    /// Oklab: the same idea as Lab, fitted so equal steps look equal. `l` is 0…1.
    private var oklab: (l: Double, a: Double, b: Double) {
        let (r, g, b) = linearComponents
        let long = Self.cubeRoot(0.4122215 * r + 0.5363325 * g + 0.0514460 * b)
        let medium = Self.cubeRoot(0.2119035 * r + 0.6806995 * g + 0.1073970 * b)
        let short = Self.cubeRoot(0.0883025 * r + 0.2817188 * g + 0.6299787 * b)
        return (
            0.2104543 * long + 0.7936178 * medium - 0.0040720 * short,
            1.9779985 * long - 2.4285922 * medium + 0.4505937 * short,
            0.0259040 * long + 0.7827718 * medium - 0.8086758 * short
        )
    }

    var oklch: (l: Double, c: Double, h: Double) {
        let oklab = oklab
        return (
            oklab.l, (oklab.a * oklab.a + oklab.b * oklab.b).squareRoot(),
            Self.hueDegrees(oklab.a, oklab.b)
        )
    }

    /// `pow` is undefined for a negative base at a fractional exponent, and a channel can be one.
    private static func cubeRoot(_ value: Double) -> Double {
        value < 0 ? -pow(-value, 1.0 / 3) : pow(value, 1.0 / 3)
    }

    /// Zero for a neutral: `atan2` over two rounding errors would still name a direction.
    private static func hueDegrees(_ a: Double, _ b: Double) -> Double {
        guard abs(a) > 1e-6 || abs(b) > 1e-6 else { return 0 }
        let degrees = atan2(b, a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// The inverse of `oklch`: a colour picker states its swatch in the space, not in hex.
    init(lightness: Double, chroma: Double, hue: Double, alpha: Double = 1) {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let long = Self.cubed(lightness + 0.3963377774 * a + 0.2158037573 * b)
        let medium = Self.cubed(lightness - 0.1055613458 * a - 0.0638541728 * b)
        let short = Self.cubed(lightness - 0.0894841775 * a - 1.2914855480 * b)
        self.init(
            red: Self.gamma(4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short),
            green: Self.gamma(-1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short),
            blue: Self.gamma(-0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short),
            alpha: alpha)
    }

    private static func cubed(_ value: Double) -> Double { value * value * value }

    /// The inverse of `linear`; a channel below the split can be negative, and `pow` answers NaN.
    private static func gamma(_ channel: Double) -> Double {
        channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
    }
}
