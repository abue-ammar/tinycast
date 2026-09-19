import SwiftUI

/// `Theme`'s palette geometry at the user's Interface Size and font; `.standard` is `Theme`.
struct InterfaceMetrics: Equatable, Sendable {
    static let standard = InterfaceMetrics(scale: 1)

    let scale: CGFloat
    /// `nil` is the system face; a family here replaces it wherever text is drawn, never a symbol.
    let fontFamily: String?

    init(scale: CGFloat, fontFamily: String? = nil) {
        self.scale = scale
        self.fontFamily = fontFamily
    }

    var spacing: Spacing { Spacing(scale: scale) }
    var radius: Radius { Radius(scale: scale) }
    var size: Size { Size(scale: scale) }
    var typography: Typography { Typography(scale: scale, fontFamily: fontFamily) }

    /// For a tuned length a surface owns itself, where `Theme` states no token for it.
    func scaled(_ value: CGFloat) -> CGFloat { scaledPoints(value, scale) }

    struct Spacing: Equatable, Sendable {
        let scale: CGFloat

        var xxs: CGFloat { scaledPoints(Theme.Spacing.xxs, scale) }
        var xs: CGFloat { scaledPoints(Theme.Spacing.xs, scale) }
        var sm: CGFloat { scaledPoints(Theme.Spacing.sm, scale) }
        var md: CGFloat { scaledPoints(Theme.Spacing.md, scale) }
        var lg: CGFloat { scaledPoints(Theme.Spacing.lg, scale) }
        var xl: CGFloat { scaledPoints(Theme.Spacing.xl, scale) }
        var dialogInset: CGFloat { scaledPoints(Theme.Spacing.dialogInset, scale) }
        var xxl: CGFloat { scaledPoints(Theme.Spacing.xxl, scale) }
        var xxxl: CGFloat { scaledPoints(Theme.Spacing.xxxl, scale) }
        var sectionHeaderBottom: CGFloat { scaledPoints(Theme.Spacing.sectionHeaderBottom, scale) }
        var sectionSpacing: CGFloat { scaledPoints(Theme.Spacing.sectionSpacing, scale) }
        var emojiSectionSpacing: CGFloat { scaledPoints(Theme.Spacing.emojiSectionSpacing, scale) }
        var chatTranscriptBottom: CGFloat { scaledPoints(Theme.Spacing.chatTranscriptBottom, scale) }
        var chatFollowTailSlack: CGFloat { scaledPoints(Theme.Spacing.chatFollowTailSlack, scale) }
    }

    struct Radius: Equatable, Sendable {
        let scale: CGFloat

        var panel: CGFloat { scaledPoints(Theme.Radius.panel, scale) }
        var row: CGFloat { scaledPoints(Theme.Radius.row, scale) }
        var emojiCell: CGFloat { scaledPoints(Theme.Radius.emojiCell, scale) }
        var menu: CGFloat { scaledPoints(Theme.Radius.menu, scale) }
        var menuRow: CGFloat { scaledPoints(Theme.Radius.menuRow, scale) }
        var barControl: CGFloat { scaledPoints(Theme.Radius.barControl, scale) }
        var menuPanel: CGFloat { scaledPoints(Theme.Radius.menuPanel, scale) }
        var dialogSymbol: CGFloat { scaledPoints(Theme.Radius.dialogSymbol, scale) }
        var dialog: CGFloat { scaledPoints(Theme.Radius.dialog, scale) }
        var thumbnail: CGFloat { scaledPoints(Theme.Radius.thumbnail, scale) }
        var glyph: CGFloat { scaledPoints(Theme.Radius.glyph, scale) }
        var attachmentChip: CGFloat { scaledPoints(Theme.Radius.attachmentChip, scale) }
        var card: CGFloat { scaledPoints(Theme.Radius.card, scale) }
        var keyCap: CGFloat { scaledPoints(Theme.Radius.keyCap, scale) }
        var tooltip: CGFloat { scaledPoints(Theme.Radius.tooltip, scale) }
    }

    struct Size: Equatable, Sendable {
        let scale: CGFloat

        var panelWidth: CGFloat { scaledPoints(Theme.Size.panelWidth, scale) }
        var panelHeight: CGFloat { scaledPoints(Theme.Size.panelHeight, scale) }
        var headerHeight: CGFloat { scaledPoints(Theme.Size.headerHeight, scale) }
        var headerIconSlot: CGFloat { scaledPoints(Theme.Size.headerIconSlot, scale) }
        var headerPadding: CGFloat { scaledPoints(Theme.Size.headerPadding, scale) }
        /// Derived, not scaled: the compact bar must stay exactly the header in symmetric slack.
        var compactHeight: CGFloat { headerHeight + headerPadding * 2 }
        var bottomBarHeight: CGFloat { scaledPoints(Theme.Size.bottomBarHeight, scale) }
        var barButtonHeight: CGFloat { scaledPoints(Theme.Size.barButtonHeight, scale) }
        var rowIcon: CGFloat { scaledPoints(Theme.Size.rowIcon, scale) }
        var colorDot: CGFloat { scaledPoints(Theme.Size.colorDot, scale) }
        var calendarBarWidth: CGFloat { scaledPoints(Theme.Size.calendarBarWidth, scale) }
        var calendarBarHeight: CGFloat { scaledPoints(Theme.Size.calendarBarHeight, scale) }
        var keyCap: CGFloat { scaledPoints(Theme.Size.keyCap, scale) }
        var compactKeyCap: CGFloat { scaledPoints(Theme.Size.compactKeyCap, scale) }
        var heroKeyCap: CGFloat { scaledPoints(Theme.Size.heroKeyCap, scale) }
        var menuButton: CGFloat { scaledPoints(Theme.Size.menuButton, scale) }
        var checkbox: CGFloat { scaledPoints(Theme.Size.checkbox, scale) }

        var menuWidth: CGFloat { scaledPoints(Theme.Size.menuWidth, scale) }
        var actionMenuWidth: CGFloat { scaledPoints(Theme.Size.actionMenuWidth, scale) }
        var clipboardFilterMenuWidth: CGFloat { scaledPoints(Theme.Size.clipboardFilterMenuWidth, scale) }
        var fileSearchFilterMenuWidth: CGFloat { scaledPoints(Theme.Size.fileSearchFilterMenuWidth, scale) }
        var emojiCategoryMenuWidth: CGFloat { scaledPoints(Theme.Size.emojiCategoryMenuWidth, scale) }
        var menuIcon: CGFloat { scaledPoints(Theme.Size.menuIcon, scale) }
        var menuBrandIcon: CGFloat { scaledPoints(Theme.Size.menuBrandIcon, scale) }
        var barBrandIcon: CGFloat { scaledPoints(Theme.Size.barBrandIcon, scale) }
        var menuRowSpacing: CGFloat { scaledPoints(Theme.Size.menuRowSpacing, scale) }
        var menuSectionHeader: CGFloat { scaledPoints(Theme.Size.menuSectionHeader, scale) }
        /// Derived like `Theme`'s, so the row cap still counts whole rows at every size.
        var menuRowHeight: CGFloat { menuIcon + Spacing(scale: scale).md * 2 }
        var menuRowsMaxHeight: CGFloat {
            (Theme.Size.menuVisibleRows * (menuRowHeight + menuRowSpacing)).rounded()
        }
        var clipboardListWidth: CGFloat { scaledPoints(Theme.Size.clipboardListWidth, scale) }
        var clipboardMediaHeight: CGFloat { scaledPoints(Theme.Size.clipboardMediaHeight, scale) }
        var clipboardPreviewPixel: CGFloat { scaledPoints(Theme.Size.clipboardPreviewPixel, scale) }
        var emojiGridInset: CGFloat { scaledPoints(Theme.Size.emojiGridInset, scale) }
        var emojiCell: CGFloat { scaledPoints(Theme.Size.emojiCell, scale) }

        var markdownListMarker: CGFloat { scaledPoints(Theme.Size.markdownListMarker, scale) }
        var markdownQuoteBar: CGFloat { scaledPoints(Theme.Size.markdownQuoteBar, scale) }
        var chatMessageAction: CGFloat { scaledPoints(Theme.Size.chatMessageAction, scale) }
        var chatImageThumb: CGFloat { scaledPoints(Theme.Size.chatImageThumb, scale) }
        var chatAttachmentGlyph: CGFloat { scaledPoints(Theme.Size.chatAttachmentGlyph, scale) }
        var chatAttachmentThumb: CGFloat { scaledPoints(Theme.Size.chatAttachmentThumb, scale) }
        var chatAttachmentRemove: CGFloat { scaledPoints(Theme.Size.chatAttachmentRemove, scale) }
        var chatAttachmentInset: CGFloat { scaledPoints(Theme.Size.chatAttachmentInset, scale) }

        var quickActionPanel: CGFloat { scaledPoints(Theme.Size.quickActionPanel, scale) }
        var quickActionHeaderIcon: CGFloat { scaledPoints(Theme.Size.quickActionHeaderIcon, scale) }
        var quickActionScrollFade: CGFloat { scaledPoints(Theme.Size.quickActionScrollFade, scale) }
        var quickActionPanelBody: CGFloat { scaledPoints(Theme.Size.quickActionPanelBody, scale) }
        var quickActionPanelMinBody: CGFloat { scaledPoints(Theme.Size.quickActionPanelMinBody, scale) }

        var dialogCompactWidth: CGFloat { scaledPoints(Theme.Size.dialogCompactWidth, scale) }
        var dialogWidth: CGFloat { scaledPoints(Theme.Size.dialogWidth, scale) }
        var dialogButtonHeight: CGFloat {
            menuButton
                - scaledPoints(Theme.Size.menuButton - Theme.Size.dialogButtonHeight, scale)
        }
        var dialogSymbol: CGFloat { scaledPoints(Theme.Size.dialogSymbol, scale) }
        var dialogSymbolContainer: CGFloat {
            scaledPoints(Theme.Size.dialogSymbolContainer, scale)
        }
        var dialogIcon: CGFloat { scaledPoints(Theme.Size.dialogIcon, scale) }
        var hudMaxWidth: CGFloat { scaledPoints(Theme.Size.hudMaxWidth, scale) }
        var hudWidth: CGFloat { scaledPoints(Theme.Size.hudWidth, scale) }
        var hudHeight: CGFloat { scaledPoints(Theme.Size.hudHeight, scale) }
        var volumeTrackHeight: CGFloat { scaledPoints(Theme.Size.volumeTrackHeight, scale) }
        var volumeReadout: CGFloat { scaledPoints(Theme.Size.volumeReadout, scale) }
    }

    /// `NSFont` is the only public source of a text style's size and face.
    struct Typography: Sendable {
        let scale: CGFloat
        let fontFamily: String?

        /// Both knobs at their default, where every token is `Theme` verbatim.
        private var isStandard: Bool { scale == 1 && fontFamily == nil }

        var searchFieldSize: CGFloat { scaledPoints(Theme.Typography.searchFieldSize, scale) }
        var searchField: Font {
            isStandard ? Theme.Typography.searchField : Font(sizedFont(searchFieldSize, .regular))
        }
        /// Isolated because `Theme`'s twin is, not because resolving a font needs main.
        @MainActor var searchFieldNSFont: NSFont {
            isStandard ? Theme.Typography.searchFieldNSFont : sizedFont(searchFieldSize, .regular)
        }
        /// Sizes an SF Symbol, not text: a family swap would drop its weight and scale mapping.
        var headerIcon: Font {
            scale == 1
                ? Theme.Typography.headerIcon
                : .system(size: scaledPoints(18, scale), weight: .medium)
        }

        var rowTitle: Font { font(Theme.Typography.rowTitle, .body) }
        var rowTrailing: Font { font(Theme.Typography.rowTrailing, .callout) }
        var sectionHeader: Font { font(Theme.Typography.sectionHeader, .subheadline, .medium) }
        var panelTitle: Font { font(Theme.Typography.panelTitle, .headline) }
        var calcResult: Font { font(Theme.Typography.calcResult, .title1) }
        var keyCap: Font { font(Theme.Typography.keyCap, .caption1) }
        var compactKeyCap: Font { font(Theme.Typography.compactKeyCap, .caption2) }
        var heroKeyCap: Font { font(Theme.Typography.heroKeyCap, .body) }
        var markdownHeading1: Font { font(Theme.Typography.markdownHeading1, .title2, .semibold) }
        var markdownHeading2: Font { font(Theme.Typography.markdownHeading2, .title3, .semibold) }
        var markdownHeading3: Font { font(Theme.Typography.markdownHeading3, .headline) }
        var code: Font { monospaced(Theme.Typography.code, .callout) }
        var inlineCode: Font {
            guard !isStandard else { return Theme.Typography.inlineCode }
            let resolved = font(Theme.Typography.inlineCode, .body)
            return fontFamily == nil ? resolved.monospaced() : resolved
        }
        var bar: Font { font(Theme.Typography.bar, .callout, .medium) }
        var chip: Font { font(Theme.Typography.chip, .callout) }
        @MainActor var chipNSFont: NSFont {
            isStandard ? Theme.Typography.chipNSFont : nsFont(.callout)
        }
        /// A trailing chevron, so it stays on the system face alongside the other symbol tokens.
        var disclosure: Font { systemFont(Theme.Typography.disclosure, .caption1, .semibold) }
        var menuRow: Font { font(Theme.Typography.menuRow, .body) }
        var menuShortcut: Font { font(Theme.Typography.menuShortcut, .callout) }
        var menuIcon: Font { systemFont(Theme.Typography.menuIcon, .body) }
        var cardTitle: Font { font(Theme.Typography.cardTitle, .title3, .semibold) }
        var previewCode: Font { monospaced(Theme.Typography.previewCode, .subheadline) }
        /// An oversized SF Symbol, so it stays on the system face like the other symbol tokens.
        var placeholderGlyph: Font { systemFont(Theme.Typography.placeholderGlyph, .largeTitle) }
        /// Notes sits a style above the app and never scales, so only the family reaches it.
        var noteTitle: Font {
            Typography(scale: 1, fontFamily: fontFamily).font(Theme.Typography.noteTitle, .headline)
        }

        /// A chosen family is the one font everywhere, so it outranks the monospaced design.
        private func monospaced(_ base: Font, _ style: NSFont.TextStyle) -> Font {
            guard fontFamily == nil else { return font(base, style) }
            return scale == 1 ? base : .system(size: nsFont(style).pointSize, design: .monospaced)
        }

        /// Composed like `Theme`'s own: the style carries the face, an explicit weight overrides it.
        private func font(
            _ base: Font, _ style: NSFont.TextStyle, _ weight: Font.Weight? = nil
        )
            -> Font
        {
            guard !isStandard else { return base }
            let resolved = Font(nsFont(style))
            return weight.map(resolved.weight) ?? resolved
        }

        /// The family-blind twin, for the tokens that size a symbol rather than set type.
        private func systemFont(
            _ base: Font, _ style: NSFont.TextStyle, _ weight: Font.Weight? = nil
        )
            -> Font
        {
            guard scale != 1 else { return base }
            let resolved = Font(systemNSFont(style))
            return weight.map(resolved.weight) ?? resolved
        }

        /// The style resolved on the chosen family; a copied descriptor would pin the system face.
        func nsFont(_ style: NSFont.TextStyle) -> NSFont {
            let system = systemNSFont(style)
            return familyFont(matching: system, size: system.pointSize) ?? system
        }

        /// Its own descriptor, so `.headline` stays Bold and `.caption2` Medium rather than lightening.
        private func systemNSFont(_ style: NSFont.TextStyle) -> NSFont {
            let base = NSFont.preferredFont(forTextStyle: style)
            guard scale != 1 else { return base }
            return NSFont(descriptor: base.fontDescriptor, size: scaledPoints(base.pointSize, scale)) ?? base
        }

        /// For the one token that states a size instead of naming a style.
        private func sizedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
            let system = NSFont.systemFont(ofSize: size, weight: weight)
            return familyFont(matching: system, size: size) ?? system
        }

        private func familyFont(matching base: NSFont, size: CGFloat) -> NSFont? {
            InterfaceMetrics.face(base, on: fontFamily, size: size)
        }
    }
}

extension InterfaceMetrics {
    /// `NSFontManager` is what carries a face across families; a family that cannot keeps the face.
    static func face(_ base: NSFont, on family: String?, size: CGFloat) -> NSFont? {
        guard let family else { return nil }
        let manager = NSFontManager.shared
        let font = manager.font(
            withFamily: family,
            traits: manager.traits(of: base),
            weight: manager.weight(of: base),
            size: size)
        guard let font, font.familyName == family else { return nil }
        return font
    }
}

/// Whole points: a fractional row pitch lands keycap edges and the dissolve mask off-pixel.
private func scaledPoints(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
    scale == 1 ? value : (value * scale).rounded()
}

extension EnvironmentValues {
    /// `.standard` by default, so a shared `DesignSystem` view outside the palette never scales.
    @Entry var metrics = InterfaceMetrics.standard
}
