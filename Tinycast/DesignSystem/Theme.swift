import SwiftUI

/// Central design tokens; the app forces `.darkAqua`, so colours are literal alphas.
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
        /// Space above every header but the first, reading as the previous section's close.
        static let sectionSpacing: CGFloat = 12
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        static let menu: CGFloat = 6
        /// Hover highlight behind a popover menu row.
        static let menuRow: CGFloat = 10
        static let menuPanel: CGFloat = 16
        /// The dialog and HUD surface, so a dialog reads as a sibling of the palette.
        static let dialog: CGFloat = 20
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 10
        static let keyCap: CGFloat = 6
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 4
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
        /// A restored position needs this much of the compact bar on a display to still be grabbable.
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
        /// The uninstall list's leading checkbox / lock glyph.
        static let checkbox: CGFloat = 16
        static let clipboardListWidth: CGFloat = 290
        static let emojiCell: CGFloat = 56
        static let menuWidth: CGFloat = 276
        /// The clipboard type filter's menu; `menuWidth` is far too wide for five short rows.
        static let clipboardFilterMenuWidth: CGFloat = 200
        /// A menu row's glyph slot, sized so symbol and app-icon rows read the same.
        static let menuIcon: CGFloat = 20
        /// Opening size and the resize floor; tall enough that the sidebar's rows never scroll.
        static let settingsWindow = CGSize(width: 860, height: 700)
        /// Settings sidebar: a fixed column, wide enough for "Window Management".
        static let settingsSidebar: CGFloat = 215
        /// The narrowest the pane column may get before a grouped row's control starts colliding.
        static let settingsDetailMinimum: CGFloat = 420
        static let settingsRowIcon: CGFloat = 20
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
        /// The big value line on the calculator answer card (both source and target sides).
        static let calcResult = Font.title
        static let keyCap = Font.caption
        /// Pair with the matching `Size` for `KeyCapChip.Scale`.
        static let compactKeyCap = Font.caption2
        static let heroKeyCap = Font.body
        static let bar = Font.callout.weight(.medium)
        /// A dropdown control's trailing chevron, deliberately smaller than the label it follows.
        static let disclosure = Font.caption.weight(.semibold)
        static let menuRow = Font.body
        static let menuShortcut = Font.callout
        static let menuIcon = Font.body
        static let noteTitle = Font.headline
    }

    enum Colors {
        /// Black opacity of the panel's surface tint over the behind-window material.
        static let panelDimming: CGFloat = 0.4
        /// Selection fill, shared by every list so they look identical.
        static let selection = Color.white.opacity(0.10)
        /// Mouse hover: a fainter layer, visually distinct from selection.
        static let rowHover = Color.white.opacity(0.05)
        static let menuHover = Color.white.opacity(0.10)
        static let separator = Color.white.opacity(0.10)
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = Color.white.opacity(0.10)
        /// Control borders: outlined kbd chips.
        static let border = Color.white.opacity(0.20)
        static let textSecondary = Color.white.opacity(0.60)
        static let textTertiary = Color.white.opacity(0.40)
        static let noteText = Color.white.opacity(0.90)
        /// The Settings card: a faint surface whose border doubles as the row divider.
        static let cardFill = Color.white.opacity(0.05)
        static let cardStroke = Color.white.opacity(0.10)
        /// Tint layered into the floating controls, so the glass reads frosted, not clear.
        static let glassFrost = Color.white.opacity(0.05)
        /// The violet of the app mark, used only to tint the About support callout.
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)
        /// The palette's drop guides while dragging, and once a release would snap it home.
        static let dropGuide = Color.white.opacity(0.35)
        static let dropGuideArmed = Color.blue
        /// Destructive tint: a destructive label, and a `.danger` dialog's glyph.
        static let destructive = Color.red
        /// Success tint: the leading glyph of a `.success` dialog.
        static let success = Color.green
    }
}

extension View {
    /// A floating glass control surface, frosted so it reads brighter than clear glass.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive().tint(Theme.Colors.glassFrost), in: shape)
            .tint(.clear)
    }
}
