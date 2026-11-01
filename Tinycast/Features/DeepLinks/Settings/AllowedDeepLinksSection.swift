import SwiftUI

/// Commands a link from outside may run unasked; removing one makes its next link ask again.
struct AllowedDeepLinksSection: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        let links = core.deepLinkCoordinator.allowedLinks
        Section {
            if links.isEmpty {
                Text("None. A link from another app or a web page asks before it runs a command.")
                    .foregroundStyle(.secondary)
            }
            ForEach(links) { link in
                LabeledContent {
                    Button {
                        core.deepLinkCoordinator.revoke(link)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ask before a link runs \(link.name)")
                } label: {
                    Text(verbatim: link.name).lineLimit(1)
                }
            }
        } header: {
            SettingsSectionHeader(.generalDeepLinks)
        } footer: {
            Text("Commands you chose Always Allow for when a link asked to run them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
