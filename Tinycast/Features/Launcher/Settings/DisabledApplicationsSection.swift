import SwiftUI

/// The excluded-apps list a feature offers: rows with a remove button, and a picker below.
struct DisabledApplicationsSection: View {
    @Binding var bundleIDs: [String]
    let anchor: SettingsAnchor
    let footer: String

    @State private var picking = false

    var body: some View {
        Section {
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
