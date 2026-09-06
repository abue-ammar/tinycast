import AppKit
import SwiftUI

/// The editor's right column. Stacks the field groups; holds no geometry of its own.
struct WindowLayoutInspector: View {
    let draft: WindowLayoutDraft
    let displays: [WindowLayoutDisplay]

    @Environment(AppIndex.self) private var appIndex
    @State private var showingIconPicker = false
    @State private var showingAppPicker = false

    private static let iconSymbols = [
        "macwindow.on.rectangle", "macwindow", "square.grid.2x2", "rectangle.split.2x1",
        "rectangle.split.3x1", "sidebar.left", "display", "display.2", "laptopcomputer",
        "desktopcomputer", "briefcase", "hammer", "chevron.left.forwardslash.chevron.right",
        "paintbrush", "calendar", "video", "chart.bar", "terminal", "globe", "envelope",
        "message", "music.note", "book", "person.2"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            nameField
            gapToggle
            entryPicker
            if draft.selectedEntry != nil {
                argumentField
                sizeFields
                offsetFields
                positionField
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Layout-wide

    private var nameField: some View {
        @Bindable var draft = draft
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Name")
                .font(.callout.weight(.medium))
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Office", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                Button {
                    showingIconPicker = true
                } label: {
                    SymbolImage(name: draft.symbol, size: 14)
                }
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
        }
    }

    private var gapToggle: some View {
        @Bindable var draft = draft
        return Toggle(isOn: $draft.usesPreferredGap) {
            Text("Use preferred gap settings")
            Text("Inset every window by the gap set above, as the tiling commands do.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - The entry being edited

    private var entryPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Layout")
                .font(.callout.weight(.medium))
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    showingAppPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add an app to this layout")
                .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
                    AppPickerPopover { bundleID in
                        showingAppPicker = false
                        guard let bundleID, let display = targetDisplay else { return }
                        draft.addEntry(bundleID: bundleID, on: display)
                    }
                }
                entryMenu
            }
        }
    }

    /// A `Menu`, not a `Picker`: a stock picker draws no app icon and cannot group by display.
    private var entryMenu: some View {
        Menu {
            ForEach(draft.tabs(connected: displays), id: \.uuid) { display in
                Section(display.name) {
                    ForEach(draft.entries(onDisplay: display.uuid)) { entry in
                        Button(appName(entry.bundleID)) { draft.select(entryID: entry.id) }
                    }
                }
            }
            if draft.selectedEntry != nil {
                Divider()
                Button("Remove This Entry", role: .destructive) { draft.removeSelectedEntry() }
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if let entry = draft.selectedEntry {
                    let app = AppPresentation.resolve(bundleID: entry.bundleID, in: appIndex)
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(app.name).lineLimit(1)
                } else {
                    Text("No app yet").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .disabled(draft.entries.isEmpty)
    }

    private var argumentField: some View {
        WindowLayoutArgumentField(draft: draft)
    }

    private var sizeFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Size")
                .font(.callout.weight(.medium))
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
            Text("Offset")
                .font(.callout.weight(.medium))
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
            Text("Position")
                .font(.callout.weight(.medium))
            WindowLayoutPositionGrid(selection: entry.anchor, onSelect: draft.setAnchor)
        }
    }

    // MARK: - Helpers

    /// Safe: every caller is behind a `draft.selectedEntry != nil` check.
    private var entry: WindowLayoutEntry {
        draft.selectedEntry ?? WindowLayoutEntry(bundleID: "", display: .init(uuid: "", name: ""))
    }

    private var targetDisplay: WindowLayoutDisplay? {
        draft.tabs(connected: displays).first { $0.uuid == draft.selectedDisplayUUID }
            ?? displays.first
    }

    private func appName(_ bundleID: String) -> String {
        AppPresentation.resolve(bundleID: bundleID, in: appIndex).name
    }
}
