import SwiftUI

struct SnippetsSettingsView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var snippetsStore: SnippetsStore
    @ObservedObject private var keywordListener = AppCore.shared.snippetListener

    @State private var editor: EditorTarget?
    @State private var pendingDeletion: StoredSnippet?

    var body: some View {
        SettingsPane(
            title: "Snippets",
            subtitle:
                "Create reusable text templates and expand them from the launcher or with a keyword."
        ) {
            keywordExpansionCard
            snippetsCard
            libraryNotices
        }
        .sheet(item: $editor) { target in
            SnippetEditorSheet(record: target.record)
        }
        .alert(item: $pendingDeletion) { record in
            Alert(
                title: Text("Delete “\(record.snippet.name)”?"),
                message: Text(
                    "This removes \(record.fileURL.lastPathComponent) from your snippets folder."),
                primaryButton: .destructive(Text("Delete")) {
                    delete(record)
                },
                secondaryButton: .cancel())
        }
    }

    private var keywordExpansionCard: some View {
        SettingsCard(header: "Automatic Expansion") {
            SettingsRow(
                title: "Expand keywords while typing",
                subtitle: keywordExpansionSubtitle,
                systemImage: "keyboard",
                tint: .green,
                statusDot: keywordExpansionStatusDot
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    if keywordListener.status == .needsAccessibility {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                    Toggle(
                        "Automatic snippet expansion",
                        isOn: Binding(
                            get: { core.settings.snippetKeywordExpansion },
                            set: { core.setSnippetKeywordExpansion($0) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Automatic snippet expansion")
                    .accessibilityHint(
                        "When enabled, Tinycast recognizes snippet keywords while you type in other apps."
                    )
                }
            }
        }
    }

    private var snippetsCard: some View {
        SettingsCard(header: "Library") {
            if sortedSnippets.isEmpty {
                SettingsRow(
                    title: snippetsStore.state == .loading ? "Loading snippets…" : "No snippets",
                    subtitle: "Add one to make it searchable from the launcher.",
                    systemImage: "doc.text",
                    tint: .secondary
                ) {
                    EmptyView()
                }
            } else {
                ForEach(Array(sortedSnippets.enumerated()), id: \.element.id) { index, record in
                    if index > 0 { SettingsDivider() }
                    SnippetSettingsRow(
                        record: record,
                        onEdit: { editor = EditorTarget(record: record) },
                        onDelete: { pendingDeletion = record })
                }
            }

            SettingsDivider()
            SettingsRow(
                title: "New Snippet",
                subtitle: "Give the snippet a searchable name and an optional expansion keyword.",
                systemImage: "plus.circle",
                tint: .green
            ) {
                Button("Add…") { editor = EditorTarget(record: nil) }
                    .controlSize(.small)
            }

            SettingsDivider()
            SettingsRow(
                title: "Snippets Folder",
                subtitle: "Plain Markdown files in this channel’s Application Support folder.",
                systemImage: "folder",
                tint: .green
            ) {
                Button("Open Folder", action: core.revealSnippetsInFinder)
                    .controlSize(.small)
                    .accessibilityHint("Reveals this Tinycast channel’s snippets folder in Finder.")
            }
        }
    }

    @ViewBuilder
    private var libraryNotices: some View {
        if case .failed(let message) = snippetsStore.state {
            SettingsCallout(
                title: "Couldn’t load the snippet library",
                message: message,
                systemImage: "exclamationmark.triangle",
                tint: .orange
            ) {
                Button("Retry", action: snippetsStore.retry)
                    .accessibilityHint("Tries to load the snippet library again.")
            }
            .accessibilityElement(children: .contain)
        }

        if !snippetsStore.issues.isEmpty {
            SettingsCallout(
                title: snippetIssueTitle,
                message: snippetIssueMessage,
                systemImage: "doc.badge.ellipsis",
                tint: .orange
            ) {
                Button("Retry", action: snippetsStore.retry)
                    .accessibilityHint("Reloads snippet files after you fix them on disk.")
            }
            .accessibilityElement(children: .contain)
        }

        // The editor shows its own save failures inline, so this covers the ones with no sheet behind them (deleting from the list).
        if editor == nil, let operationError = snippetsStore.operationError {
            SettingsCallout(
                title: "The snippet operation failed",
                message: operationError,
                systemImage: "exclamationmark.triangle",
                tint: .red
            )
            .accessibilityElement(children: .contain)
        }
    }

    private var sortedSnippets: [StoredSnippet] {
        snippetsStore.snippets.sorted {
            $0.snippet.name.localizedCaseInsensitiveCompare($1.snippet.name) == .orderedAscending
        }
    }

    private var snippetIssueTitle: String {
        let count = snippetsStore.issues.count
        return count == 1
            ? "1 snippet file couldn’t be loaded" : "\(count) snippet files couldn’t be loaded"
    }

    private var snippetIssueMessage: String {
        let first = snippetsStore.issues[0]
        if snippetsStore.issues.count == 1 {
            return "\(first.fileURL.lastPathComponent): \(first.message)"
        }
        return
            "\(first.fileURL.lastPathComponent): \(first.message) Plus \(snippetsStore.issues.count - 1) more."
    }

    private var keywordExpansionStatusDot: Color? {
        switch keywordListener.status {
        case .off: return nil
        case .needsAccessibility: return .orange
        case .active: return .green
        }
    }

    private var keywordExpansionSubtitle: String {
        switch keywordListener.status {
        case .off:
            return "Off. Enable to recognize snippet keywords in other apps."
        case .needsAccessibility:
            return "Needs the Accessibility permission, the same one pasting uses."
        case .active:
            return "Active. Keystrokes are matched locally in memory and are never stored."
        }
    }

    private func delete(_ record: StoredSnippet) {
        Task { try? await snippetsStore.delete(id: record.id) }
    }
}

private struct EditorTarget: Identifiable {
    let id = UUID()
    /// nil for a snippet that has no file yet.
    let record: StoredSnippet?
}

private struct SnippetSettingsRow: View {
    let record: StoredSnippet
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: Theme.Size.settingsRowIcon)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(record.snippet.name)
                    .font(.body)
                    .lineLimit(1)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(metadata)
            }

            Spacer(minLength: Theme.Spacing.lg)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Snippet")
            .accessibilityLabel("Edit \(record.snippet.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Snippet")
            .accessibilityLabel("Delete \(record.snippet.name)")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var metadata: String {
        let filename = record.fileURL.lastPathComponent
        guard let keyword = record.snippet.keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
            !keyword.isEmpty
        else { return filename }
        return "\(keyword) · \(filename)"
    }
}

private struct SnippetEditorSheet: View {
    /// nil while adding; otherwise the record whose file (and revision) the save targets.
    let record: StoredSnippet?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTemplateFocused: Bool
    @State private var name: String
    @State private var keyword: String
    @State private var text: String
    @State private var selection: TextSelection?
    @State private var isEnabled: Bool
    @State private var showInLauncher: Bool
    @State private var showsConfirmation: Bool
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(record: StoredSnippet?) {
        self.record = record
        let snippet = record?.snippet
        _name = State(initialValue: snippet?.name ?? "")
        _keyword = State(initialValue: snippet?.keyword ?? "")
        _text = State(initialValue: snippet?.text ?? "")
        _isEnabled = State(initialValue: snippet?.isEnabled ?? true)
        _showInLauncher = State(initialValue: snippet?.showInLauncher ?? true)
        _showsConfirmation = State(initialValue: snippet?.showsConfirmation ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(record == nil ? "Add Snippet" : "Edit Snippet")
                .font(.title2.weight(.bold))

            field(
                title: "Name", placeholder: "Email Sign-off", text: $name,
                hint: "Required. Shown in the library and launcher.")
            field(
                title: "Keyword", placeholder: "Optional, for example !notes", text: $keyword,
                hint: "Optional. Type this to expand the snippet.")

            templateEditor

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                optionToggle(
                    "Enabled", isOn: $isEnabled,
                    detail: "Disabled snippets cannot be expanded.")
                optionToggle(
                    "Show in Launcher", isOn: $showInLauncher,
                    detail: "Find this snippet in launcher search.")
                optionToggle(
                    "Show confirmation", isOn: $showsConfirmation,
                    detail: "Flash a confirmation on screen when it runs.")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Template")
                    .font(.callout.weight(.medium))
                Spacer()
                placeholderMenu
            }
            TextEditor(text: $text, selection: $selection)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.sm)
                .frame(height: Theme.Size.editorTextHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
                .focused($isTemplateFocused)
                .accessibilityLabel("Snippet template")
                .accessibilityHint("Enter the text Tinycast expands.")
        }
    }

    /// Every placeholder the engine understands. Parameters and modifiers (`offset=`, `| uppercase`) are documented rather than listed here — see docs/snippets.md.
    private var placeholderMenu: some View {
        Menu("Insert…") {
            Section("Text") {
                placeholderItem("{cursor}")
                placeholderItem("{clipboard}")
                placeholderItem("{selection}")
                placeholderItem("{uuid}")
            }
            Section("Date & Time") {
                placeholderItem("{date}")
                placeholderItem("{time}")
                placeholderItem("{datetime}")
                placeholderItem("{day}")
            }
            Section("Arguments") {
                placeholderItem("{argument name=\"Name\"}")
            }
            Section("Snippets") {
                placeholderItem("{snippet name=\"Name\"}")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Insert a placeholder")
    }

    private func placeholderItem(_ token: String) -> some View {
        Button(token) { insert(token) }
    }

    /// Replaces the selection, or lands at the caret; appends when there is no usable one (the menu can be used before the editor is ever focused).
    private func insert(_ token: String) {
        if let selection, case .selection(let range) = selection.indices,
            range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex
        {
            text.replaceSubrange(range, with: token)
        } else {
            text += token
        }
        // Those indices belong to the string we just replaced, so they must not survive into the next insert.
        selection = nil
        isTemplateFocused = true
    }

    private func field(
        title: String, placeholder: String, text: Binding<String>, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.callout.weight(.medium))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Snippet \(title.lowercased())")
                .accessibilityHint(hint)
        }
    }

    private func optionToggle(
        _ title: String, isOn: Binding<Bool>, detail: String
    ) -> some View {
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

    private var draft: Snippet {
        Snippet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text,
            keyword: trimmedOrNil(keyword),
            isEnabled: isEnabled,
            showInLauncher: showInLauncher,
            showsConfirmation: showsConfirmation)
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            let store = AppCore.shared.snippetsStore
            do {
                // Saving keeps the file and its revision, so an external edit in between is reported as a conflict rather than overwritten.
                if var updated = record {
                    updated.snippet = draft
                    try await store.save(updated)
                } else {
                    try await store.create(draft)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
