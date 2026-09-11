import AppKit
import SwiftUI

/// Against the real `Theme`, so `.standard` can never drift from what the app ships today.
@main
@MainActor
struct InterfaceSizeTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(abs(actual - expected) < 0.001, "\(message) — got \(actual), want \(expected)")
    }

    static func main() {
        theDefaultIsThemeVerbatim()
        fontsKeepTheirFace()
        everySizeRounds()
        sizesGrow()
        derivationsHold()
        theEnumIsWellFormed()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Identity at the default size

    /// Every member, so a mistyped `Theme` reference in `InterfaceMetrics` cannot ship silently.
    static func theDefaultIsThemeVerbatim() {
        let m = InterfaceMetrics.standard
        expect(m.scale, 1, "the default scale is 1")

        expect(m.spacing.xxs, Theme.Spacing.xxs, "spacing.xxs")
        expect(m.spacing.xs, Theme.Spacing.xs, "spacing.xs")
        expect(m.spacing.sm, Theme.Spacing.sm, "spacing.sm")
        expect(m.spacing.md, Theme.Spacing.md, "spacing.md")
        expect(m.spacing.lg, Theme.Spacing.lg, "spacing.lg")
        expect(m.spacing.xl, Theme.Spacing.xl, "spacing.xl")
        expect(m.spacing.xxl, Theme.Spacing.xxl, "spacing.xxl")
        expect(m.spacing.xxxl, Theme.Spacing.xxxl, "spacing.xxxl")
        expect(
            m.spacing.sectionHeaderBottom, Theme.Spacing.sectionHeaderBottom,
            "spacing.sectionHeaderBottom")
        expect(m.spacing.sectionSpacing, Theme.Spacing.sectionSpacing, "spacing.sectionSpacing")
        expect(
            m.spacing.chatTranscriptBottom, Theme.Spacing.chatTranscriptBottom,
            "spacing.chatTranscriptBottom")
        expect(
            m.spacing.chatFollowTailSlack, Theme.Spacing.chatFollowTailSlack,
            "spacing.chatFollowTailSlack")

        expect(m.radius.panel, Theme.Radius.panel, "radius.panel")
        expect(m.radius.row, Theme.Radius.row, "radius.row")
        expect(m.radius.menu, Theme.Radius.menu, "radius.menu")
        expect(m.radius.menuRow, Theme.Radius.menuRow, "radius.menuRow")
        expect(m.radius.barControl, Theme.Radius.barControl, "radius.barControl")
        expect(m.radius.menuPanel, Theme.Radius.menuPanel, "radius.menuPanel")
        expect(m.radius.dialog, Theme.Radius.dialog, "radius.dialog")
        expect(m.radius.thumbnail, Theme.Radius.thumbnail, "radius.thumbnail")
        expect(m.radius.glyph, Theme.Radius.glyph, "radius.glyph")
        expect(m.radius.attachmentChip, Theme.Radius.attachmentChip, "radius.attachmentChip")
        expect(m.radius.card, Theme.Radius.card, "radius.card")
        expect(m.radius.keyCap, Theme.Radius.keyCap, "radius.keyCap")

        expect(m.size.panelWidth, Theme.Size.panelWidth, "size.panelWidth")
        expect(m.size.panelHeight, Theme.Size.panelHeight, "size.panelHeight")
        expect(m.size.headerHeight, Theme.Size.headerHeight, "size.headerHeight")
        expect(m.size.headerIconSlot, Theme.Size.headerIconSlot, "size.headerIconSlot")
        expect(m.size.headerPadding, Theme.Size.headerPadding, "size.headerPadding")
        expect(m.size.compactHeight, Theme.Size.compactHeight, "size.compactHeight")
        expect(m.size.bottomBarHeight, Theme.Size.bottomBarHeight, "size.bottomBarHeight")
        expect(m.size.barButtonHeight, Theme.Size.barButtonHeight, "size.barButtonHeight")
        expect(m.size.rowIcon, Theme.Size.rowIcon, "size.rowIcon")
        expect(m.size.keyCap, Theme.Size.keyCap, "size.keyCap")
        expect(m.size.compactKeyCap, Theme.Size.compactKeyCap, "size.compactKeyCap")
        expect(m.size.heroKeyCap, Theme.Size.heroKeyCap, "size.heroKeyCap")
        expect(m.size.menuButton, Theme.Size.menuButton, "size.menuButton")
        expect(m.size.checkbox, Theme.Size.checkbox, "size.checkbox")
        expect(m.size.menuWidth, Theme.Size.menuWidth, "size.menuWidth")
        expect(
            m.size.clipboardFilterMenuWidth, Theme.Size.clipboardFilterMenuWidth,
            "size.clipboardFilterMenuWidth")
        expect(m.size.menuIcon, Theme.Size.menuIcon, "size.menuIcon")
        expect(m.size.menuBrandIcon, Theme.Size.menuBrandIcon, "size.menuBrandIcon")
        expect(m.size.barBrandIcon, Theme.Size.barBrandIcon, "size.barBrandIcon")
        expect(m.size.menuRowSpacing, Theme.Size.menuRowSpacing, "size.menuRowSpacing")
        expect(m.size.menuSectionHeader, Theme.Size.menuSectionHeader, "size.menuSectionHeader")
        expect(m.size.menuRowHeight, Theme.Size.menuRowHeight, "size.menuRowHeight")
        expect(m.size.menuRowsMaxHeight, Theme.Size.menuRowsMaxHeight, "size.menuRowsMaxHeight")
        expect(m.size.clipboardListWidth, Theme.Size.clipboardListWidth, "size.clipboardListWidth")
        expect(
            m.size.clipboardMediaHeight, Theme.Size.clipboardMediaHeight, "size.clipboardMediaHeight")
        expect(
            m.size.clipboardPreviewPixel, Theme.Size.clipboardPreviewPixel,
            "size.clipboardPreviewPixel")
        expect(m.size.emojiCell, Theme.Size.emojiCell, "size.emojiCell")
        expect(m.size.formLabelWidth, Theme.Size.formLabelWidth, "size.formLabelWidth")
        expect(m.size.argumentPromptWidth, Theme.Size.argumentPromptWidth, "size.argumentPromptWidth")
        expect(m.size.markdownListMarker, Theme.Size.markdownListMarker, "size.markdownListMarker")
        expect(m.size.markdownQuoteBar, Theme.Size.markdownQuoteBar, "size.markdownQuoteBar")
        expect(m.size.chatMessageAction, Theme.Size.chatMessageAction, "size.chatMessageAction")
        expect(m.size.chatImageThumb, Theme.Size.chatImageThumb, "size.chatImageThumb")
        expect(m.size.chatAttachmentGlyph, Theme.Size.chatAttachmentGlyph, "size.chatAttachmentGlyph")
        expect(m.size.chatAttachmentThumb, Theme.Size.chatAttachmentThumb, "size.chatAttachmentThumb")
        expect(
            m.size.chatAttachmentRemove, Theme.Size.chatAttachmentRemove, "size.chatAttachmentRemove")
        expect(m.size.chatAttachmentInset, Theme.Size.chatAttachmentInset, "size.chatAttachmentInset")
        expect(m.size.quickActionPanel, Theme.Size.quickActionPanel, "size.quickActionPanel")
        expect(
            m.size.quickActionHeaderIcon, Theme.Size.quickActionHeaderIcon,
            "size.quickActionHeaderIcon")
        expect(
            m.size.quickActionScrollFade, Theme.Size.quickActionScrollFade,
            "size.quickActionScrollFade")
        expect(m.size.quickActionPanelBody, Theme.Size.quickActionPanelBody, "size.quickActionPanelBody")
        expect(
            m.size.quickActionPanelMinBody, Theme.Size.quickActionPanelMinBody,
            "size.quickActionPanelMinBody")
        expect(m.size.dialogWidth, Theme.Size.dialogWidth, "size.dialogWidth")
        expect(m.size.dialogIcon, Theme.Size.dialogIcon, "size.dialogIcon")
        expect(m.size.hudMaxWidth, Theme.Size.hudMaxWidth, "size.hudMaxWidth")
        expect(m.size.hudWidth, Theme.Size.hudWidth, "size.hudWidth")
        expect(m.size.hudHeight, Theme.Size.hudHeight, "size.hudHeight")
        expect(m.size.volumeTrackHeight, Theme.Size.volumeTrackHeight, "size.volumeTrackHeight")
        expect(m.size.volumeKnob, Theme.Size.volumeKnob, "size.volumeKnob")
        expect(m.size.volumeReadout, Theme.Size.volumeReadout, "size.volumeReadout")

        expect(m.typography.searchFieldSize, Theme.Typography.searchFieldSize, "typography.searchField")
        expect(
            m.typography.searchFieldNSFont == Theme.Typography.searchFieldNSFont,
            "typography.searchFieldNSFont is the Theme font itself")
        expect(
            m.typography.chipNSFont == Theme.Typography.chipNSFont,
            "typography.chipNSFont is the Theme font itself")

        // Extensions duplicates the mechanism rather than importing it, so it is checked here too.
        expect(ExtensionFormMetrics.base.scale, 1, "the form metrics base is unscaled")
    }

    // MARK: - Fonts

    /// `.headline` is Bold and `.caption2` Medium: a size-and-weight rebuild would lighten both.
    static func fontsKeepTheirFace() {
        for size in InterfaceSize.allCases {
            let metrics = size.metrics
            for style in [NSFont.TextStyle.body, .callout, .subheadline, .headline, .caption2] {
                let base = NSFont.preferredFont(forTextStyle: style)
                let scaled = NSFont(
                    descriptor: base.fontDescriptor,
                    size: (base.pointSize * size.scale).rounded())
                expect(scaled != nil, "\(style.rawValue) rebuilds from its own descriptor")
                expect(
                    scaled?.familyName == base.familyName,
                    "\(style.rawValue) keeps its family at \(size.rawValue)")
                expect(
                    scaled?.fontName == base.fontName,
                    "\(style.rawValue) keeps its face at \(size.rawValue)")
            }
            expect(
                metrics.typography.searchFieldSize
                    == (Theme.Typography.searchFieldSize * size.scale).rounded(),
                "the search field's stated size scales at \(size.rawValue)")
        }
    }

    // MARK: - Rounding and growth

    static func everySizeRounds() {
        for size in InterfaceSize.allCases {
            let m = size.metrics
            for (name, value) in lengths(m) {
                expect(
                    value == value.rounded(),
                    "\(name) lands on a whole point at \(size.rawValue) — got \(value)")
            }
        }
    }

    /// Weakly, not strictly: a 2pt gap rounds to 2 at 1.1, which is the only way to draw it.
    static func sizesGrow() {
        let ordered = [InterfaceSize.standard, .large, .larger]
        for (smaller, larger) in zip(ordered, ordered.dropFirst()) {
            let a = lengths(smaller.metrics)
            let b = lengths(larger.metrics)
            for (index, entry) in a.enumerated() {
                expect(
                    b[index].1 >= entry.1,
                    "\(entry.0) never shrinks from \(smaller.rawValue) to \(larger.rawValue)")
            }
            expect(
                larger.metrics.size.panelWidth > smaller.metrics.size.panelWidth,
                "the panel is wider at \(larger.rawValue)")
            expect(smaller.scale < larger.scale, "\(larger.rawValue) scales further")
        }
    }

    /// A derived token composes scaled parts; scaling the result would disagree by a point.
    static func derivationsHold() {
        for size in InterfaceSize.allCases {
            let m = size.metrics
            expect(
                m.size.compactHeight, m.size.headerHeight + m.size.headerPadding * 2,
                "the compact bar is the header in symmetric slack at \(size.rawValue)")
            expect(
                m.size.menuRowHeight, m.size.menuIcon + m.spacing.md * 2,
                "a menu row is its glyph slot plus breathing room at \(size.rawValue)")

            let form = ExtensionFormMetrics(scale: size.scale)
            expect(
                form.popoverRowsMaxHeight
                    == (form.popoverVisibleRows * (form.popoverRowHeight + form.popoverRowSpacing))
                    .rounded(),
                "a form popover still caps on a whole row at \(size.rawValue)")
        }
    }

    static func theEnumIsWellFormed() {
        expect(InterfaceSize.standard.scale == 1, "the default size changes nothing")
        expect(InterfaceSize(rawValue: "huge") == nil, "an unknown raw value is rejected")
        expect(
            InterfaceSize.allCases.count == Set(InterfaceSize.allCases.map(\.title)).count,
            "every size has its own title")
    }

    /// Every scalable length, paired with its name, so one loop covers rounding and growth.
    static func lengths(_ m: InterfaceMetrics) -> [(String, CGFloat)] {
        [
            ("spacing.xxs", m.spacing.xxs), ("spacing.xs", m.spacing.xs),
            ("spacing.sm", m.spacing.sm), ("spacing.md", m.spacing.md),
            ("spacing.lg", m.spacing.lg), ("spacing.xl", m.spacing.xl),
            ("spacing.xxl", m.spacing.xxl), ("spacing.xxxl", m.spacing.xxxl),
            ("spacing.sectionHeaderBottom", m.spacing.sectionHeaderBottom),
            ("spacing.sectionSpacing", m.spacing.sectionSpacing),
            ("spacing.chatTranscriptBottom", m.spacing.chatTranscriptBottom),
            ("spacing.chatFollowTailSlack", m.spacing.chatFollowTailSlack),
            ("radius.panel", m.radius.panel), ("radius.row", m.radius.row),
            ("radius.menu", m.radius.menu), ("radius.menuRow", m.radius.menuRow),
            ("radius.barControl", m.radius.barControl), ("radius.menuPanel", m.radius.menuPanel),
            ("radius.dialog", m.radius.dialog), ("radius.thumbnail", m.radius.thumbnail),
            ("radius.glyph", m.radius.glyph), ("radius.attachmentChip", m.radius.attachmentChip),
            ("radius.card", m.radius.card), ("radius.keyCap", m.radius.keyCap),
            ("size.panelWidth", m.size.panelWidth), ("size.panelHeight", m.size.panelHeight),
            ("size.headerHeight", m.size.headerHeight),
            ("size.headerIconSlot", m.size.headerIconSlot),
            ("size.headerPadding", m.size.headerPadding),
            ("size.compactHeight", m.size.compactHeight),
            ("size.bottomBarHeight", m.size.bottomBarHeight),
            ("size.barButtonHeight", m.size.barButtonHeight), ("size.rowIcon", m.size.rowIcon),
            ("size.keyCap", m.size.keyCap), ("size.compactKeyCap", m.size.compactKeyCap),
            ("size.heroKeyCap", m.size.heroKeyCap), ("size.menuButton", m.size.menuButton),
            ("size.checkbox", m.size.checkbox), ("size.menuWidth", m.size.menuWidth),
            ("size.clipboardFilterMenuWidth", m.size.clipboardFilterMenuWidth),
            ("size.menuIcon", m.size.menuIcon), ("size.menuBrandIcon", m.size.menuBrandIcon),
            ("size.barBrandIcon", m.size.barBrandIcon),
            ("size.menuSectionHeader", m.size.menuSectionHeader),
            ("size.menuRowHeight", m.size.menuRowHeight),
            ("size.menuRowsMaxHeight", m.size.menuRowsMaxHeight),
            ("size.clipboardListWidth", m.size.clipboardListWidth),
            ("size.clipboardMediaHeight", m.size.clipboardMediaHeight),
            ("size.emojiCell", m.size.emojiCell), ("size.formLabelWidth", m.size.formLabelWidth),
            ("size.argumentPromptWidth", m.size.argumentPromptWidth),
            ("size.markdownListMarker", m.size.markdownListMarker),
            ("size.markdownQuoteBar", m.size.markdownQuoteBar),
            ("size.chatMessageAction", m.size.chatMessageAction),
            ("size.chatImageThumb", m.size.chatImageThumb),
            ("size.chatAttachmentGlyph", m.size.chatAttachmentGlyph),
            ("size.chatAttachmentThumb", m.size.chatAttachmentThumb),
            ("size.chatAttachmentRemove", m.size.chatAttachmentRemove),
            ("size.chatAttachmentInset", m.size.chatAttachmentInset),
            ("size.quickActionPanel", m.size.quickActionPanel),
            ("size.quickActionHeaderIcon", m.size.quickActionHeaderIcon),
            ("size.quickActionScrollFade", m.size.quickActionScrollFade),
            ("size.quickActionPanelBody", m.size.quickActionPanelBody),
            ("size.quickActionPanelMinBody", m.size.quickActionPanelMinBody),
            ("size.dialogWidth", m.size.dialogWidth), ("size.dialogIcon", m.size.dialogIcon),
            ("size.hudMaxWidth", m.size.hudMaxWidth), ("size.hudWidth", m.size.hudWidth),
            ("size.hudHeight", m.size.hudHeight),
            ("size.volumeTrackHeight", m.size.volumeTrackHeight),
            ("size.volumeKnob", m.size.volumeKnob), ("size.volumeReadout", m.size.volumeReadout)
        ]
    }
}
