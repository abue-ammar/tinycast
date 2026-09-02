import SwiftUI

/// Central design tokens; every dark colour is the literal the forced-dark build shipped.
enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 20
        /// Calculator answer card's roomier vertical breathing room.
        static let xxxl: CGFloat = 28
        /// Gap under a category header, shared by every palette list's `SectionHeader`.
        static let sectionHeaderBottom: CGFloat = 4
        /// Clearance under the last message, so its actions row belongs to it, not to the footer.
        static let chatTranscriptBottom: CGFloat = 28
        /// A stream grows the transcript as the reader descends, so an exact-bottom test runs away.
        static let chatFollowTailSlack: CGFloat = 44
        /// Space above every header but the first, reading as the previous section's close.
        static let sectionSpacing: CGFloat = 12
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        static let menu: CGFloat = 6
        /// Hover highlight behind a popover menu row.
        static let menuRow: CGFloat = 10
        /// A header pop-up button; the footer's action pills stay capsules.
        static let barControl: CGFloat = 8
        static let menuPanel: CGFloat = 16
        /// The dialog and HUD surface, so a dialog reads as a sibling of the palette.
        static let dialog: CGFloat = 20
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 10
        static let keyCap: CGFloat = 6
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 4
    }

    enum Blur {
        /// Unreadable at full size without smearing the row; the scramble is what hides it.
        static let redaction: CGFloat = 3
    }

    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 475
        /// Opening size on a first run and the floor: below it the title bar's own parts collide.
        static let noteWindow = CGSize(width: 440, height: 180)
        static let noteEditorInset: CGFloat = 16
        /// Shorter than the horizontal inset, so the first line sits close under the title bar.
        static let noteEditorTopInset: CGFloat = 6
        static let noteSearchHeight: CGFloat = 34
        /// The switcher popover, sized independently of a note window that can be 180pt tall.
        static let noteSwitcher = CGSize(width: 300, height: 240)
        static let noteSwitcherEmptyHeight: CGFloat = 96
        static let noteSwitcherDrop: CGFloat = 56
        static let noteFooterHeight: CGFloat = 28
        /// Holds the launcher's 36-point action capsule with the same margin its own bar gives it.
        static let noteTitlebar: CGFloat = 52
        /// Symmetric, so the title stays centred on the window while clearing lights and capsule.
        static let noteTitleInset: CGFloat = 120
        /// Nine points crowds the palette's 26-point corner, so Notes seats its lights further in.
        static let noteTrafficLightInset: CGFloat = 20
        /// Fraction of visible height above the palette's top edge; it grows downward.
        static let paletteTopMarginFraction: CGFloat = 0.18
        static let headerHeight: CGFloat = 44
        /// Fixed slot for the header glyph, so the field starts at one x in every mode.
        static let headerIconSlot: CGFloat = 22
        /// Room above the search row, constant so typing never shifts the bar.
        static let headerPadding: CGFloat = 10
        /// Collapsed compact bar: the search row centered in symmetric `headerPadding` slack.
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        /// How near the default placement a drag has to land before it snaps home.
        static let paletteSnapDistance: CGFloat = 24
        /// A restored position needs this much bar on a display to still be grabbable.
        static let paletteMinimumVisible: CGFloat = 44
        /// Dash and gap of the drop guides, equal so the line reads evenly.
        static let dropGuideDash: CGFloat = 4
        static let dropGuideWidth: CGFloat = 2
        static let bottomBarHeight: CGFloat = 52
        /// A `BarButton`'s hover capsule, shared by the footer group and the header's filter.
        static let barButtonHeight: CGFloat = 28
        static let rowIcon: CGFloat = 24
        static let keyCap: CGFloat = 18
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 16
        /// Fixed so the recorder can't resize as its binding changes.
        static let shortcutRecorder: CGFloat = 120
        /// One text line in the recorder callout.
        static let shortcutPopoverLine: CGFloat = 14
        /// Summed from the laid-out bands; the width is pinned by `callout-test`.
        static let shortcutPopover = CGSize(
            width: 132,
            height: Spacing.sm * 2 + heroKeyCap + Spacing.sm + shortcutPopoverLine + Spacing.sm
                + compactKeyCap + calloutCaretHeight)
        /// The callout's pointer: a triangle with a rounded tip.
        static let calloutCaretWidth: CGFloat = 15
        static let calloutCaretHeight: CGFloat = 7
        static let calloutCaretTip: CGFloat = 2.5
        /// Keycaps: `compact` hints, `keyCap` is standard, `hero` where the cap is content.
        static let compactKeyCap: CGFloat = 15
        static let heroKeyCap: CGFloat = 22
        static let menuButton: CGFloat = 36
        static let noteGlyph: CGFloat = 16
        static let noteEmptyGlyph: CGFloat = 28
        /// Hit target for a chat message footer glyph; its caption symbol floats inside it.
        static let chatMessageAction: CGFloat = 16
        /// A one-pixel markdown rule and table header separator.
        static let hairline: CGFloat = 1
        static let markdownListMarker: CGFloat = 20
        static let markdownQuoteBar: CGFloat = 2
        /// The uninstall list's leading checkbox / lock glyph.
        static let checkbox: CGFloat = 16
        static let clipboardListWidth: CGFloat = 290
        static let emojiCell: CGFloat = 56
        static let menuWidth: CGFloat = 276
        /// The clipboard type filter's menu; `menuWidth` is far too wide for five short rows.
        static let clipboardFilterMenuWidth: CGFloat = 200
        /// Stated, not padded: the cap below counts rows, so a capped menu would land mid-row.
        static let menuRowHeight: CGFloat = menuIcon + Spacing.md * 2
        static let menuRowSpacing: CGFloat = 1
        /// Six rows and half of the seventh, so a capped menu reads as scrollable, not clipped.
        static let menuVisibleRows: CGFloat = 6.5
        /// Rounded: a half-row of an odd pitch lands the glass edge on a half pixel.
        static var menuRowsMaxHeight: CGFloat {
            (menuVisibleRows * (menuRowHeight + menuRowSpacing)).rounded()
        }
        /// A menu row's glyph slot, sized so symbol and app-icon rows read the same.
        static let menuIcon: CGFloat = 20
        /// A brand mark inside the menu icon slot, sized to the optical weight of a symbol.
        static let menuBrandIcon: CGFloat = 14
        /// The same mark in a header bar button, matched to the callout symbol beside it.
        static let barBrandIcon: CGFloat = 12
        /// A sent image in the transcript; a staged one is a glyph in a pill by the search text.
        static let chatImageThumb: CGFloat = 96
        static let chatAttachmentGlyph: CGFloat = 16
        /// Opening size and the resize floor; tall enough that the sidebar's rows never scroll.
        static let settingsWindow = CGSize(width: 860, height: 700)
        /// Settings sidebar: a fixed column, wide enough for "Window Management".
        static let settingsSidebar: CGFloat = 215
        /// The narrowest the pane column may get before a grouped row's control starts colliding.
        static let settingsDetailMinimum: CGFloat = 420
        static let settingsRowIcon: CGFloat = 20
        /// The sidebar's search field; matches a grouped `Form` row's control height.
        static let settingsSearchField: CGFloat = 28
        /// Settings editor modals (Custom Commands, Snippets): fixed width, intrinsic height.
        static let editorSheetWidth: CGFloat = 480
        /// Label column of an extension's `Form`, so every field's input starts on one line.
        static let formLabelWidth: CGFloat = 110
        /// The multi-line box inside those modals; it scrolls rather than grows the sheet.
        static let editorTextHeight: CGFloat = 120
        /// The argument prompt's field column, kept under the alert's natural width.
        static let argumentPromptWidth: CGFloat = 220
        /// The confirmation HUD's width ceiling, and its distance above the screen bottom.
        static let hudMaxWidth: CGFloat = 420
        static let hudEdgeOffset: CGFloat = 48
        /// Tinycast's own dialog: fixed width, height measured from the SwiftUI content.
        static let dialogWidth: CGFloat = 420
        /// A dialog's leading glyph, larger than a row icon: it carries the subject.
        static let dialogIcon: CGFloat = 32
        /// 16:9 at the dialog's own width, so the two surfaces read as siblings.
        static let cameraPreview = CGSize(width: 420, height: 236)
        /// Wider than a dialog: a Quick Action's result is prose to read, not a sentence to answer.
        static let quickActionPanel: CGFloat = 520
        /// Matched to the title's cap height; a row-sized glyph beside it reads as an error.
        static let quickActionHeaderIcon: CGFloat = 14
        /// The dissolve ramp below each bar's clear zone, measured against text behind the title.
        static let quickActionScrollFade: CGFloat = 40
        /// Past this the result scrolls, so a long summary cannot grow the panel off the screen.
        static let quickActionPanelBody: CGFloat = 320
        /// Keeps a two-word grammar fix from collapsing the panel to a slot.
        static let quickActionPanelMinBody: CGFloat = 44
        /// Transient volume HUD shown after any volume or mute command.
        static let hudWidth: CGFloat = 200
        static let hudHeight: CGFloat = 100
        /// Volume slider geometry, shared by the Set Volume dialog and the HUD's read-only bar.
        static let volumeTrackHeight: CGFloat = 6
        static let volumeKnob: CGFloat = 16
        /// Fixed slot for the level readout, sized to the widest string it ever holds.
        static let volumeReadout: CGFloat = 38
    }

    enum Duration {
        /// How long each HUD stays up; a sentence needs longer than a level does.
        static let messageHUD: TimeInterval = 2.4
        static let volumeHUD: TimeInterval = 1.6
        /// How a borderless surface arrives and leaves; the exit is shorter, so it feels quick.
        static let enter: TimeInterval = 0.18
        static let exit: TimeInterval = 0.12
        /// Fade-in/out for a hover `Tooltip`.
        static let tooltip: TimeInterval = 0.15
        static let copyFeedback: TimeInterval = 1.2
        static let chatFooter: TimeInterval = 0.12
        /// A Settings search result scrolling its section into view, then the pulse that marks it.
        static let settingsReveal: TimeInterval = 0.28
        static let settingsFlash: TimeInterval = 2.0
        static let settingsFlashOut: TimeInterval = 0.6
    }

    /// System text styles (not hardcoded sizes) so the UI honors Dynamic Type.
    enum Typography {
        /// One size, two frameworks: `TextTrailingDragHandle` measures what the field renders.
        static let searchFieldSize: CGFloat = 20
        static let searchField = Font.system(size: searchFieldSize, weight: .regular)
        /// `NSFont` is not `Sendable`, hence the isolation; every reader is a view anyway.
        @MainActor static let searchFieldNSFont = NSFont.systemFont(
            ofSize: searchFieldSize, weight: .regular)
        static let headerIcon = Font.system(size: 18, weight: .medium)
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.subheadline.weight(.medium)
        /// A borderless panel's own title, which names the surface rather than a section inside it.
        static let panelTitle = Font.headline
        /// The big value line on the calculator answer card (both source and target sides).
        static let calcResult = Font.title
        static let keyCap = Font.caption
        /// Pair with the matching `Size` for `KeyCapChip.Scale`.
        static let compactKeyCap = Font.caption2
        static let heroKeyCap = Font.body
        static let markdownHeading1 = Font.title2.weight(.semibold)
        static let markdownHeading2 = Font.title3.weight(.semibold)
        static let markdownHeading3 = Font.headline
        static let code = Font.system(.callout, design: .monospaced)
        static let inlineCode = Font.body.monospaced()
        static let bar = Font.callout.weight(.medium)
        /// A staged chat attachment's name beside the search text; the NSFont measures the chip.
        static let chip = Font.callout
        @MainActor static let chipNSFont = NSFont.preferredFont(forTextStyle: .callout)
        /// A dropdown control's trailing chevron, deliberately smaller than the label it follows.
        static let disclosure = Font.caption.weight(.semibold)
        static let menuRow = Font.body
        static let menuShortcut = Font.callout
        static let menuIcon = Font.body
        static let noteTitle = Font.headline
    }

    enum Colors {
        /// Resolves against the window's `effectiveAppearance`, so a token repaints on its own.
        static func adaptive(dark: NSColor, light: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
        }

        /// The alpha ramp, inverted: white ink over the dark surface, black ink over the light one.
        static func ramp(dark: Double, light: Double) -> Color {
            adaptive(dark: .srgbInk(1, alpha: dark), light: .srgbInk(0, alpha: light))
        }

        /// The ramp's inverse: the scrim darkens the dark surface and lightens the light one.
        static let panelScrim = adaptive(dark: .srgbInk(0, alpha: 0.40), light: .srgbInk(1, alpha: 0.55))
        /// Selection fill, shared by every list so they look identical.
        static let selection = ramp(dark: 0.10, light: 0.09)
        /// Mouse hover: a fainter layer, visually distinct from selection.
        static let rowHover = ramp(dark: 0.05, light: 0.045)
        static let menuHover = ramp(dark: 0.10, light: 0.09)
        static let separator = ramp(dark: 0.10, light: 0.12)
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = ramp(dark: 0.10, light: 0.08)
        /// Control borders: outlined kbd chips.
        static let border = ramp(dark: 0.20, light: 0.18)
        /// Alpha 1, so a call site can dim it with `.opacity` and land on the value it replaced.
        static let textPrimary = ramp(dark: 1.0, light: 1.0)
        static let textSecondary = ramp(dark: 0.60, light: 0.60)
        static let textTertiary = ramp(dark: 0.40, light: 0.42)
        static let noteText = ramp(dark: 0.90, light: 0.85)
        static let iconPlaceholder = ramp(dark: 0.06, light: 0.06)
        /// The faint wash behind the Onboarding header.
        static let sheen = ramp(dark: 0.04, light: 0.04)
        /// The Settings card: a faint surface whose border doubles as the row divider.
        static let cardFill = ramp(dark: 0.05, light: 0.04)
        static let cardStroke = ramp(dark: 0.10, light: 0.10)
        /// White in both: the frost brightens glass, and light glass needs more to read at all.
        static let glassFrost = adaptive(dark: .srgbInk(1, alpha: 0.05), light: .srgbInk(1, alpha: 0.25))
        /// The pill behind the header of the section a Settings search jumped to.
        static let searchFlash = Color.accentColor.opacity(0.35)
        /// The violet of the app mark, used only to tint the About support callout.
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)
        /// The palette's drop guides while dragging, and once a release would snap it home.
        static let dropGuide = ramp(dark: 0.35, light: 0.35)
        static let dropGuideArmed = Color.blue
        /// Destructive tint: a destructive label, and a `.danger` dialog's glyph.
        static let destructive = Color.red
        /// Success tint: the leading glyph of a `.success` dialog.
        static let success = Color.green
        /// Progress tint: the message pill's spinner while the work behind it is still running.
        static let progress = Color.blue
        /// The command output window's page: a flat surface the log sits directly on.
        static let terminalSurface = adaptive(
            dark: .srgbInk(0.07, alpha: 1), light: .srgbInk(0.99, alpha: 1))
    }
}

extension View {
    /// A floating glass control surface, frosted so it reads brighter than clear glass.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive().tint(Theme.Colors.glassFrost), in: shape)
            .tint(.clear)
    }
}
