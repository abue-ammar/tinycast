import Testing

@testable import Tinycast

extension ClipboardTests {
    @Test(arguments: [
        ("#FF5733", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255)),
        ("#0f0", ColorValue(red: 0, green: 1, blue: 0)),
        ("#0f08", ColorValue(red: 0, green: 1, blue: 0, alpha: 136 / 255)),
        ("rgb(255, 87, 51)", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255)),
        ("rgb(0 255 0 / 0.5)", ColorValue(red: 0, green: 1, blue: 0, alpha: 0.5)),
        ("rgba(255,87,51,0.5)", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255, alpha: 0.5)),
        ("hsl(120, 100%, 50%)", ColorValue(red: 0, green: 1, blue: 0)),
        ("hsl(10.6deg 100% 60%)", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255)),
        ("oklch(62.7955% 0.257683 29.2338)", ColorValue(red: 1, green: 0, blue: 0)),
        ("oklch(0.627955 64.42% 29.2338deg / 0.5)", ColorValue(red: 1, green: 0, blue: 0, alpha: 0.5))
    ])
    func recognizedColorNotationsResolveToSRGB(_ text: String, _ expected: ColorValue) throws {
        let parsed = try #require(ColorValue.parse(text))
        #expect(channelDifferences(parsed, expected).allSatisfy { $0 < 1.0 / 255 })
    }

    @Test(arguments: [
        "#FF5733 and more", "rgb(255, 87, 51) plus", "(255, 87, 51)", "#", "rgb",
        "#GGGGGG", "#12345", "#", "report.pdf", "rgb(1, 2)", "rgb(1, 2, 3", "hsl(1, 2, 3, 4, 5)",
        "cmyk(0, 1, 1, 0)", "255, 87, 51", "#" + String(repeating: "f", count: 96),
        "rgb(nan, 0, 0)", "hsl(inf, 100%, 50%)", "rgb(1e400, 0, 0)", "rgba(0, 0, 0, nan)",
        "hsl(120, 100, 50)", "hsl(120 100 50)", "hsla(120, 100, 50, 1)",
        "rgb(255,,87,51)", "rgb(255,87,51,)", "rgb(255, 87)", "rgb()", "rgb(1,2,3,4,5)",
        "rgb(1/2, 3, 4)", "rgb(255, 87, 51 / 0.5)", "rgb(0 255 0 / 0.5 / 1)", "rgb(/0.5)",
        "rgb(0 255 / 0.5)", "hsl(120 100% / 50%)", "rgb(0 / 255 0)", "rgb(0 255 0 0)",
        "rgb(0x10, 0, 0)", "rgb(1e2, 0, 0)", "rgb(+255, 0, 0)", "#\u{ff46}\u{ff46}\u{ff46}"
    ])
    func malformedColorsAndPartialMatchesAreRejected(_ text: String) {
        #expect(ColorValue.parse(text) == nil)
    }

    @Test(arguments: [
        "rgba(255, 87, 51)", "rgb(255, 87, 51, 0.5)", "hsla(120, 100%, 50%)",
        "hsl(120, 100%, 50%, 0.5)", "hsl(120, 100%, 50%, 50%)", "rgb(0 255 0)",
        "rgb(255,\n87,\n51)", "rgb(0\n255\n0)"
    ])
    func CSSAliasesAcceptOptionalAlphaAndMultilineWhitespace(_ text: String) {
        #expect(ColorValue.parse(text) != nil)
    }

    @Test func almostWhiteHasFiniteSaturationAndFormatsInEveryOfferedNotation() throws {
        let color = try #require(ColorValue.parse("rgb(100%, 100%, 99.99999999999999%)"))
        #expect(ColorFormat.offered(for: color).allSatisfy { !$0.string(for: color).isEmpty })
        #expect(color.hsl.saturation.isFinite)
    }

    @Test func fourDigitHexExpandsItsAlphaNibble() throws {
        let color = try #require(ColorValue.parse("#0f0f"))
        #expect(ColorFormat.hexWithAlpha.string(for: color) == "#00FF00FF")
    }

    @Test func anOpaqueHexAlphaChannelDoesNotRequireAnAlphaFormat() throws {
        let color = try #require(ColorValue.parse("#000000FF"))
        #expect(!color.hasAlpha)
    }

    @Test func convertingToHSLAndBackPreservesSRGBChannels() {
        let original = ColorValue(red: 0.2, green: 0.6, blue: 0.9)
        let hsl = original.hsl
        let restored = ColorValue(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)
        #expect(channelDifferences(restored, original).allSatisfy { $0 < 1.0 / 255 })
    }

    @Test(arguments: [
        ("#FF5733", ColorFormat.hex, "#FF5733"),
        ("#FF5733", .rgba, "rgba(255, 87, 51, 1)"),
        ("#FF5733", .hsl, "hsl(10.6deg, 100%, 60%)"),
        ("#FF5733", .oklch, "oklch(68% 0.21 33.7deg)"),
        ("rgba(255, 87, 51, 0.5)", .hexWithAlpha, "#FF573380"),
        ("#DDDDDD", .oklch, "oklch(89.8% 0 0deg)"),
        ("rgba(0, 255, 0, 0.5)", .oklch, "oklch(86.6% 0.295 142.5deg / 0.5)")
    ])
    func colorFormatsPreserveSpecifiedPrecisionAndAlpha(
        _ input: String, _ format: ColorFormat, _ expected: String
    ) throws {
        let color = try #require(ColorValue.parse(input))
        #expect(format.string(for: color) == expected)
    }

    @Test func opaqueColorsDefaultToHexAndOmitTheTwoExplicitAlphaFormats() throws {
        let color = try #require(ColorValue.parse("#FF5733"))
        let offered = ColorFormat.offered(for: color)
        #expect(!offered.contains(.hslWithAlpha))
        #expect(offered.count == ColorFormat.allCases.count - 2)
        #expect(ColorFormat.primary(for: color) == .hex)
    }

    @Test func translucentColorsOfferEveryFormatAndDefaultToHexWithAlpha() throws {
        let color = try #require(ColorValue.parse("rgba(255, 87, 51, 0.5)"))
        #expect(ColorFormat.offered(for: color) == ColorFormat.allCases)
        #expect(ColorFormat.primary(for: color) == .hexWithAlpha)
    }

    nonisolated private static let sampledColors: [ColorValue] = stride(from: 0, through: 255, by: 17).flatMap { red in
        stride(from: 0, through: 255, by: 29).flatMap { green in
            stride(from: 0, through: 255, by: 43).flatMap { blue in
                [255, 128].map { alpha in
                    ColorValue(red: Double(red) / 255, green: Double(green) / 255,
                        blue: Double(blue) / 255, alpha: Double(alpha) / 255)
                }
            }
        }
    }

    @Test(arguments: sampledColors)
    func offeredHighPrecisionFormatsRoundTripToWithinOneChannel(_ color: ColorValue) throws {
        for format in ColorFormat.offered(for: color) where format != .oklch {
            let text = format.string(for: color)
            let parsed = try #require(ColorValue.parse(text), "\(text)")
            let differences = channelDifferences(parsed, color, includeAlpha: parsed.hasAlpha == color.hasAlpha)
            #expect(differences.allSatisfy { $0 < 1.0 / 255 }, "\(text)")
        }
    }

    @Test func theColorSweepExercisesMoreThanFiveHundredRoundTrips() {
        let total = Self.sampledColors.reduce(0) { count, color in
            count + ColorFormat.offered(for: color).filter { $0 != .oklch }.count
        }
        #expect(total > 500)
    }

    private func channelDifferences(
        _ first: ColorValue, _ second: ColorValue, includeAlpha: Bool = true
    ) -> [Double] {
        var differences = [abs(first.red - second.red), abs(first.green - second.green), abs(first.blue - second.blue)]
        if includeAlpha { differences.append(abs(first.alpha - second.alpha)) }
        return differences
    }
}
