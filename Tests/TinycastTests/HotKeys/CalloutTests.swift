import AppKit
import SwiftUI
import Testing

@testable import Tinycast

/// Drives `CalloutPlacement` against the real `Theme`, so a retuned token fails here.
@MainActor
struct CalloutTests {
    // Exactly what `ShortcutRecorderPopoverHost` passes.
    static let size = Theme.Size.shortcutPopover
    static let gap = Theme.Spacing.sm
    static let inset = Theme.Spacing.xs
    static let cornerRadius = Theme.Radius.menuPanel
    static let caretWidth = Theme.Size.calloutCaretWidth

    /// Pane `xxl` padding, row `xl` padding, then half the field.
    static let fieldInsetFromPaneEdge = Theme.Spacing.xxl + Theme.Spacing.xl + Theme.Size.shortcutRecorder / 2
    /// The nearest the tip may sit to an edge before it would grow out of a corner arc.
    static let caretLimit = cornerRadius + caretWidth / 2

    static let pane = CGSize(width: 600, height: 800)
    nonisolated static let instructions = [
        "Press again for a double press", "Release or complete the shortcut", "Release to record"
    ]

    // MARK: The case that actually ships

    @Test(arguments: [Theme.Size.settingsSidebar + 320, 720, 1100] as [CGFloat])
    func theCalloutCentresOnARealRecorder(paneWidth: CGFloat) {
        let field = CGRect(
            x: paneWidth - Self.fieldInsetFromPaneEdge - Theme.Size.shortcutRecorder / 2, y: 400,
            width: Theme.Size.shortcutRecorder, height: 24)
        let placement = Self.resolve(field: field, container: CGSize(width: paneWidth, height: 800))
        #expect(abs(placement.center.x - field.midX) < 0.001)
        #expect(abs(placement.caretX - Self.size.width / 2) < 0.001)
    }

    /// Widen the callout past this and the caret skews on a trailing-edge recorder.
    @Test func theCalloutIsNarrowEnoughToCentreOnATrailingRecorder() {
        #expect(Self.size.width / 2 + Self.inset <= Self.fieldInsetFromPaneEdge)
    }

    // MARK: Above vs below

    @Test func aFieldWithRoomAboveGetsTheCalloutAbove() {
        let field = CGRect(x: 400, y: 400, width: 80, height: 24)
        let above = Self.resolve(field: field, container: Self.pane)
        #expect(above.caretEdge == .bottom)
        #expect(abs(above.center.y - (field.minY - Self.gap - Self.size.height / 2)) < 0.001)
        #expect(above.center.y + Self.size.height / 2 <= field.minY, "never overlaps the field it points at")
    }

    @Test func aFieldNearThePanesTopFlipsTheCalloutBelow() {
        let field = CGRect(x: 400, y: 40, width: 80, height: 24)
        let below = Self.resolve(field: field, container: Self.pane)
        #expect(below.caretEdge == .top)
        #expect(abs(below.center.y - (field.maxY + Self.gap + Self.size.height / 2)) < 0.001)
    }

    @Test func exactlyEnoughRoomAboveDoesNotFlip() {
        let field = CGRect(x: 400, y: Self.size.height + Self.gap, width: 80, height: 24)
        #expect(Self.resolve(field: field, container: Self.pane).caretEdge == .bottom)
    }

    @Test func onePointShortOfTheRoomItNeedsFlips() {
        let field = CGRect(x: 400, y: Self.size.height + Self.gap - 1, width: 80, height: 24)
        #expect(Self.resolve(field: field, container: Self.pane).caretEdge == .top)
    }

    // MARK: Staying inside the pane

    @Test func aMidPaneFieldCentresTheCallout() {
        let placement = Self.resolve(
            field: CGRect(x: 260, y: 400, width: 80, height: 24), container: Self.pane)
        #expect(abs(placement.center.x - 300) < 0.001)
    }

    /// A recorder sits at a settings row's trailing edge, the case that happens.
    @Test func aTrailingFieldSlidesTheCalloutBackInsideThePane() {
        let placement = Self.resolve(
            field: CGRect(x: 500, y: 400, width: 80, height: 24), container: Self.pane)
        #expect(abs(placement.center.x - (Self.pane.width - Self.size.width / 2 - Self.inset)) < 0.001)
        #expect(placement.center.x + Self.size.width / 2 <= Self.pane.width - Self.inset + 0.001)
    }

    @Test func aLeadingFieldClampsTheSameWay() {
        let placement = Self.resolve(field: CGRect(x: 0, y: 400, width: 80, height: 24), container: Self.pane)
        #expect(abs(placement.center.x - (Self.size.width / 2 + Self.inset)) < 0.001)
        #expect(placement.center.x - Self.size.width / 2 >= Self.inset - 0.001)
    }

    // MARK: Where the pointer lands

    @Test func anUnclampedCalloutPointsFromItsMiddle() {
        let placement = Self.resolve(
            field: CGRect(x: 260, y: 400, width: 80, height: 24), container: Self.pane)
        #expect(abs(placement.caretX - Self.size.width / 2) < 0.001)
    }

    /// Once the body is clamped, the tip walks toward the edge to keep aiming.
    @Test func aClampedCalloutStillPointsAtTheFieldsCentre() {
        let field = CGRect(x: 500, y: 400, width: 80, height: 24)
        let placement = Self.resolve(field: field, container: Self.pane)
        #expect(abs(placement.center.x - Self.size.width / 2 + placement.caretX - field.midX) < 0.001)
        #expect(placement.caretX > Self.size.width / 2)
    }

    @Test func thePointerStopsClearOfTheTrailingCornerArc() {
        let placement = Self.resolve(
            field: CGRect(x: 596, y: 400, width: 80, height: 24), container: Self.pane)
        #expect(placement.caretX <= Self.size.width - Self.caretLimit + 0.001)
    }

    @Test func thePointerStopsClearOfTheLeadingCornerArc() {
        let placement = Self.resolve(
            field: CGRect(x: -200, y: 400, width: 80, height: 24), container: Self.pane)
        #expect(placement.caretX >= Self.caretLimit - 0.001)
    }

    // MARK: Containers smaller than the callout

    /// A pane narrower than the callout has no valid inset range; `max` must win.
    @Test func aTooNarrowPaneStillResolvesFinitely() {
        let placement = Self.resolve(
            field: CGRect(x: 10, y: 400, width: 80, height: 24), container: CGSize(width: 200, height: 800))
        #expect(abs(placement.center.x - (Self.size.width / 2 + Self.inset)) < 0.001)
        #expect(placement.caretX.isFinite)
    }

    @Test func aPaneWithNoRoomAboveFlipsBelowEvenWhenCramped() {
        let placement = Self.resolve(
            field: CGRect(x: 100, y: 4, width: 80, height: 24), container: CGSize(width: 600, height: 60))
        #expect(placement.caretEdge == .top)
        #expect(placement.center.y.isFinite)
    }

    // MARK: Shared row grammar

    @Test func theUninstallCheckboxFitsTheSharedLeadingSlot() {
        #expect(Theme.Size.checkbox <= Theme.Size.rowIcon)
        #expect(Theme.Size.checkbox > 0)
    }

    // MARK: Localized instructions

    @Test(arguments: instructions, AppLanguage.allCases)
    func anInstructionFitsTwoLines(_ key: String, _ language: AppLanguage) throws {
        let table = try #require(Bundle.main.url(forResource: language.rawValue, withExtension: "lproj"))
        let label = try #require(Bundle(url: table)).localizedString(forKey: key, value: nil, table: nil)
        let text = Text(verbatim: label)
            .font(Theme.Typography.compactKeyCap)
            .frame(width: Self.size.width - Theme.Spacing.md * 2)
            .fixedSize(horizontal: false, vertical: true)
        #expect(NSHostingView(rootView: text).fittingSize.height <= Theme.Size.shortcutPopoverLine * 2)
    }

    private static func resolve(field: CGRect, container: CGSize) -> CalloutPlacement {
        CalloutPlacement.resolve(
            field: field, container: container, size: size, gap: gap, inset: inset,
            cornerRadius: cornerRadius, caretWidth: caretWidth)
    }
}
