import AppKit
import SwiftUI

/// The Layout row: an add button beside the dropdown naming the entry every field below edits.
struct WindowLayoutEntryPicker: View {
    let draft: WindowLayoutDraft
    let displays: [WindowLayoutDisplay]

    @Environment(AppIndex.self) private var appIndex
    @State private var showingAppPicker = false
    @State private var showingEntries = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            addButton
            entryButton
        }
    }

    private var addButton: some View {
        Button {
            showingAppPicker = true
        } label: {
            Image(systemName: "plus")
                .font(Theme.Typography.keyCap.weight(.semibold))
                .frame(width: Theme.Size.layoutControlHeight - Theme.Spacing.xl)
                .layoutFieldChrome()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add an app to this layout")
        .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
            AppPickerPopover { bundleID in
                showingAppPicker = false
                guard let bundleID, let display = targetDisplay else { return }
                draft.addEntry(bundleID: bundleID, on: display)
            }
        }
    }

    /// A button and a popover, not a `Menu`: a menu label stretches an `NSImage` out of aspect.
    private var entryButton: some View {
        Button {
            showingEntries = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if let entry = draft.selectedEntry {
                    let app = AppPresentation.resolve(bundleID: entry.bundleID, in: appIndex)
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                    Text(app.name).lineLimit(1)
                } else {
                    Text("No app yet").foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.disclosure)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .layoutFieldChrome()
        }
        .buttonStyle(.plain)
        .disabled(draft.entries.isEmpty)
        .accessibilityLabel("Entry being edited")
        .popover(isPresented: $showingEntries, arrowEdge: .bottom) { entryList }
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(draft.tabs(connected: displays), id: \.uuid) { display in
                let entries = draft.entries(onDisplay: display.uuid)
                if !entries.isEmpty {
                    Text(display.name)
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.md)
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
            if draft.selectedEntry != nil {
                Divider()
                Button("Remove This Entry", role: .destructive) {
                    showingEntries = false
                    draft.removeSelectedEntry()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Size.layoutControlHeight, alignment: .leading)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Theme.Size.layoutEntryPopover)
    }

    private func row(_ entry: WindowLayoutEntry) -> some View {
        let app = AppPresentation.resolve(bundleID: entry.bundleID, in: appIndex)
        let isSelected = entry.id == draft.selectedEntryID
        return Button {
            showingEntries = false
            draft.select(entryID: entry.id)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                Text(app.name).lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if isSelected {
                    Image(systemName: "checkmark").font(Theme.Typography.disclosure)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Theme.Size.layoutControlHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(isSelected ? Theme.Colors.selection : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private var targetDisplay: WindowLayoutDisplay? {
        draft.tabs(connected: displays).first { $0.uuid == draft.selectedDisplayUUID }
            ?? displays.first
    }
}
