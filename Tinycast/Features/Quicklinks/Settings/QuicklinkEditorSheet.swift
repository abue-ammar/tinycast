import AppKit
import SwiftUI

/// Identifies the editor to present; nil is "add", and the UUID keeps two opens distinct.
struct QuicklinkEditRequest: Identifiable {
    let id = UUID()
    var quicklink: Quicklink?
}

/// Add / edit sheet for a single quicklink, presented from the Quicklinks pane.
struct QuicklinkEditorSheet: View {
    let quicklink: Quicklink?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppIndex.self) private var appIndex
    @Environment(AppCore.self) private var core
    @State private var name: String
    @State private var link: String
    @State private var iconSymbol: String?
    @State private var openWithBundleID: String?
    @State private var showsInRootSearch: Bool
    @State private var isPinned: Bool
    @State private var errorMessage: String?
    @State private var showingAppPicker = false
    @State private var showingIconPicker = false

    init(quicklink: Quicklink?) {
        self.quicklink = quicklink
        _name = State(initialValue: quicklink?.name ?? "")
        _link = State(initialValue: quicklink?.link ?? "")
        _iconSymbol = State(initialValue: quicklink?.iconSymbol)
        _openWithBundleID = State(initialValue: quicklink?.openWithBundleID)
        _showsInRootSearch = State(initialValue: quicklink?.showsInRootSearch ?? true)
        _isPinned = State(initialValue: quicklink?.isPinned ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(quicklink == nil ? "Add Quicklink" : "Edit Quicklink")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name")
                    .font(.callout.weight(.medium))
                TextField("Search GitHub", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Link")
                        .font(.callout.weight(.medium))
                    Spacer()
                    insertMenu
                }
                TextField("https://github.com/search?q={argument}", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                destinationPreview
            }

            HStack(spacing: Theme.Spacing.xl) {
                iconField
                openWithField
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                optionToggle(
                    "Show in root search", isOn: $showsInRootSearch,
                    detail: "List this quicklink alongside apps and commands.")
                optionToggle(
                    "Pin to top", isOn: $isPinned,
                    detail: "Keep it above the other quicklinks.")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed(name).isEmpty || trimmed(link).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }

    // MARK: - Fields

    /// The destination as it will be opened: all the feedback a templated link can give.
    @ViewBuilder
    private var destinationPreview: some View {
        let value = trimmed(link)
        if value.isEmpty {
            EmptyView()
        } else if QuicklinkDestination.containsPlaceholder(value) {
            Text("Resolved when you open it — placeholders are filled in first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let destination = QuicklinkDestination.detect(value) {
            Label(destination.displayText, systemImage: destination.defaultSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("This doesn't look like a URL, file path, or deeplink.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// Only tokens meaningful in a destination; `{cursor}` and `{snippet:…}` stay literal.
    private var insertMenu: some View {
        Menu("Insert…") {
            Button("Argument") { insert("{argument}") }
            Button("Named Argument") { insert("{argument name=\"Query\"}") }
            Divider()
            Button("Clipboard") { insert("{clipboard}") }
            Button("Selected Text") { insert("{selection}") }
            Divider()
            Button("Date") { insert("{date}") }
            Button("Time") { insert("{time}") }
            Button("Date & Time") { insert("{datetime}") }
            Button("Custom Date Format") { insert("{date format=\"yyyy-MM-dd\"}") }
            Divider()
            Button("UUID") { insert("{uuid}") }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private static let iconSymbols = [
        "globe", "folder", "doc.text", "link", "star", "bookmark", "magnifyingglass", "cart",
        "envelope", "message", "calendar", "clock", "checklist", "chart.bar", "hammer", "wrench",
        "ladybug", "terminal", "chevron.left.forwardslash.chevron.right", "cloud", "server.rack",
        "lock", "person.2", "building.2", "graduationcap", "book", "music.note", "play.rectangle",
        "photo", "paintbrush", "creditcard", "map"
    ]

    private var iconField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Icon")
                .font(.callout.weight(.medium))
            Button {
                showingIconPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: resolvedSymbol, size: 14)
                    Text(iconSymbol == nil ? "Automatic" : "Custom")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: 150)
            }
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                SymbolPicker(
                    selection: $iconSymbol, fallback: automaticSymbol, symbols: Self.iconSymbols
                ) {
                    showingIconPicker = false
                }
            }
        }
    }

    private var openWithField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Open With")
                .font(.callout.weight(.medium))
            Button {
                showingAppPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if let openWithBundleID {
                        let app = AppPresentation.resolve(bundleID: openWithBundleID, in: appIndex)
                        Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                        Text(app.name).lineLimit(1)
                    } else {
                        Text("Default app")
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 180)
            }
            .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
                AppPickerPopover(clearTitle: "Default app") { bundleID in
                    openWithBundleID = bundleID
                    showingAppPicker = false
                }
            }
        }
    }

    private func optionToggle(_ title: String, isOn: Binding<Bool>, detail: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Behaviour

    private var automaticSymbol: String {
        QuicklinkDestination.detect(trimmed(link))?.defaultSymbol ?? Quicklink.sfSymbol
    }

    private var resolvedSymbol: String { iconSymbol ?? automaticSymbol }

    private func insert(_ token: String) {
        link += token
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        // Editing keeps the UUID, and with it the quicklink's shortcut, favorite and visibility.
        let existing = quicklink
        let draft = Quicklink(
            id: existing?.id ?? UUID(), name: name, link: link,
            openWithBundleID: openWithBundleID, iconSymbol: iconSymbol,
            showsInRootSearch: showsInRootSearch,
            // Re-pinning keeps the original stamp, so saving an edit doesn't move the row.
            pinnedAt: isPinned ? (existing?.pinnedAt ?? Date()) : nil,
            createdAt: existing?.createdAt ?? Date())
        do {
            if existing == nil {
                try core.quicklinkCoordinator.addQuicklink(draft)
            } else {
                try core.quicklinkCoordinator.updateQuicklink(draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A small fixed grid, not a symbol browser; "Automatic" is first, being the better default.
