import AppKit
import SwiftUI

/// Against the real `Theme`, so the system face can never drift from what the app ships today.
@main
@MainActor
struct InterfaceFontTests {
    static var failures = 0
    static var passes = 0

    /// Present on every macOS, so the harness does not depend on what this Mac has installed.
    static let family = "Helvetica"

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static let textStyles: [(String, NSFont.TextStyle)] = [
        ("body", .body), ("callout", .callout), ("subheadline", .subheadline),
        ("headline", .headline), ("title1", .title1), ("title2", .title2),
        ("title3", .title3), ("caption1", .caption1), ("caption2", .caption2)
    ]

    static func main() {
        theSystemFaceIsThemeVerbatim()
        aFamilyReachesEveryTextToken()
        aFamilyKeepsEachStylesWeight()
        anUnknownFamilyFallsBack()
        symbolTokensIgnoreTheFamily()
        theFamilyComposesWithScale()
        theCatalogIsWellFormed()

        print("interface-font-test: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// The `.standard` guarantee, extended: an unset font changes nothing anywhere.
    static func theSystemFaceIsThemeVerbatim() {
        let t = InterfaceMetrics.standard.typography
        expect(t.rowTitle == Theme.Typography.rowTitle, "rowTitle is Theme verbatim")
        expect(t.rowTrailing == Theme.Typography.rowTrailing, "rowTrailing is Theme verbatim")
        expect(t.sectionHeader == Theme.Typography.sectionHeader, "sectionHeader is Theme verbatim")
        expect(t.panelTitle == Theme.Typography.panelTitle, "panelTitle is Theme verbatim")
        expect(t.calcResult == Theme.Typography.calcResult, "calcResult is Theme verbatim")
        expect(t.cardTitle == Theme.Typography.cardTitle, "cardTitle is Theme verbatim")
        expect(t.code == Theme.Typography.code, "code keeps its monospaced design")
        expect(t.previewCode == Theme.Typography.previewCode, "previewCode keeps its design")
        expect(t.inlineCode == Theme.Typography.inlineCode, "inlineCode keeps its design")
        expect(t.searchField == Theme.Typography.searchField, "searchField is Theme verbatim")
        expect(
            t.searchFieldNSFont == Theme.Typography.searchFieldNSFont,
            "searchFieldNSFont is Theme verbatim")
        expect(t.chipNSFont == Theme.Typography.chipNSFont, "chipNSFont is Theme verbatim")
        expect(InterfaceMetrics.standard.fontFamily == nil, "standard names no family")
    }

    static func aFamilyReachesEveryTextToken() {
        let t = InterfaceMetrics(scale: 1, fontFamily: family).typography
        for (name, style) in textStyles {
            expect(t.nsFont(style).familyName == family, "\(name) resolves on \(family)")
        }
        expect(t.searchFieldNSFont.familyName == family, "the search field resolves on \(family)")
        expect(t.chipNSFont.familyName == family, "the chip measurer resolves on \(family)")
        expect(
            NoteMarkdownTypography(fontFamily: family).body.familyName == family,
            "the note editor resolves on \(family)")
        expect(
            NoteMarkdownTypography(fontFamily: family).codeBlock.familyName == family,
            "a note code block takes the family too, since one font means one font")
    }

    /// The regression docs/ui.md warns about: a weight table lightens `.headline` off its face.
    static func aFamilyKeepsEachStylesWeight() {
        let t = InterfaceMetrics(scale: 1, fontFamily: family).typography
        let manager = NSFontManager.shared
        for (name, style) in textStyles {
            let system = NSFont.preferredFont(forTextStyle: style)
            expect(
                manager.weight(of: t.nsFont(style)) == manager.weight(of: system),
                "\(name) keeps the weight the system style has")
            expect(
                t.nsFont(style).pointSize == system.pointSize,
                "\(name) keeps the size the system style has")
        }
        expect(
            manager.traits(of: t.nsFont(.headline)).contains(.boldFontMask),
            "headline stays Bold on a family that has a Bold")
    }

    static func anUnknownFamilyFallsBack() {
        let t = InterfaceMetrics(scale: 1, fontFamily: "NoSuchFamilyInstalledHere").typography
        for (name, style) in textStyles {
            let system = NSFont.preferredFont(forTextStyle: style)
            expect(t.nsFont(style).fontName == system.fontName, "\(name) falls back to the system face")
        }
        expect(
            t.searchFieldNSFont.fontName
                == NSFont.systemFont(ofSize: Theme.Typography.searchFieldSize, weight: .regular).fontName,
            "the search field falls back to the system face")
        expect(
            NoteMarkdownTypography(fontFamily: "NoSuchFamilyInstalledHere").body.fontName
                == NoteMarkdownTypography.system.body.fontName,
            "the note editor falls back to the system face")
    }

    /// These size an SF Symbol rather than setting type, so a family must not reach them.
    static func symbolTokensIgnoreTheFamily() {
        let system = InterfaceMetrics.standard.typography
        let chosen = InterfaceMetrics(scale: 1, fontFamily: family).typography
        expect(chosen.headerIcon == system.headerIcon, "headerIcon ignores the family")
        expect(chosen.menuIcon == system.menuIcon, "menuIcon ignores the family")
        expect(chosen.disclosure == system.disclosure, "disclosure ignores the family")
        expect(chosen.placeholderGlyph == system.placeholderGlyph, "placeholderGlyph ignores the family")
    }

    static func theFamilyComposesWithScale() {
        for size in InterfaceSize.allCases {
            let t = InterfaceMetrics(scale: size.scale, fontFamily: family).typography
            for (name, style) in textStyles {
                let scaled = InterfaceMetrics(scale: size.scale).typography.nsFont(style)
                expect(
                    t.nsFont(style).familyName == family,
                    "\(name) keeps the family at \(size.title)")
                expect(
                    t.nsFont(style).pointSize == scaled.pointSize,
                    "\(name) keeps the scaled size at \(size.title)")
            }
            expect(
                t.searchFieldSize == InterfaceMetrics(scale: size.scale).typography.searchFieldSize,
                "the search field keeps its scaled size at \(size.title)")
        }
    }

    static func theCatalogIsWellFormed() {
        let families = FontCatalog.installedFamilies()
        expect(!families.isEmpty, "the Mac reports at least one family")
        expect(!families.contains { $0.hasPrefix(".") }, "no private family is offered")
        expect(
            families == families.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            "the list is sorted for display")
        expect(Set(families).count == families.count, "no family is listed twice")
        expect(FontCatalog.isInstalled(family), "\(family) reads as installed")
        expect(!FontCatalog.isInstalled("NoSuchFamilyInstalledHere"), "an absent family reads as absent")
    }
}
