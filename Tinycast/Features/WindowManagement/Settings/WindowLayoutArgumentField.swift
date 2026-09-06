import AppKit
import SwiftUI

/// The Argument row: none, a file, a folder, a URL, or one of the user's quicklinks.
struct WindowLayoutArgumentField: View {
    let draft: WindowLayoutDraft

    @Environment(QuicklinkStore.self) private var quicklinks
    @State private var isEditingURL = false
    @State private var urlText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Argument")
                .font(.callout.weight(.medium))
            menu
            if isEditingURL {
                TextField("https://example.com", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { draft.setArgument(urlText) }
            }
        }
    }

    private var menu: some View {
        Menu {
            Button("None") { clear() }
            Button("Choose File…") { choose(directories: false) }
            Button("Choose Folder…") { choose(directories: true) }
            Button("Enter URL…") {
                urlText = draft.selectedEntry?.argument ?? ""
                isEditingURL = true
            }
            if !quicklinks.quicklinks.isEmpty {
                // The link is copied, not referenced: a run is one non-interactive pass, and a
                // quicklink that later grows a placeholder would have nothing to prompt with.
                Section("Quicklinks") {
                    ForEach(quicklinks.quicklinks) { quicklink in
                        Button(quicklink.name) {
                            isEditingURL = false
                            draft.setArgument(quicklink.link)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if let argument = draft.selectedEntry?.argument,
                    let destination = QuicklinkDestination.detect(argument)
                {
                    Image(systemName: destination.defaultSymbol)
                    Text(destination.displayText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("None").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func clear() {
        isEditingURL = false
        urlText = ""
        draft.setArgument(nil)
    }

    private func choose(directories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        // An accessory app's panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isEditingURL = false
        draft.setArgument((url.path as NSString).abbreviatingWithTildeInPath)
    }
}
