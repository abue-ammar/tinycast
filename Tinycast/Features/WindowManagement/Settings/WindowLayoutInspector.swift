import AppKit
import SwiftUI

/// The editor's right column. Stacks the field groups; holds no geometry of its own.
struct WindowLayoutInspector: View {
    let draft: WindowLayoutDraft
    let displays: [WindowLayoutDisplay]

    @State private var showingIconPicker = false
    @FocusState private var nameFocused: Bool

    /// Arrangements and workplaces; never the menu bar's own glyph, which reads as the app.
    private static let iconSymbols = [
        "rectangle.3.group", "square.grid.2x2", "rectangle.split.2x1", "rectangle.split.3x1",
        "rectangle.split.1x2", "sidebar.left", "macwindow", "display", "display.2",
        "laptopcomputer", "desktopcomputer", "briefcase", "hammer",
        "chevron.left.forwardslash.chevron.right", "paintbrush", "calendar", "video", "chart.bar",
        "terminal", "globe", "envelope", "message", "music.note", "book"
    ]

    var body: some View {
        // Insurance only: at any normal text size every group fits the sheet's stated height.
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                nameField
                gapToggle
                Divider()
                sectionLabel("Layout")
                WindowLayoutEntryPicker(draft: draft, displays: displays)
                if draft.selectedEntry != nil {
                    WindowLayoutArgumentField(draft: draft)
                    Divider()
                    sizeFields
                    offsetFields
                    positionField
                }
            }
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Layout-wide

    /// The picker lives inside the field's chrome, so name and icon read as the one control.
    private var nameField: some View {
        @Bindable var draft = draft
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("Name")
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Office", text: $draft.name)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .focusEffectDisabled()
                Divider()
                    .frame(height: Theme.Spacing.xl)
                Button {
                    showingIconPicker = true
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
                        SymbolImage(name: draft.symbol, size: 13)
                        Image(systemName: "chevron.down")
                            .font(Theme.Typography.disclosure)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose an icon")
                .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                    SymbolPicker(
                        selection: $draft.iconSymbol, fallback: WindowLayout.sfSymbol,
                        symbols: Self.iconSymbols
                    ) {
                        showingIconPicker = false
                    }
                }
            }
            .layoutFieldChrome(isFocused: nameFocused)
        }
    }

    private var gapToggle: some View {
        @Bindable var draft = draft
        return HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Use preferred gap")
                    .font(.callout.weight(.medium))
                Text("Inset every window by the gap set above, as the tiling commands do.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $draft.usesPreferredGap)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The entry being edited

    private var sizeFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("Size")
            HStack(spacing: Theme.Spacing.md) {
                WindowLayoutNumberField(
                    label: "W", name: "Width", suffix: "%",
                    range: WindowLayoutDraft.percentRange,
                    value: WindowLayoutDraft.percent(entry.widthFraction),
                    onCommit: draft.setWidthPercent)
                WindowLayoutNumberField(
                    label: "H", name: "Height", suffix: "%",
                    range: WindowLayoutDraft.percentRange,
                    value: WindowLayoutDraft.percent(entry.heightFraction),
                    onCommit: draft.setHeightPercent)
            }
        }
    }

    private var offsetFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("Offset")
            HStack(spacing: Theme.Spacing.md) {
                WindowLayoutNumberField(
                    label: "X", name: "Horizontal offset", suffix: "pt",
                    range: WindowLayoutDraft.offsetRange, value: Int(entry.offset.x.rounded()),
                    onCommit: draft.setOffsetX)
                WindowLayoutNumberField(
                    label: "Y", name: "Vertical offset", suffix: "pt",
                    range: WindowLayoutDraft.offsetRange, value: Int(entry.offset.y.rounded()),
                    onCommit: draft.setOffsetY)
            }
        }
    }

    private var positionField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("Position")
            WindowLayoutPositionGrid(selection: entry.anchor, onSelect: draft.setAnchor)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.medium))
    }

    /// Safe: every caller is behind a `draft.selectedEntry != nil` check.
    private var entry: WindowLayoutEntry {
        draft.selectedEntry ?? WindowLayoutEntry(bundleID: "", display: .init(uuid: "", name: ""))
    }
}
