import SwiftUI

/// The excluded-apps control: one row per exclusion, then the picker that adds another. The caller
/// owns the label above it, so a pane can seat the list beside the command the exclusions belong to.
struct DisabledApplicationsList: View {
    @Binding var bundleIDs: [String]

    @State private var picking = false

    var body: some View {
        ForEach(bundleIDs, id: \.self) { bundleID in
            DisabledAppRow(bundleID: bundleID) {
                bundleIDs.removeAll { $0 == bundleID }
            }
        }

        Button("Add Application…") { picking = true }
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                AppPickerPopover(excluded: Set(bundleIDs)) { bundleID in
                    if let bundleID { bundleIDs.append(bundleID) }
                    picking = false
                }
            }
    }
}

/// A whole section of them, for a pane whose exclusions are a subject of their own.
struct DisabledApplicationsSection: View {
    @Binding var bundleIDs: [String]
    let anchor: SettingsAnchor
    let footer: String

    var body: some View {
        Section {
            DisabledApplicationsList(bundleIDs: $bundleIDs)
        } header: {
            SettingsSectionHeader(anchor)
        } footer: {
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One excluded app; only the bundle ID is stored, so name and icon resolve on the fly.
private struct DisabledAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    @Environment(AppIndex.self) private var appIndex

    var body: some View {
        let (name, icon) = AppPresentation.resolve(bundleID: bundleID, in: appIndex)
        LabeledContent {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop excluding \(name)")
        } label: {
            Label {
                Text(name).lineLimit(1)
            } icon: {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
        }
    }
}
