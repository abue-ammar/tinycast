import AppKit
import SwiftUI
import Testing

@testable import Tinycast

/// Pins `AGENTS.md`: a token's dark branch is the literal the forced-dark build shipped.
@MainActor
struct AppearanceTests {
    struct Token: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let color: Color
    }

    struct DarkLiteral: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let color: Color
        let shipped: Color
    }

    nonisolated static let colors = Theme.Colors.self

    nonisolated static let darkLiterals = [
        DarkLiteral(testDescription: "panelScrim", color: colors.panelScrim, shipped: .black.opacity(0.4)),
        DarkLiteral(
            testDescription: "dialogDimming", color: colors.dialogDimming, shipped: .black.opacity(0.34)),
        DarkLiteral(
            testDescription: "tooltipShadow", color: colors.tooltipShadow, shipped: .black.opacity(0.18)),
        DarkLiteral(testDescription: "selection", color: colors.selection, shipped: .white.opacity(0.10)),
        DarkLiteral(testDescription: "rowHover", color: colors.rowHover, shipped: .white.opacity(0.05)),
        DarkLiteral(testDescription: "menuHover", color: colors.menuHover, shipped: .white.opacity(0.10)),
        DarkLiteral(testDescription: "separator", color: colors.separator, shipped: .white.opacity(0.10)),
        DarkLiteral(
            testDescription: "controlSurface", color: colors.controlSurface, shipped: .white.opacity(0.10)),
        DarkLiteral(testDescription: "border", color: colors.border, shipped: .white.opacity(0.20)),
        DarkLiteral(
            testDescription: "textSecondary", color: colors.textSecondary, shipped: .white.opacity(0.60)),
        DarkLiteral(
            testDescription: "textTertiary", color: colors.textTertiary, shipped: .white.opacity(0.40)),
        DarkLiteral(testDescription: "noteText", color: colors.noteText, shipped: .white.opacity(0.90)),
        DarkLiteral(testDescription: "cardFill", color: colors.cardFill, shipped: .white.opacity(0.05)),
        DarkLiteral(testDescription: "cardStroke", color: colors.cardStroke, shipped: .white.opacity(0.10)),
        DarkLiteral(testDescription: "dropGuide", color: colors.dropGuide, shipped: .white.opacity(0.35)),
        DarkLiteral(
            testDescription: "brand", color: colors.brand, shipped: Color(red: 0.525, green: 0.231, blue: 1.0)
        ),
        DarkLiteral(
            testDescription: "iconPlaceholder", color: colors.iconPlaceholder, shipped: .white.opacity(0.06)),
        DarkLiteral(testDescription: "textPrimary", color: colors.textPrimary, shipped: .white),
        // VolumeHUDView draws white 0.85; textPrimary is alpha 1, so opacity must reproduce it.
        DarkLiteral(
            testDescription: "textPrimary at 0.85", color: colors.textPrimary.opacity(0.85),
            shipped: .white.opacity(0.85))
    ]

    nonisolated static let surfaces = [
        Token(testDescription: "panelScrim", color: colors.panelScrim),
        Token(testDescription: "selection", color: colors.selection),
        Token(testDescription: "rowHover", color: colors.rowHover),
        Token(testDescription: "menuHover", color: colors.menuHover),
        Token(testDescription: "separator", color: colors.separator),
        Token(testDescription: "controlSurface", color: colors.controlSurface),
        Token(testDescription: "border", color: colors.border),
        Token(testDescription: "textPrimary", color: colors.textPrimary),
        Token(testDescription: "textSecondary", color: colors.textSecondary),
        Token(testDescription: "textTertiary", color: colors.textTertiary),
        Token(testDescription: "noteText", color: colors.noteText),
        Token(testDescription: "cardFill", color: colors.cardFill),
        Token(testDescription: "cardStroke", color: colors.cardStroke),
        Token(testDescription: "dropGuide", color: colors.dropGuide),
        Token(testDescription: "iconPlaceholder", color: colors.iconPlaceholder)
    ]

    // MARK: Colour tokens

    @Test(arguments: darkLiterals)
    func aDarkBranchIsTheShippedLiteral(_ token: DarkLiteral) throws {
        #expect(
            try Self.components(token.color, in: .darkAqua) == Self.components(token.shipped, in: .darkAqua))
    }

    /// A token that resolves identically in both never adapted at all.
    @Test(arguments: surfaces)
    func aSurfaceTokenResolvesPerAppearance(_ token: Token) throws {
        #expect(try Self.components(token.color, in: .darkAqua) != Self.components(token.color, in: .aqua))
    }

    @Test func theScrimInvertsRatherThanRamping() throws {
        #expect(try Self.components(Self.colors.panelScrim, in: .aqua)[0] == 255)
        #expect(try Self.components(Self.colors.panelScrim, in: .darkAqua)[0] == 0)
    }

    // MARK: App appearance

    @Test func systemHandsTheChoiceBackToAppKit() {
        #expect(AppAppearance.system.nsAppearance == nil)
    }

    @Test func lightAndDarkPinTheirAppearance() {
        #expect(AppAppearance.light.nsAppearance?.isDark == false)
        #expect(AppAppearance.dark.nsAppearance?.isDark == true)
    }

    @Test func anUnknownStoredAppearanceIsRejected() {
        #expect(AppAppearance(rawValue: "sepia") == nil)
    }

    // MARK: System icon style

    @Test(arguments: [nil, "Sepia", "Clear"] as [String?])
    func anUnsetUnknownOrShadelessStyleIsDefault(_ stored: String?) {
        #expect(SystemIconTheme(stored: stored) == .standard)
    }

    @Test func aStoredStyleSplitsIntoMaterialAndShade() {
        let clearDark = SystemIconTheme(stored: "ClearDark")
        #expect(clearDark.material == .clear)
        #expect(clearDark.shade == .dark)
        let tinted = SystemIconTheme(stored: "TintedAutomatic")
        #expect(tinted.material == .tinted)
        #expect(tinted.shade == .automatic)
        #expect(SystemIconTheme(stored: "RegularDark").shade == .dark)
    }

    @Test func anAutomaticShadeFollowsTheSurface() {
        let tinted = SystemIconTheme(stored: "TintedAutomatic")
        #expect(tinted.isDark(onDarkSurface: true))
        #expect(!tinted.isDark(onDarkSurface: false))
    }

    @Test func aFixedShadeIgnoresTheSurface() {
        #expect(SystemIconTheme(stored: "ClearDark").isDark(onDarkSurface: false))
    }

    @Test func anUnsetTintUsesTheAccent() {
        #expect(SystemIconTheme(stored: "TintedAutomatic").tint == .accent)
    }

    @Test func clearIgnoresTheSavedTint() {
        #expect(
            SystemIconTheme(stored: "ClearDark", storedTint: "Blue") == SystemIconTheme(stored: "ClearDark"))
    }

    @Test func aNamedTintIgnoresOldCustomComponents() {
        let theme = SystemIconTheme(stored: "TintedDark", storedTint: "Graphite", customTint: "0 0.4 1 0.9")
        #expect(theme.tint == .preset(.graphite))
    }

    @Test func aCustomTintPreservesItsRGBAComponents() {
        let theme = SystemIconTheme(stored: "TintedDark", storedTint: "Other", customTint: "0 0.4 1 0.9")
        #expect(theme.tint == .custom(red: 0, green: 0.4, blue: 1, opacity: 0.9))
    }

    @Test(arguments: ["0 0 1", "0 0 1 1 extra", "nan 0 1 1", "0 0 1 1.5"])
    func anInvalidCustomTintUsesTheAccent(_ components: String) {
        let theme = SystemIconTheme(stored: "TintedDark", storedTint: "Other", customTint: components)
        #expect(theme.tint == .accent)
    }

    /// Quantized to the 8 bits that reach the framebuffer: `CGFloat`s carry Float error.
    private static func components(_ color: Color, in name: NSAppearance.Name) throws -> [Int] {
        let appearance = try #require(NSAppearance(named: name))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = NSColor(color).usingColorSpace(.sRGB) }
        let srgb = try #require(resolved)
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
            .map { Int(($0 * 255).rounded()) }
    }
}
