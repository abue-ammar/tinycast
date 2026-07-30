import SwiftUI

/// Central design tokens for the palette UI (dark design system per `docs/ui.md`; the app forces `.darkAqua`, so colors are literal white/black alphas).
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
        /// Gap under a category header before its first row; shared by every palette list's `SectionHeader` (launcher, clipboard, emoji, calculator history).
        static let sectionHeaderBottom: CGFloat = 4
        /// Space above a category header (every header except the list's first), which reads as bottom padding closing the previous section — shared by every palette list.
        static let sectionSpacing: CGFloat = 12
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        static let menu: CGFloat = 6
        /// Hover highlight behind a popover menu row.
        static let menuRow: CGFloat = 10
        static let menuPanel: CGFloat = 16
        /// Tinycast's own modal / HUD surface, sized between `menuPanel` and `panel`, so a dialog reads as a smaller sibling of the palette rather than a second palette.
        static let modal: CGFloat = 20
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 10
        static let keyCap: CGFloat = 6
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 4
    }

    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 475
        /// Fraction of the active screen's visible height between the top of the visible area and the palette's top edge; the window grows downward from this edge (Spotlight-style upper placement).
        static let paletteTopMarginFraction: CGFloat = 0.18
        static let headerHeight: CGFloat = 44
        /// Fixed slot for the header leading glyph (search / back chevron / mode icon) so the search field starts at the same x in every mode — glyphs have different intrinsic widths (chevron 14, magnifyingglass 22). Sized to the magnifyingglass so the launcher spacing is unchanged.
        static let headerIconSlot: CGFloat = 22
        /// Vertical breathing room above the search row — constant across compact/expanded so the bar never shifts when typing flips the state; also the compact bar's symmetric top/bottom slack.
        static let headerPadding: CGFloat = 10
        /// Collapsed compact bar: the search row centered in symmetric `headerPadding` slack.
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        static let bottomBarHeight: CGFloat = 52
        static let rowIcon: CGFloat = 24
        static let keyCap: CGFloat = 18
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 16
        static let menuButton: CGFloat = 36
        static let clipboardListWidth: CGFloat = 290
        static let emojiCell: CGFloat = 56
        static let menuWidth: CGFloat = 276
        /// Square slot for a popover-menu row's leading glyph. 20 (not the 16 the artwork suggests) because an `IconCache` app icon only paints ~85% of its canvas: at 20 its visible artwork is 17pt, matching the 17–18pt a `.body` SF Symbol renders at, so symbol and app-icon rows read the same size.
        static let menuIcon: CGFloat = 20
        /// Settings window: sidebar column width and the small icon used in setting rows.
        static let settingsSidebar: CGFloat = 184
        static let settingsRowIcon: CGFloat = 20
        /// Little state indicator dot next to a settings row title (Hyper Key active/needs-permission).
        static let statusDot: CGFloat = 6
        /// Settings editor modals (Custom Commands, Snippets): fixed width, intrinsic height.
        static let editorSheetWidth: CGFloat = 480
        /// The multi-line text box inside those modals (shell command, snippet template) — it scrolls internally rather than growing the sheet.
        static let editorTextHeight: CGFloat = 120
        /// Field column in the snippet argument prompt. At or below 220 the alert keeps its natural 260pt width, so its buttons sit exactly where every other alert's do.
        static let argumentPromptWidth: CGFloat = 220
        /// Confirmation HUD: it sizes to its message, up to this ceiling, and sits this far above the bottom of the screen.
        static let hudMaxWidth: CGFloat = 420
        static let hudEdgeOffset: CGFloat = 48
        /// Tinycast's own modal: fixed width, height measured from the SwiftUI content.
        static let modalWidth: CGFloat = 420
        /// Leading glyph on a modal, larger than a row icon because it carries the dialog's tone (warning / question).
        static let modalIcon: CGFloat = 26
        /// Transient volume HUD shown after any volume or mute command.
        static let hudWidth: CGFloat = 200
        static let hudHeight: CGFloat = 92
        /// Volume slider geometry, shared by the Set Volume modal and the HUD's read-only bar.
        static let volumeTrackHeight: CGFloat = 6
        static let volumeKnob: CGFloat = 16
    }

    enum Duration {
        /// How long the confirmation HUD stays on screen.
        static let hud: TimeInterval = 1.6
    }

    /// System text styles (not hardcoded sizes) so the UI honors Dynamic Type.
    enum Typography {
        static let searchField = Font.system(size: 20, weight: .regular)
        static let headerIcon = Font.system(size: 18, weight: .medium)
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.subheadline.weight(.medium)
        /// The big value line on the calculator answer card (both source and target sides).
        static let calcResult = Font.title
        static let keyCap = Font.caption
        static let bar = Font.callout.weight(.medium)
        static let menuRow = Font.body
        static let menuShortcut = Font.callout
        static let menuIcon = Font.body
    }

    enum Colors {
        /// Black opacity of the panel's surface tint over the behind-window material.
        static let panelDimming: CGFloat = 0.4
        /// Selection fill: a soft neutral translucent layer shared by launcher and clipboard so both lists look identical.
        static let selection = Color.white.opacity(0.10)
        /// Mouse hover — a fainter layer that follows the cursor, visually distinct from selection.
        static let rowHover = Color.white.opacity(0.05)
        static let menuHover = Color.white.opacity(0.10)
        static let separator = Color.white.opacity(0.10)
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = Color.white.opacity(0.10)
        /// Control borders: outlined kbd chips.
        static let border = Color.white.opacity(0.20)
        static let textSecondary = Color.white.opacity(0.60)
        static let textTertiary = Color.white.opacity(0.40)
        /// Settings grouped "card": a faint raised surface whose hairline border doubles as the inset row divider.
        static let cardFill = Color.white.opacity(0.05)
        static let cardStroke = Color.white.opacity(0.10)
        /// Whitish tint layered into the Liquid Glass floating controls (action group + menu circle) so the glass reads frosted rather than clear.
        static let glassFrost = Color.white.opacity(0.05)
        /// The violet of the app mark. The one non-white hue in the system, used only to tint the About support callout.
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)
    }
}

/// A single keycap chip: `.outline` for hotkey hints on rows, `.filled` for footer shortcuts.
struct KeyCapChip: View {
    enum Style {
        case outline
        case filled
    }

    let text: String
    var style: Style = .filled

    /// "↵" is absent from SF Pro and falls back to Lucida Grande UI, which seats it 1.1pt higher in the line box than the SF caps — visibly top-heavy in a chip. Nudging via `offset` is render-only, so the chip keeps the same footprint as every other cap.
    private static let returnGlyphDrop: CGFloat = 1.1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
        Text(text)
            .font(Theme.Typography.keyCap)
            .foregroundStyle(Theme.Colors.textSecondary)
            .offset(y: text == "↵" ? Self.returnGlyphDrop : 0)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minWidth: Theme.Size.keyCap, minHeight: Theme.Size.keyCap)
            .background {
                switch style {
                case .filled: shape.fill(Theme.Colors.controlSurface)
                case .outline: shape.strokeBorder(Theme.Colors.border, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// A floating Liquid Glass control surface (action group + menu button), interactive for native lensing with a whitish frost tint so it reads brighter than clear glass.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive().tint(Theme.Colors.glassFrost), in: shape)
            .tint(.clear)
    }
}
