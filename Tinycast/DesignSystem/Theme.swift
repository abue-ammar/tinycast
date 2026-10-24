import SwiftUI

/// Central design tokens; every dark colour is the literal the forced-dark build shipped.
enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let dictationWaveGap: CGFloat = 3
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let dialogInset: CGFloat = 18
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 28
        /// Gap under a category header, shared by every palette list's `SectionHeader`.
        static let sectionHeaderBottom: CGFloat = 4
        /// Clearance under the last message, so its actions row belongs to it, not to the footer.
        static let chatTranscriptBottom: CGFloat = 28
        /// A stream grows the transcript as the reader descends, so an exact-bottom test runs away.
        static let chatFollowTailSlack: CGFloat = 44
        /// Extra leading between a transcript's lines, so a long reply reads as paragraphs.
        static let chatLine: CGFloat = 4
        /// Space above every header but the first, reading as the previous section's close.
        static let sectionSpacing: CGFloat = 12
        /// Emoji tiles need a little more separation so adjacent category grids stay distinct.
        static let emojiSectionSpacing: CGFloat = 14
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        static let formField: CGFloat = 12
        /// Emoji tiles are roomier than list rows, so their corners take one larger step.
        static let emojiCell: CGFloat = 12
        static let menu: CGFloat = 6
        static let menuRow: CGFloat = 10
        /// A header pop-up button; the footer's action pills stay capsules.
        static let barControl: CGFloat = 8
        static let menuPanel: CGFloat = 16
        static let dialogSymbol: CGFloat = 16
        /// The dialog and HUD surface, so a dialog reads as a sibling of the palette.
        static let dialog: CGFloat = 20
        static let thumbnail: CGFloat = 6
        /// A shape small enough that `thumbnail` would round it into a circle.
        static let glyph: CGFloat = 2
        /// A pill holding a square thumbnail; a full capsule fights the thumbnail's own corners.
        static let attachmentChip: CGFloat = 8
        static let card: CGFloat = 10
        static let codeBlock: CGFloat = 14
        /// A window-to-be in the room preview, rounded like a real window rather than a row.
        static let roomCard: CGFloat = 16
        static let keyCap: CGFloat = 6
        static let recorderKeyCap: CGFloat = 4
        static let tooltip: CGFloat = 8
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
        static let noteWindowMaxHeight: CGFloat = 860
        static let noteEditorInset: CGFloat = 16
        /// Shorter than the horizontal inset, so the first line sits close under the title bar.
        static let noteEditorTopInset: CGFloat = 6
        static let noteSearchHeight: CGFloat = 34
        /// The switcher popover, sized independently of a note window that can be 180pt tall.
        static let noteSwitcher = CGSize(width: 300, height: 240)
        static let noteSwitcherEmptyHeight: CGFloat = 96
        static let noteSwitcherDrop: CGFloat = 56
        /// Fixed like every menu's width; the height is exactly four heading rows.
        static let noteHeadingMenu = CGSize(
            width: 220, height: menuRowHeight * 4 + menuRowSpacing * 3 + Spacing.sm * 2)
        static let noteFooterHeight: CGFloat = 28
        /// Holds the launcher's 36-point action capsule with the same margin its own bar gives it.
        static let noteTitlebar: CGFloat = 52
        /// Symmetric, so the title stays centred on the window while clearing lights and capsule.
        static let noteTitleInset: CGFloat = 120
        /// Nine points crowds the palette's 26-point corner, so Notes seats its lights further in.
        static let noteTrafficLightInset: CGFloat = 20
        /// Fraction of visible height above the palette's top edge; it grows downward.
        static let paletteTopMarginFraction: CGFloat = 0.18
        /// The search row; padded alike above and below, it is the compact bar's whole height.
        static let headerHeight: CGFloat = 36
        /// Fixed slot for the header glyph, so the field starts at one x in every mode.
        static let headerIconSlot: CGFloat = 22
        /// The narrowest a strip squeezes the search field to: the caret and a few characters.
        static let searchFieldMinWidth: CGFloat = 60
        /// Room above the search row, constant so typing never shifts the bar.
        static let headerPadding: CGFloat = 10
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        /// How close a dragged palette must be to the invisible vertical centre line.
        static let paletteSnapDistance: CGFloat = 8
        /// A restored position needs this much bar on a display to still be grabbable.
        static let paletteMinimumVisible: CGFloat = 44
        static let dropGuideDash: CGFloat = 8
        static let dropGuideGap: CGFloat = 12
        static let dropGuideWidth: CGFloat = 2
        static let dropGuideCombinedFlashTolerance: CGFloat = 6
        static let dropGuideFadeThreshold: CGFloat = 36
        static let dropGuideFadeDistance: CGFloat = 180
        static let bottomBarHeight: CGFloat = 52
        /// The unit a form's text area counts its minimum height in, so it scales with the interface.
        static let textAreaUnit: CGFloat = 44
        static let barButtonHeight: CGFloat = 28
        static let rowIcon: CGFloat = 24
        static let resultRowIcon: CGFloat = 26
        static let colorDot: CGFloat = 8
        static let calendarBarWidth: CGFloat = 3
        static let calendarBarHeight: CGFloat = 18
        static let keyCap: CGFloat = 18
        static let recorderKeyCap: CGFloat = 16
        /// Fixed so the recorder can't resize as its binding changes.
        static let shortcutRecorder: CGFloat = 120
        static let shortcutPopoverLine: CGFloat = 14
        /// Summed from the laid-out bands; the width is pinned by `callout-test`.
        static let shortcutPopover = CGSize(
            width: 176,
            height: Spacing.sm * 2 + heroKeyCap + Spacing.sm + shortcutPopoverLine * 2 + Spacing.sm
                + compactKeyCap + calloutCaretHeight)
        static let calloutCaretWidth: CGFloat = 15
        static let calloutCaretHeight: CGFloat = 7
        static let calloutCaretTip: CGFloat = 2.5
        static let compactKeyCap: CGFloat = 15
        static let heroKeyCap: CGFloat = 22
        static let menuButton: CGFloat = 36
        static let noteGlyph: CGFloat = 16
        static let noteEmptyGlyph: CGFloat = 28
        /// Hit target for a chat message footer glyph; its caption symbol floats inside it.
        static let chatMessageAction: CGFloat = 16
        static let hairline: CGFloat = 1
        static let markdownListMarker: CGFloat = 20
        static let markdownQuoteBar: CGFloat = 2
        static let contextRingStroke: CGFloat = 2
        static let dropHintStroke: CGFloat = 2
        static let dropHintDash: CGFloat = 6
        /// The uninstall list's leading checkbox / lock glyph.
        static let checkbox: CGFloat = 16
        static let clipboardListWidth: CGFloat = 290
        /// Symmetric clearance between the emoji grid and both panel edges.
        static let emojiGridInset: CGFloat = 16
        static let emojiCell: CGFloat = 56
        static let menuWidth: CGFloat = 276
        static let formMenuMinimumWidth: CGFloat = 200
        static let formMenuExtraRowsHeight: CGFloat = 20
        static let formFieldFocusStroke: CGFloat = 2
        static let actionMenuWidth: CGFloat = 320
        /// The clipboard type filter's menu; `menuWidth` is far too wide for six short rows.
        static let clipboardFilterMenuWidth: CGFloat = 200
        static let fileSearchFilterMenuWidth: CGFloat = 200
        /// Fits "Shapes & Punctuation", the longest category title.
        static let emojiCategoryMenuWidth: CGFloat = 220
        /// Stated, not padded: the cap below counts rows, so a capped menu would land mid-row.
        static let menuRowHeight: CGFloat = menuIcon + Spacing.md * 2
        static let menuRowSpacing: CGFloat = 1
        /// Stated, not measured: `viewportHeight` counts headers, so a capped menu lands on a row.
        static let menuSectionHeader: CGFloat = 16
        /// Five rows and half of the sixth, so a capped menu reads as scrollable, not clipped.
        static let menuVisibleRows: CGFloat = 5.5
        static let appMenuVisibleRows: CGFloat = 4.5
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
        /// A sent image in the transcript; a staged one is a small preview in a composer pill.
        static let chatImageThumb: CGFloat = 96
        static let chatAttachmentGlyph: CGFloat = 16
        /// A staged file's preview in its pill, kept under the pill's height so it reads inside it.
        static let chatAttachmentThumb: CGFloat = 18
        static let chatAttachmentRemove: CGFloat = 14
        /// Tighter than the gap inside the pill, so the thumbnail reads as filling it.
        static let chatAttachmentInset: CGFloat = 3
        /// The clipboard preview's player; `VideoPlayer` expands unbounded without a height.
        static let clipboardMediaHeight: CGFloat = 260
        /// The preview pane is ~460pt wide, so 900px stays crisp at 2× without over-decoding.
        static let clipboardPreviewPixel: CGFloat = 900
        /// File search's preview stage: video's own shape, and enough height to read a page in.
        static let previewAspectRatio: CGFloat = 16 / 9
        /// Opening size and resize floor: the Quick Actions row's width, the sidebar's full height.
        static let settingsWindow = CGSize(width: 900, height: 700)
        /// Settings sidebar: a fixed column, wide enough for "Window Management".
        static let settingsSidebar: CGFloat = 215
        /// The narrowest the pane column may get before a grouped row's control starts colliding.
        static let settingsDetailMinimum: CGFloat = 420
        static let settingsRowIcon: CGFloat = 20
        /// Inside its tinted tile, whose inset brings it to the row icon's size.
        static let settingsSidebarGlyph: CGFloat = 14
        /// AI Chat's opening size; the user owns it from there, autosaved.
        static let aiChatWindow = CGSize(width: 960, height: 660)
        static let aiChatWindowMinimum = CGSize(width: 680, height: 440)
        static let aiChatSidebarMinimum: CGFloat = 240
        static let aiChatSidebarMaximum: CGFloat = 340
        /// The sidebar's search capsule, a row's height so it lines up with the list below it.
        static let aiChatSearchField: CGFloat = 28
        static let aiChatDetailMinimum: CGFloat = 440
        /// The transcript and composer column; past this a line of prose stops being readable.
        static let aiChatReadingWidth: CGFloat = 960
        static let aiChatComposerMaxLines: CGFloat = 15
        static let aiChatComposerHeightFraction: CGFloat = 0.30
        /// Every control on the composer's row, Send included, so the row reads as one line.
        static let aiChatComposerControl: CGFloat = 28
        /// One slot for every glyph on that row, so a plus and a brand mark weigh the same.
        static let aiChatComposerGlyph: CGFloat = 16
        static let chatContextGauge: CGFloat = 14
        /// A source chip's title before it middle-truncates, so three chips share a row.
        static let chatSourceTitle: CGFloat = 200
        static let chatSourceBadge: CGFloat = 18
        static let chatJumpToLatest: CGFloat = 30
        /// The context card's width: a label column and a value one, with room for a model name.
        static let chatContextCard: CGFloat = 300
        static let settingsControlHeight: CGFloat = 28
        static let emojiSkinToneGlyph: CGFloat = 13
        /// One density preview; five fit across the Emoji settings detail pane.
        static let emojiSettingsGridPreview: CGFloat = 72
        /// The layout editor. Height is stated so selecting an entry cannot resize the panel.
        static let layoutEditorSheet = CGSize(width: 900, height: 660)
        /// The inspector column; the preview takes the rest, keeping the split two-to-one.
        static let layoutInspectorColumn: CGFloat = 300
        /// The entry dropdown's list, wider than its button so a long app name still reads.
        static let layoutEntryPopover: CGFloat = 260
        /// An app icon inside a preview rect, small enough a narrow window still shows one.
        static let layoutPreviewIcon: CGFloat = 22
        static let layoutDisplayTab: CGFloat = 24
        /// Every inspector control — field, dropdown, add button — sits on this one height.
        static let layoutControlHeight: CGFloat = 28
        /// The unit slot in a numeric field, stated so "%" and "pt" put their digits on one x.
        static let layoutFieldUnit: CGFloat = 16
        static let layoutPositionGlyph = CGSize(width: 26, height: 19)
        static let layoutPositionStroke: CGFloat = 1.5
        /// A position cell's clickable row; the glyph floats inside it, so the whole cell hits.
        static let layoutPositionCell: CGFloat = 34
        static let aiProvidersPanel = CGSize(width: 840, height: 520)
        static let aiProvidersList: CGFloat = 262
        /// What the system leaves either side of a segment's label once the control has settled.
        static let segmentLabelInset: CGFloat = 13
        static let aiVariableName: CGFloat = 170
        /// A Codex usage window's meter, beside its "72% left" readout.
        static let aiUsageBar: CGFloat = 110
        /// Settings editor modals (Custom Commands, Snippets): fixed width, intrinsic height.
        static let editorSheetWidth: CGFloat = 480
        /// The multi-line box inside those modals; it scrolls rather than grows the panel.
        static let editorTextHeight: CGFloat = 120
        /// The confirmation HUD's width ceiling, and its distance above the screen bottom.
        static let hudMaxWidth: CGFloat = 420
        static let hudEdgeOffset: CGFloat = 48
        /// Questions and notices stay compact; controls keep the room their native widgets need.
        static let dialogCompactWidth: CGFloat = 290
        /// Tinycast's own control dialog: fixed width, height measured from its SwiftUI content.
        static let dialogWidth: CGFloat = 420
        static let dialogTextHeight: CGFloat = 180
        static let dialogButtonHeight: CGFloat = menuButton - 2
        static let dialogSymbol: CGFloat = 28
        static let dialogSymbolContainer: CGFloat = 52
        /// Shared measurement for dialog accessories and the volume-HUD glyph.
        static let dialogIcon: CGFloat = 32
        /// 16:9 at the dialog's own width, so the two surfaces read as siblings.
        static let cameraPreview = CGSize(width: 420, height: 236)
        /// 16:9 again, wider: the standalone camera is the surface, not a confirmation on one.
        static let cameraStage = CGSize(width: 560, height: 315)
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
        static let dictationPanel = CGSize(width: 144, height: 44)
        static let dictationWaveBar: CGFloat = 2
        /// Read-only volume bar geometry used by the HUD.
        static let volumeTrackHeight: CGFloat = 6
        /// Fixed slot for the level readout, sized to the widest string it ever holds.
        static let volumeReadout: CGFloat = 38
        static let roomCardTitleBar: CGFloat = 40
        static let roomCardStroke: CGFloat = 2
        static let roomCardShadowRadius: CGFloat = 24
        static let roomCardShadowOffset: CGFloat = 8
        static let roomCardDot: CGFloat = 8
        static let roomCardIcon: CGFloat = 64
        static let roomCardIconLarge: CGFloat = 96
        /// Below this a card is a sliver, too short for its icon.
        static let roomCardIconMinHeight: CGFloat = 160
        static let roomCardLargeIconMinSide: CGFloat = 320
    }

    enum Duration {
        /// How long each HUD stays up; a sentence needs longer than a level does.
        static let messageHUD: TimeInterval = 2.4
        static let volumeHUD: TimeInterval = 1.6
        /// How a borderless surface arrives and leaves; the exit is shorter, so it feels quick.
        static let enter: TimeInterval = 0.18
        static let exit: TimeInterval = 0.12
        /// A dialog moves with its launcher dimming; its fade-in is a shorter sub-beat.
        static let dialogEnter: TimeInterval = 0.12
        static let dialogExit: TimeInterval = 0.10
        /// Fade-in/out for a hover `Tooltip`, after a wait only a deliberate hover outlasts.
        static let tooltip: TimeInterval = 0.15
        static let dropGuide: TimeInterval = 0.24
        static let tooltipDelay: TimeInterval = 0.4
        static let hover: TimeInterval = 0.12
        static let menuChevron: TimeInterval = 0.34
        static let copyFeedback: TimeInterval = 1.2
        static let chatFooter: TimeInterval = 0.12
        static let settingsReveal: TimeInterval = 0.28
        static let settingsFlash: TimeInterval = 2.0
        static let settingsFlashOut: TimeInterval = 0.6
        static let roomGlide: TimeInterval = 0.32
        static let roomCardEnter: TimeInterval = 0.2
        static let roomCardExit: TimeInterval = 0.18
        static let roomSettle: TimeInterval = 0.25
    }

    enum RoomMotion {
        /// Quick to leave, long to settle, so a card reads as the window it is about to become.
        static let glide = Animation.timingCurve(0.2, 0, 0, 1, duration: Theme.Duration.roomGlide)
    }

    enum CompactBarMotion {
        /// Under the 10pt gap, so resting buttons stand apart and only moving ones fuse.
        static let blend: CGFloat = 8
        /// Parked inside the capsule's end this small, so each button pinches out of it.
        static let parkedScale: CGFloat = 0.36
        /// One button after another, beaded off the capsule.
        static let stagger: TimeInterval = 0.055
        /// A summon lands first; the buttons extrude once the window has arrived.
        static let revealDelay: TimeInterval = 0.12
        /// The glyph surfaces once its glass has formed, and blurs in rather than popping.
        static let glyphDelay: TimeInterval = 0.24
        static let glyphFade: TimeInterval = 0.16
        static let glyphBlur: CGFloat = 4
        /// Past the window's own close animation, so parking the buttons is never seen.
        static let parkAfterHide: TimeInterval = 0.3
        /// The capsule undershoots as it shortens, then settles.
        static let capsule = Animation.spring(response: 0.44, dampingFraction: 0.62)
        /// The buttons barely overshoot: the last rests on the window's edge, which would clip it.
        static let button = Animation.spring(response: 0.44, dampingFraction: 0.86)
    }

    enum MenuMotion {
        /// Starts promptly and eases gently into the chevron's final direction.
        static let chevronAnimation = Animation.timingCurve(
            0.16, 1, 0.3, 1, duration: Theme.Duration.menuChevron)
    }

    enum Typography {
        /// One size, two frameworks: `TextTrailingDragHandle` measures what the field renders.
        static let searchFieldSize: CGFloat = 20
        static let searchField = Font.system(size: searchFieldSize, weight: .regular)
        /// `NSFont` is not `Sendable`, hence the isolation; every reader is a view anyway.
        @MainActor static let searchFieldNSFont = NSFont.systemFont(
            ofSize: searchFieldSize, weight: .regular)
        static let headerIconSize: CGFloat = 18
        static let headerIcon = Font.system(size: headerIconSize, weight: .medium)
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.subheadline.weight(.medium)
        /// A borderless panel's own title, which names the surface rather than a section inside it.
        static let panelTitle = Font.headline
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
        static let menuSymbolSize: CGFloat = 14
        static let menuSymbolWeight = Font.Weight.medium
        static let noteTitle = Font.headline
        static let composerSymbol = Font.system(size: 13, weight: .medium)
        static let composerSend = Font.system(size: 13, weight: .bold)
        static let composerStop = Font.system(size: 10, weight: .bold)
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
        static let dialogDimming = adaptive(
            dark: .srgbInk(0, alpha: 0.34), light: .srgbInk(0, alpha: 0.34))
        /// Find's marks, the Mac's own yellow: every match faint, the current one solid.
        static let findMatch = adaptive(
            dark: NSColor.systemYellow.withAlphaComponent(0.32),
            light: NSColor.systemYellow.withAlphaComponent(0.4))
        static let findCurrent = adaptive(
            dark: NSColor.systemYellow.withAlphaComponent(0.9),
            light: NSColor.systemYellow.withAlphaComponent(0.95))
        /// Black on the solid mark in both appearances, as a highlighter's ink stays readable.
        static let findCurrentInk = adaptive(
            dark: .srgbInk(0, alpha: 1), light: .srgbInk(0, alpha: 1))
        static let tooltipShadow = adaptive(
            dark: .srgbInk(0, alpha: 0.18), light: .srgbInk(0, alpha: 0.18))

        /// Selection fill, shared by every list so they look identical.
        static let selection = ramp(dark: 0.10, light: 0.09)
        static let rowHover = ramp(dark: 0.05, light: 0.045)
        static let emojiCell = ramp(dark: 0.045, light: 0.04)
        static let emojiHoverBorder = ramp(dark: 0.42, light: 0.34)
        static let emojiSelectionBorder = ramp(dark: 0.92, light: 0.72)
        static let emojiInnerBorder = adaptive(
            dark: .srgbInk(0, alpha: 0.72), light: .srgbInk(1, alpha: 0.72))
        static let menuHover = ramp(dark: 0.10, light: 0.09)
        static let separator = ramp(dark: 0.10, light: 0.12)
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = ramp(dark: 0.10, light: 0.08)
        static let controlHover = ramp(dark: 0.16, light: 0.14)
        /// A held control is stronger than hover, so mouse-down always reads.
        static let controlPressed = ramp(dark: 0.24, light: 0.20)
        static let compactShortcutGlassSelection = ramp(dark: 1, light: 0)
        static let compactShortcutSelection = ramp(dark: 0.20, light: 0.55)
        static let compactShortcutSelectedInk = adaptive(
            dark: .srgbInk(1, alpha: 1), light: .srgbInk(1, alpha: 1))
        /// Control borders: outlined kbd chips.
        static let border = ramp(dark: 0.20, light: 0.18)
        /// Alpha 1, so a call site can dim it with `.opacity` and land on the value it replaced.
        static let textPrimary = ramp(dark: 1.0, light: 1.0)
        static let textSecondary = ramp(dark: 0.60, light: 0.60)
        static let textTertiary = ramp(dark: 0.40, light: 0.42)
        static let menuSymbol = ramp(dark: 0.70, light: 0.70)
        static let noteText = ramp(dark: 0.90, light: 0.85)
        static let iconPlaceholder = ramp(dark: 0.06, light: 0.06)
        static let sheen = ramp(dark: 0.04, light: 0.04)
        /// The Settings card: a faint surface whose border doubles as the row divider.
        static let cardFill = ramp(dark: 0.05, light: 0.04)
        static let cardStroke = ramp(dark: 0.10, light: 0.10)
        /// A window on the preview's plate. White in both, since the plate is always dark.
        static let layoutPreviewWindow = adaptive(
            dark: .srgbInk(1, alpha: 0.22), light: .srgbInk(1, alpha: 0.28))
        /// The selected one, lifted enough to read as chosen before the accent stroke is seen.
        static let layoutPreviewWindowSelected = adaptive(
            dark: .srgbInk(1, alpha: 0.38), light: .srgbInk(1, alpha: 0.44))
        /// The preview's plate: a display is dark in both appearances, so `adaptive`, not `ramp`.
        static let layoutPreviewGround = adaptive(
            dark: .srgbInk(0, alpha: 0.55), light: .srgbInk(0, alpha: 0.50))
        /// The blurred desk behind a room preview, darkened so only the new layout reads.
        static let roomPreviewDim = adaptive(
            dark: .srgbInk(0, alpha: 0.18), light: .srgbInk(0, alpha: 0.18))
        /// A room card is a solid window in both appearances, so the desk never shows through.
        static let roomCardFill = adaptive(
            dark: .srgbInk(0.16, alpha: 0.94), light: .srgbInk(0.98, alpha: 0.94))
        static let roomCardStroke = Color.accentColor
        static let roomCardShadow = adaptive(
            dark: .srgbInk(0, alpha: 0.25), light: .srgbInk(0, alpha: 0.25))
        static let roomCardDot = ramp(dark: 0.25, light: 0.25)
        static let searchFlash = Color.accentColor.opacity(0.35)
        static let checkerLight = Color(nsColor: .srgbInk(1, alpha: 0.22))
        static let checkerDark = Color(nsColor: .srgbInk(0, alpha: 0.22))
        /// The violet of the app mark, used only to tint the About support callout.
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)
        /// The palette's drop guides while dragging, and once a release would snap it home.
        static let dropGuide = ramp(dark: 0.35, light: 0.35)
        static let dropGuideArmed = Color.blue
        /// A dialog's standard default action; destructive defaults keep their semantic red.
        static let primaryAction = Color.blue
        static let destructive = Color.red
        static let success = Color.green
        static let warning = Color.orange
        static let composerSend = ramp(dark: 0.92, light: 0.92)
        static let composerSendInk = adaptive(dark: .srgbInk(0, alpha: 0.85), light: .srgbInk(1, alpha: 1))
        /// The window's own page, for a card that must hide the transcript it floats over.
        static let windowSurface = Color(nsColor: .windowBackgroundColor)
        static let dropTarget = Color.accentColor
        /// Progress tint: the message pill's spinner while the work behind it is still running.
        static let progress = Color.blue
        /// The command output window's page: a flat surface the log sits directly on.
        static let terminalSurface = adaptive(
            dark: .srgbInk(0.07, alpha: 1), light: .srgbInk(0.99, alpha: 1))

        enum Syntax {
            static let keyword = pair(dark: 0xFC5FA3, light: 0xAD3DA4)
            static let string = pair(dark: 0xFC6A5D, light: 0xD12F1B)
            static let number = pair(dark: 0xD0BF69, light: 0x272AD8)
            static let comment = pair(dark: 0x7F8C98, light: 0x5D6C79)
            static let type = pair(dark: 0x5DD8FF, light: 0x1F7A85)
            static let function = pair(dark: 0x67B7A4, light: 0x2B6A72)
            static let constant = pair(dark: 0xD0A8FF, light: 0x6C36A9)
            static let attribute = pair(dark: 0xFD8F3F, light: 0x78492A)
            static let property = pair(dark: 0x6BBCDD, light: 0x0F68A0)
            static let inserted = pair(dark: 0x67D97E, light: 0x1F7F3A)
            static let deleted = pair(dark: 0xFC6A5D, light: 0xC0301F)

            private static func pair(dark: UInt32, light: UInt32) -> Color {
                adaptive(dark: rgb(dark), light: rgb(light))
            }

            private static func rgb(_ hex: UInt32) -> NSColor {
                NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            }
        }
    }
}

extension View {
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
    }
}
