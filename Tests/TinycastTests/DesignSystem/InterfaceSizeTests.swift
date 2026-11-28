import AppKit
import Testing

@testable import Tinycast

/// Against the real `Theme`, so `.standard` can never drift from what the app ships today.
struct InterfaceSizeTests {
    struct Length: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let path: KeyPath<InterfaceMetrics, CGFloat> & Sendable
        let theme: CGFloat

        init(_ name: String, _ path: KeyPath<InterfaceMetrics, CGFloat> & Sendable, _ theme: CGFloat) {
            testDescription = name
            self.path = path
            self.theme = theme
        }
    }

    /// Every scalable length, so a mistyped `Theme` reference in `InterfaceMetrics` cannot ship.
    static let lengths = [
        Length("spacing.xxs", \.spacing.xxs, Theme.Spacing.xxs),
        Length("spacing.xs", \.spacing.xs, Theme.Spacing.xs),
        Length("spacing.sm", \.spacing.sm, Theme.Spacing.sm),
        Length("spacing.md", \.spacing.md, Theme.Spacing.md),
        Length("spacing.lg", \.spacing.lg, Theme.Spacing.lg),
        Length("spacing.xl", \.spacing.xl, Theme.Spacing.xl),
        Length("spacing.dialogInset", \.spacing.dialogInset, Theme.Spacing.dialogInset),
        Length("spacing.xxl", \.spacing.xxl, Theme.Spacing.xxl),
        Length("spacing.xxxl", \.spacing.xxxl, Theme.Spacing.xxxl),
        Length(
            "spacing.sectionHeaderBottom", \.spacing.sectionHeaderBottom, Theme.Spacing.sectionHeaderBottom),
        Length("spacing.sectionSpacing", \.spacing.sectionSpacing, Theme.Spacing.sectionSpacing),
        Length(
            "spacing.emojiSectionSpacing", \.spacing.emojiSectionSpacing, Theme.Spacing.emojiSectionSpacing),
        Length(
            "spacing.chatTranscriptBottom", \.spacing.chatTranscriptBottom, Theme.Spacing.chatTranscriptBottom
        ),
        Length(
            "spacing.chatFollowTailSlack", \.spacing.chatFollowTailSlack, Theme.Spacing.chatFollowTailSlack),
        Length("spacing.chatLine", \.spacing.chatLine, Theme.Spacing.chatLine),
        Length("radius.panel", \.radius.panel, Theme.Radius.panel),
        Length("radius.row", \.radius.row, Theme.Radius.row),
        Length("radius.formField", \.radius.formField, Theme.Radius.formField),
        Length("radius.emojiCell", \.radius.emojiCell, Theme.Radius.emojiCell),
        Length("radius.menu", \.radius.menu, Theme.Radius.menu),
        Length("radius.menuRow", \.radius.menuRow, Theme.Radius.menuRow),
        Length("radius.barControl", \.radius.barControl, Theme.Radius.barControl),
        Length("radius.menuPanel", \.radius.menuPanel, Theme.Radius.menuPanel),
        Length("radius.dialogSymbol", \.radius.dialogSymbol, Theme.Radius.dialogSymbol),
        Length("radius.dialog", \.radius.dialog, Theme.Radius.dialog),
        Length("radius.thumbnail", \.radius.thumbnail, Theme.Radius.thumbnail),
        Length("radius.glyph", \.radius.glyph, Theme.Radius.glyph),
        Length("radius.attachmentChip", \.radius.attachmentChip, Theme.Radius.attachmentChip),
        Length("radius.card", \.radius.card, Theme.Radius.card),
        Length("radius.keyCap", \.radius.keyCap, Theme.Radius.keyCap),
        Length("radius.tooltip", \.radius.tooltip, Theme.Radius.tooltip),
        Length("size.panelWidth", \.size.panelWidth, Theme.Size.panelWidth),
        Length("size.panelHeight", \.size.panelHeight, Theme.Size.panelHeight),
        Length("size.headerHeight", \.size.headerHeight, Theme.Size.headerHeight),
        Length("size.headerIconSlot", \.size.headerIconSlot, Theme.Size.headerIconSlot),
        Length("size.searchFieldMinWidth", \.size.searchFieldMinWidth, Theme.Size.searchFieldMinWidth),
        Length("size.headerPadding", \.size.headerPadding, Theme.Size.headerPadding),
        Length("size.compactHeight", \.size.compactHeight, Theme.Size.compactHeight),
        Length("size.bottomBarHeight", \.size.bottomBarHeight, Theme.Size.bottomBarHeight),
        Length("size.textAreaUnit", \.size.textAreaUnit, Theme.Size.textAreaUnit),
        Length("size.barButtonHeight", \.size.barButtonHeight, Theme.Size.barButtonHeight),
        Length("size.rowIcon", \.size.rowIcon, Theme.Size.rowIcon),
        Length("size.resultRowIcon", \.size.resultRowIcon, Theme.Size.resultRowIcon),
        Length("size.colorDot", \.size.colorDot, Theme.Size.colorDot),
        Length("size.calendarBarWidth", \.size.calendarBarWidth, Theme.Size.calendarBarWidth),
        Length("size.calendarBarHeight", \.size.calendarBarHeight, Theme.Size.calendarBarHeight),
        Length("size.keyCap", \.size.keyCap, Theme.Size.keyCap),
        Length("size.compactKeyCap", \.size.compactKeyCap, Theme.Size.compactKeyCap),
        Length("size.heroKeyCap", \.size.heroKeyCap, Theme.Size.heroKeyCap),
        Length("size.menuButton", \.size.menuButton, Theme.Size.menuButton),
        Length("size.checkbox", \.size.checkbox, Theme.Size.checkbox),
        Length("size.menuWidth", \.size.menuWidth, Theme.Size.menuWidth),
        Length("size.formMenuMinimumWidth", \.size.formMenuMinimumWidth, Theme.Size.formMenuMinimumWidth),
        Length(
            "size.formMenuExtraRowsHeight", \.size.formMenuExtraRowsHeight, Theme.Size.formMenuExtraRowsHeight
        ),
        Length("size.formFieldFocusStroke", \.size.formFieldFocusStroke, Theme.Size.formFieldFocusStroke),
        Length(
            "size.clipboardFilterMenuWidth", \.size.clipboardFilterMenuWidth,
            Theme.Size.clipboardFilterMenuWidth),
        Length(
            "size.fileSearchFilterMenuWidth", \.size.fileSearchFilterMenuWidth,
            Theme.Size.fileSearchFilterMenuWidth),
        Length(
            "size.emojiCategoryMenuWidth", \.size.emojiCategoryMenuWidth, Theme.Size.emojiCategoryMenuWidth),
        Length("size.menuIcon", \.size.menuIcon, Theme.Size.menuIcon),
        Length("size.menuBrandIcon", \.size.menuBrandIcon, Theme.Size.menuBrandIcon),
        Length("size.barBrandIcon", \.size.barBrandIcon, Theme.Size.barBrandIcon),
        Length("size.menuRowSpacing", \.size.menuRowSpacing, Theme.Size.menuRowSpacing),
        Length("size.menuSectionHeader", \.size.menuSectionHeader, Theme.Size.menuSectionHeader),
        Length("size.menuRowHeight", \.size.menuRowHeight, Theme.Size.menuRowHeight),
        Length("size.menuRowsMaxHeight", \.size.menuRowsMaxHeight, Theme.Size.menuRowsMaxHeight),
        Length("size.clipboardListWidth", \.size.clipboardListWidth, Theme.Size.clipboardListWidth),
        Length("size.clipboardMediaHeight", \.size.clipboardMediaHeight, Theme.Size.clipboardMediaHeight),
        Length("size.clipboardPreviewPixel", \.size.clipboardPreviewPixel, Theme.Size.clipboardPreviewPixel),
        Length("size.emojiCell", \.size.emojiCell, Theme.Size.emojiCell),
        Length("size.emojiGridInset", \.size.emojiGridInset, Theme.Size.emojiGridInset),
        Length("size.markdownListMarker", \.size.markdownListMarker, Theme.Size.markdownListMarker),
        Length("size.markdownQuoteBar", \.size.markdownQuoteBar, Theme.Size.markdownQuoteBar),
        Length("size.chatMessageAction", \.size.chatMessageAction, Theme.Size.chatMessageAction),
        Length("size.chatImageThumb", \.size.chatImageThumb, Theme.Size.chatImageThumb),
        Length("size.chatAttachmentGlyph", \.size.chatAttachmentGlyph, Theme.Size.chatAttachmentGlyph),
        Length("size.chatAttachmentThumb", \.size.chatAttachmentThumb, Theme.Size.chatAttachmentThumb),
        Length("size.chatAttachmentInset", \.size.chatAttachmentInset, Theme.Size.chatAttachmentInset),
        Length("size.quickActionPanel", \.size.quickActionPanel, Theme.Size.quickActionPanel),
        Length("size.quickActionHeaderIcon", \.size.quickActionHeaderIcon, Theme.Size.quickActionHeaderIcon),
        Length("size.quickActionScrollFade", \.size.quickActionScrollFade, Theme.Size.quickActionScrollFade),
        Length("size.quickActionPanelBody", \.size.quickActionPanelBody, Theme.Size.quickActionPanelBody),
        Length(
            "size.quickActionPanelMinBody", \.size.quickActionPanelMinBody, Theme.Size.quickActionPanelMinBody
        ),
        Length("size.dialogCompactWidth", \.size.dialogCompactWidth, Theme.Size.dialogCompactWidth),
        Length("size.dialogWidth", \.size.dialogWidth, Theme.Size.dialogWidth),
        Length("size.dialogButtonHeight", \.size.dialogButtonHeight, Theme.Size.dialogButtonHeight),
        Length("size.dialogSymbol", \.size.dialogSymbol, Theme.Size.dialogSymbol),
        Length("size.dialogSymbolContainer", \.size.dialogSymbolContainer, Theme.Size.dialogSymbolContainer),
        Length("size.dialogIcon", \.size.dialogIcon, Theme.Size.dialogIcon),
        Length("size.hudMaxWidth", \.size.hudMaxWidth, Theme.Size.hudMaxWidth),
        Length("size.hudWidth", \.size.hudWidth, Theme.Size.hudWidth),
        Length("size.hudHeight", \.size.hudHeight, Theme.Size.hudHeight),
        Length("size.volumeTrackHeight", \.size.volumeTrackHeight, Theme.Size.volumeTrackHeight),
        Length("size.volumeReadout", \.size.volumeReadout, Theme.Size.volumeReadout)
    ]

    static let steps: [(smaller: InterfaceSize, larger: InterfaceSize)] = [
        (.standard, .large), (.large, .larger)
    ]

    /// `.headline` is Bold and `.caption2` Medium: a size-and-weight rebuild would lighten both.
    static let textStyles: [NSFont.TextStyle] = [.body, .callout, .subheadline, .headline, .caption2]

    // MARK: Identity at the default size

    @Test func theDefaultScaleIsOne() {
        #expect(abs(InterfaceMetrics.standard.scale - 1) < 0.001)
        #expect(InterfaceSize.standard.scale == 1)
    }

    @Test(arguments: lengths)
    func theDefaultLengthIsThemeVerbatim(_ length: Length) {
        #expect(abs(InterfaceMetrics.standard[keyPath: length.path] - length.theme) < 0.001)
    }

    @Test @MainActor func theDefaultTypographyIsThemeVerbatim() {
        let typography = InterfaceMetrics.standard.typography
        #expect(abs(typography.searchFieldSize - Theme.Typography.searchFieldSize) < 0.001)
        #expect(typography.searchFieldNSFont == Theme.Typography.searchFieldNSFont)
        #expect(typography.chipNSFont == Theme.Typography.chipNSFont)
    }

    // MARK: Extension forms

    /// Extensions duplicate the mechanism rather than importing it, so it is checked here too.
    @Test func theExtensionFormBaseIsUnscaled() {
        #expect(abs(ExtensionFormMetrics.base.scale - 1) < 0.001)
    }

    @Test(arguments: InterfaceSize.allCases)
    func extensionControlsMatchTheNativeForm(_ size: InterfaceSize) {
        let metrics = size.metrics
        let form = ExtensionFormMetrics(scale: metrics.scale)
        let labelWidth = (metrics.size.panelWidth * 0.16).rounded()
        let nativeWidth =
            metrics.size.panelWidth - labelWidth * 2 - metrics.spacing.xxxl * 4 - metrics.spacing.xxl * 2
        #expect(abs(form.controlWidth - nativeWidth) < 0.001)
        #expect(abs(form.controlHeight - metrics.size.dialogButtonHeight) < 0.001)
        #expect(abs(form.textInset - metrics.spacing.xl) < 0.001)
        #expect(abs(form.verticalInset - metrics.spacing.md) < 0.001)
    }

    @Test(arguments: InterfaceSize.allCases)
    func aFormPopoverCapsOnAWholeRow(_ size: InterfaceSize) {
        let form = ExtensionFormMetrics(scale: size.scale)
        let rows = form.popoverVisibleRows * (form.popoverRowHeight + form.popoverRowSpacing)
        #expect(form.popoverRowsMaxHeight == rows.rounded())
    }

    // MARK: Fonts

    @Test(arguments: InterfaceSize.allCases, textStyles)
    func aScaledTextStyleKeepsItsFace(_ size: InterfaceSize, _ style: NSFont.TextStyle) throws {
        let base = NSFont.preferredFont(forTextStyle: style)
        let scaled = try #require(
            NSFont(descriptor: base.fontDescriptor, size: (base.pointSize * size.scale).rounded()))
        #expect(scaled.familyName == base.familyName)
        #expect(scaled.fontName == base.fontName)
    }

    @Test(arguments: InterfaceSize.allCases)
    func theSearchFieldsStatedSizeScales(_ size: InterfaceSize) {
        #expect(
            size.metrics.typography.searchFieldSize
                == (Theme.Typography.searchFieldSize * size.scale).rounded())
    }

    // MARK: Rounding and growth

    @Test(arguments: InterfaceSize.allCases, lengths)
    func everyLengthLandsOnAWholePoint(_ size: InterfaceSize, _ length: Length) {
        let value = size.metrics[keyPath: length.path]
        #expect(value == value.rounded())
    }

    /// Weakly, not strictly: a 2pt gap rounds to 2 at 1.1, which is the only way to draw it.
    @Test(arguments: steps, lengths)
    func noLengthShrinksAtALargerSize(
        _ step: (smaller: InterfaceSize, larger: InterfaceSize), _ length: Length
    ) {
        #expect(step.larger.metrics[keyPath: length.path] >= step.smaller.metrics[keyPath: length.path])
    }

    @Test(arguments: steps)
    func aLargerSizeWidensThePanel(_ step: (smaller: InterfaceSize, larger: InterfaceSize)) {
        #expect(step.larger.metrics.size.panelWidth > step.smaller.metrics.size.panelWidth)
        #expect(step.smaller.scale < step.larger.scale)
    }

    /// A derived token composes scaled parts; scaling the result would disagree by a point.
    @Test(arguments: InterfaceSize.allCases)
    func derivedTokensComposeTheirScaledParts(_ size: InterfaceSize) {
        let m = size.metrics
        let dialogButtonReduction = ((Theme.Size.menuButton - Theme.Size.dialogButtonHeight) * size.scale)
            .rounded()
        #expect(abs(m.size.compactHeight - (m.size.headerHeight + m.size.headerPadding * 2)) < 0.001)
        #expect(abs(m.size.menuRowHeight - (m.size.menuIcon + m.spacing.md * 2)) < 0.001)
        #expect(abs(m.size.dialogButtonHeight - (m.size.menuButton - dialogButtonReduction)) < 0.001)
    }

    // MARK: The enum

    @Test func anUnknownStoredSizeIsRejected() {
        #expect(InterfaceSize(rawValue: "huge") == nil)
    }

    @Test func everySizeHasItsOwnTitle() {
        #expect(Set(InterfaceSize.allCases.map(\.title)).count == InterfaceSize.allCases.count)
    }
}
