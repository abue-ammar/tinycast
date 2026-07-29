import AppKit
import Combine
import SwiftUI

@MainActor
final class SnippetEditingSession: ObservableObject {
    enum Selection: Hashable {
        case none
        case new
        case stored(StoredSnippet.ID)
    }

    enum ExternalChange: Equatable {
        case modified(StoredSnippet)
        case removed
    }

    private enum FailedAction {
        case save
        case saveAsNew
        case delete
    }

    @Published private(set) var draft: Snippet?
    @Published private(set) var sourceRecord: StoredSnippet?
    @Published private(set) var isNew = false
    @Published private(set) var externalChange: ExternalChange?
    @Published private(set) var operationError: String?
    @Published private(set) var isSaving = false
    @Published private(set) var isDeleting = false

    private let store: SnippetsStore
    private var baseline: Snippet?
    private var failedAction: FailedAction?
    private var hasStarted = false

    init(store: SnippetsStore) {
        self.store = store
    }

    var selection: Selection {
        if isNew { return .new }
        if let sourceRecord { return .stored(sourceRecord.id) }
        return .none
    }

    var isDirty: Bool {
        guard let draft else { return false }
        if isNew { return true }
        return draft != baseline
    }

    var canRevert: Bool {
        guard let draft, let baseline else { return false }
        return draft != baseline && !isBusy && externalChange == nil
    }

    var canSave: Bool {
        guard let draft else { return false }
        return isDirty
            && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
            && externalChange == nil
    }

    var isBusy: Bool { isSaving || isDeleting }
    var canDelete: Bool { sourceRecord != nil && !isBusy && externalChange == nil }
    var canRetry: Bool { failedAction != nil && !isBusy }

    var selectedFilename: String? {
        if isNew { return "Not saved yet" }
        return sourceRecord?.fileURL.lastPathComponent
    }

    func start(records: [StoredSnippet]) {
        guard !hasStarted else {
            reconcile(records: records)
            return
        }
        hasStarted = true
        selectFirst(in: records)
    }

    func reconcile(records: [StoredSnippet]) {
        guard !isSaving, !isDeleting else { return }
        guard let sourceRecord else {
            if draft == nil, !isNew { selectFirst(in: records) }
            return
        }

        guard let current = records.first(where: { $0.id == sourceRecord.id }) else {
            if isDirty {
                externalChange = .removed
                clearError()
            } else {
                selectFirst(in: records)
            }
            return
        }
        if current.sourceRevision == sourceRecord.sourceRevision {
            if externalChange != nil {
                self.sourceRecord = current
                externalChange = nil
                clearError()
            }
            return
        }

        if isDirty {
            externalChange = .modified(current)
            clearError()
        } else {
            adopt(current)
        }
    }

    func select(_ selection: Selection, records: [StoredSnippet]) {
        switch selection {
        case .none:
            clear()
        case .new:
            beginNew(records: records)
        case .stored(let id):
            guard let record = records.first(where: { $0.id == id }) else { return }
            adopt(record)
        }
    }

    func beginNew(records: [StoredSnippet]) {
        let snippet = Snippet(name: uniqueNewSnippetName(in: records), text: "")
        sourceRecord = nil
        baseline = snippet
        draft = snippet
        isNew = true
        externalChange = nil
        clearError()
    }

    func update<Value>(_ keyPath: WritableKeyPath<Snippet, Value>, to value: Value) {
        draft?[keyPath: keyPath] = value
        clearError()
    }

    func appendToText(_ value: String) {
        draft?.text += value
        clearError()
    }

    func revert() {
        guard let baseline else { return }
        draft = baseline
        clearError()
    }

    @discardableResult
    func save() async -> Bool {
        guard let draft, !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            operationError = "Enter a name before saving this snippet."
            return false
        }
        if isNew { return await saveAsNew() }
        guard var record = sourceRecord, externalChange == nil else { return false }

        record.snippet = draft
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await store.save(record)
            adopt(saved)
            return true
        } catch {
            operationError = error.localizedDescription
            failedAction = .save
            store.retry()
            return false
        }
    }

    @discardableResult
    func saveAsNew() async -> Bool {
        guard let draft, !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            operationError = "Enter a name before saving this snippet."
            return false
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await store.create(draft)
            adopt(saved)
            return true
        } catch {
            operationError = error.localizedDescription
            failedAction = .saveAsNew
            return false
        }
    }

    @discardableResult
    func delete() async -> Bool {
        guard let id = sourceRecord?.id, externalChange == nil else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await store.delete(id: id)
            selectFirst(in: store.snippets)
            return true
        } catch {
            operationError = error.localizedDescription
            failedAction = .delete
            store.retry()
            return false
        }
    }

    func retryLastOperation() async {
        switch failedAction {
        case .save:
            _ = await save()
        case .saveAsNew:
            _ = await saveAsNew()
        case .delete:
            _ = await delete()
        case nil:
            break
        }
    }

    func reloadExternal() {
        guard case .modified(let record) = externalChange else { return }
        adopt(record)
    }

    func keepEditingExternal() {
        guard case .modified(let record) = externalChange else { return }
        sourceRecord = record
        baseline = record.snippet
        isNew = false
        externalChange = nil
        clearError()
    }

    func discardRemovedDraft(records: [StoredSnippet]) {
        guard externalChange == .removed else { return }
        selectFirst(in: records)
    }

    func prepareForDeparture() async -> Bool {
        guard !isBusy else { return false }

        switch externalChange {
        case .modified(let record):
            switch Self.externalModificationAlert(name: draft?.name ?? record.snippet.name) {
            case .alertFirstButtonReturn:
                adopt(record)
                return true
            case .alertSecondButtonReturn:
                keepEditingExternal()
                return false
            default:
                return false
            }
        case .removed:
            switch Self.externalRemovalAlert(name: draft?.name ?? "this snippet") {
            case .alertFirstButtonReturn:
                return await saveAsNew()
            case .alertSecondButtonReturn:
                selectFirst(in: store.snippets)
                return true
            default:
                return false
            }
        case nil:
            break
        }

        guard isDirty else { return true }
        switch Self.unsavedChangesAlert(name: draft?.name ?? "this snippet") {
        case .alertFirstButtonReturn:
            return await save()
        case .alertSecondButtonReturn:
            if isNew {
                selectFirst(in: store.snippets)
            } else {
                revert()
            }
            return true
        default:
            return false
        }
    }

    func requestWindowClose(completion: @escaping (Bool) -> Void) -> Bool {
        guard isDirty || externalChange != nil else { return true }
        Task { completion(await prepareForDeparture()) }
        return false
    }

    private func adopt(_ record: StoredSnippet) {
        sourceRecord = record
        baseline = record.snippet
        draft = record.snippet
        isNew = false
        externalChange = nil
        clearError()
    }

    private func selectFirst(in records: [StoredSnippet]) {
        if let first = records.first {
            adopt(first)
        } else {
            clear()
        }
    }

    private func clear() {
        sourceRecord = nil
        baseline = nil
        draft = nil
        isNew = false
        externalChange = nil
        clearError()
    }

    private func clearError() {
        operationError = nil
        failedAction = nil
    }

    private func uniqueNewSnippetName(in records: [StoredSnippet]) -> String {
        let names = Set(records.map { $0.snippet.name.localizedLowercase })
        if !names.contains("new snippet") { return "New Snippet" }
        var suffix = 2
        while names.contains("new snippet \(suffix)") { suffix += 1 }
        return "New Snippet \(suffix)"
    }

    private static func unsavedChangesAlert(name: String) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(name)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save").keyEquivalent = "\r"
        let discard = alert.addButton(withTitle: "Discard Changes")
        discard.hasDestructiveAction = true
        discard.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert.runModal()
    }

    private static func externalModificationAlert(name: String) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "“\(name)” changed on disk"
        alert.informativeText = "Reload the external version, or keep your draft open and review it before saving."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reload").keyEquivalent = "\r"
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert.runModal()
    }

    private static func externalRemovalAlert(name: String) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "The file for “\(name)” was removed or renamed"
        alert.informativeText = "Save your edited draft as a new snippet, discard it, or cancel. Tinycast won’t recreate the missing path."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save as New").keyEquivalent = "\r"
        let discard = alert.addButton(withTitle: "Discard")
        discard.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert.runModal()
    }
}

struct SnippetsSettingsView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var snippetsStore: SnippetsStore
    @ObservedObject var session: SnippetEditingSession
    @ObservedObject private var keywordListener = AppCore.shared.snippetListener

    @State private var editorTarget: SnippetEditorTarget?
    @State private var pendingDeletion: StoredSnippet?
    @State private var isDeletingFromList = false

    var body: some View {
        SettingsPane(
            title: "Snippets",
            subtitle: "Create reusable text templates and expand them from the launcher or with a keyword."
        ) {
            keywordExpansionCard
            hudCard
            snippetsCard
            libraryNotices
        }
        .onAppear {
            session.start(records: snippetsStore.snippets)
        }
        .onChange(of: snippetsStore.snippets) { _, records in
            session.reconcile(records: records)
        }
        .sheet(item: $editorTarget) { target in
            SnippetEditorSheet(
                session: session,
                snippetsStore: snippetsStore,
                target: target,
                onDismiss: { editorTarget = nil })
        }
        .alert(item: $pendingDeletion) { record in
            Alert(
                title: Text("Delete “\(record.snippet.name)”?"),
                message: Text("This removes \(record.fileURL.lastPathComponent) from your snippets folder."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteFromList(record)
                },
                secondaryButton: .cancel())
        }
    }

    private var keywordExpansionCard: some View {
        SettingsCard(header: "AUTOMATIC EXPANSION") {
            SettingsRow(
                title: "Expand keywords while typing",
                subtitle: keywordExpansionSubtitle,
                systemImage: "keyboard",
                tint: .green,
                statusDot: keywordExpansionStatusDot
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    statusBadge
                    Toggle("Automatic snippet expansion", isOn: Binding(
                        get: { core.settings.snippetKeywordExpansion },
                        set: { core.setSnippetKeywordExpansion($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Automatic snippet expansion")
                    .accessibilityHint("When enabled, Tinycast recognizes snippet keywords while you type in other apps.")
                }
            }

            if keywordListener.status == .waitingForPermissions {
                SettingsDivider()
                SettingsRow(
                    title: "Permissions required",
                    subtitle: "Input Monitoring recognizes keywords; Accessibility replaces them with snippet text.",
                    systemImage: "exclamationmark.triangle",
                    tint: .orange
                ) {
                    Button("Open Permissions") {
                        core.showSettings(tab: .permissions)
                    }
                    .accessibilityHint("Reviews unsaved snippet changes before opening Permissions.")
                }
            }
        }
    }

    private var hudCard: some View {
        SettingsCard(header: "INSERTION FEEDBACK") {
            SettingsRow(
                title: "Show insertion HUD",
                subtitle: "Show a brief success overlay only for snippets that also opt in individually.",
                systemImage: "checkmark.rectangle",
                tint: .green
            ) {
                Toggle("Show snippet insertion HUD", isOn: Binding(
                    get: { core.settings.snippetHUD },
                    set: { core.settings.snippetHUD = $0 }
                ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Show snippet insertion HUD")
                    .accessibilityHint("Individual snippets must also enable their HUD option.")
            }
        }
    }

    private var statusBadge: some View {
        Text(keywordExpansionStatusTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(keywordExpansionStatusColor)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Capsule().fill(keywordExpansionStatusColor.opacity(0.14)))
            .accessibilityLabel("Automatic expansion status: \(keywordExpansionStatusTitle)")
    }

    private var keywordExpansionStatusTitle: String {
        switch keywordListener.status {
        case .off: return "Off"
        case .waitingForPermissions: return "Waiting"
        case .active: return "Active"
        }
    }

    private var keywordExpansionStatusColor: Color {
        switch keywordListener.status {
        case .off: return Theme.Colors.textSecondary
        case .waitingForPermissions: return .orange
        case .active: return .green
        }
    }

    private var keywordExpansionSubtitle: String {
        switch keywordListener.status {
        case .off:
            return "Off. Enable to recognize snippet keywords in other apps."
        case .waitingForPermissions:
            return "Waiting for Input Monitoring and Accessibility permissions."
        case .active:
            return "Active. Keystrokes are matched locally in memory and are never stored."
        }
    }

    private var keywordExpansionStatusDot: Color? {
        switch keywordListener.status {
        case .off: return nil
        case .waitingForPermissions: return .orange
        case .active: return .green
        }
    }

    private var snippetsCard: some View {
        SettingsCard(header: "LIBRARY") {
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
                        onEdit: { openEditor(for: record) },
                        onDelete: { pendingDeletion = record })
                }
            }

            SettingsDivider()
            SettingsRow(
                title: "New Snippet",
                subtitle: "Create an in-memory draft; no file is created until you save.",
                systemImage: "plus.circle",
                tint: .green
            ) {
                Button("Add…", action: openNewEditor)
                    .controlSize(.small)
                    .disabled(session.isBusy || isDeletingFromList)
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
        switch snippetsStore.state {
        case .failed(let message):
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
        case .idle, .loading, .ready:
            EmptyView()
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

        if isDeletingFromList {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.small)
                Text("Deleting snippet…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }

        if editorTarget == nil, let operationError = session.operationError {
            SettingsCallout(
                title: "The snippet operation failed",
                message: operationError,
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                Button("Retry") {
                    Task { await session.retryLastOperation() }
                }
                .disabled(!session.canRetry)
                .accessibilityHint("Retries the failed snippet operation.")
            }
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
        return count == 1 ? "1 snippet file couldn’t be loaded" : "\(count) snippet files couldn’t be loaded"
    }

    private var snippetIssueMessage: String {
        let first = snippetsStore.issues[0]
        if snippetsStore.issues.count == 1 {
            return "\(first.fileURL.lastPathComponent): \(first.message)"
        }
        return "\(first.fileURL.lastPathComponent): \(first.message) Plus \(snippetsStore.issues.count - 1) more."
    }

    private func openEditor(for record: StoredSnippet) {
        Task {
            guard await session.prepareForDeparture() else { return }
            let selection = SnippetEditingSession.Selection.stored(record.id)
            session.select(selection, records: snippetsStore.snippets)
            guard session.selection == selection else { return }
            editorTarget = .stored(record.id)
        }
    }

    private func openNewEditor() {
        Task {
            guard await session.prepareForDeparture() else { return }
            session.beginNew(records: snippetsStore.snippets)
            editorTarget = .new()
        }
    }

    private func deleteFromList(_ record: StoredSnippet) {
        Task {
            guard await session.prepareForDeparture() else { return }
            let selection = SnippetEditingSession.Selection.stored(record.id)
            session.select(selection, records: snippetsStore.snippets)
            guard session.selection == selection else { return }
            isDeletingFromList = true
            _ = await session.delete()
            isDeletingFromList = false
        }
    }
}

private enum SnippetEditorTarget: Identifiable {
    case stored(StoredSnippet.ID)
    case new(UUID)

    static func new() -> Self { .new(UUID()) }

    var id: String {
        switch self {
        case .stored(let path): return path
        case .new(let identity): return "new:\(identity.uuidString)"
        }
    }
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
              !keyword.isEmpty else { return filename }
        return "\(keyword) · \(filename)"
    }
}

private struct SnippetEditorSheet: View {
    private enum FocusedField: Hashable {
        case name
        case keyword
        case category
        case template
    }

    @ObservedObject var session: SnippetEditingSession
    @ObservedObject var snippetsStore: SnippetsStore
    let target: SnippetEditorTarget
    let onDismiss: () -> Void

    @FocusState private var focusedField: FocusedField?
    @State private var isRequestingDismissal = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(session.isNew ? "New Snippet" : "Edit Snippet")
                .font(.title2.weight(.bold))

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    notices
                    detailsCard
                    templateCard
                }
                .padding(.vertical, 1)
            }
            .overlayScroller()

            footer
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
        .frame(minHeight: Theme.Size.snippetEditorHeight)
        .onAppear {
            focusedField = .name
        }
        .onChange(of: snippetsStore.snippets) { _, records in
            session.reconcile(records: records)
        }
        .interactiveDismissDisabled(session.isDirty || session.externalChange != nil || session.isBusy)
    }

    private var detailsCard: some View {
        SettingsCard(header: "DETAILS") {
            editorRow(title: "Name", systemImage: "textformat") {
                TextField("Snippet name", text: draftBinding(\.name))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
                    .accessibilityLabel("Snippet name")
                    .accessibilityHint("Required. This name appears in the library and launcher.")
            }
            SettingsDivider()
            editorRow(title: "Keyword", systemImage: "keyboard") {
                TextField("Optional, for example !notes", text: optionalDraftBinding(\.keyword))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .keyword)
                    .accessibilityLabel("Snippet keyword")
                    .accessibilityHint("Optional text that triggers automatic expansion when the feature is active.")
            }
            SettingsDivider()
            editorRow(title: "Category", systemImage: "tag") {
                TextField("Optional", text: optionalDraftBinding(\.category))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .category)
                    .accessibilityLabel("Snippet category")
                    .accessibilityHint("Optional category used when searching snippets.")
            }
            SettingsDivider()
            SettingsRow(
                title: "Enabled",
                subtitle: "Disabled snippets cannot be expanded.",
                systemImage: "checkmark.circle",
                tint: .green
            ) {
                Toggle("Snippet enabled", isOn: draftBinding(\.isEnabled))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Snippet enabled")
            }
            SettingsDivider()
            SettingsRow(
                title: "Show in Launcher",
                subtitle: "Include this snippet in launcher search results.",
                systemImage: "magnifyingglass",
                tint: .green
            ) {
                Toggle("Show snippet in launcher", isOn: draftBinding(\.showInLauncher))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Show snippet in launcher")
                    .accessibilityHint("When enabled, this snippet appears in launcher search results.")
            }
            SettingsDivider()
            SettingsRow(
                title: "Show insertion HUD",
                subtitle: "Also requires the master switch in Snippets Settings.",
                systemImage: "checkmark.rectangle",
                tint: .green
            ) {
                Toggle("Show insertion HUD for this snippet", isOn: draftBinding(\.showHUD))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Show insertion HUD for this snippet")
                    .accessibilityHint("The global insertion HUD setting must also be enabled.")
            }
        }
    }

    private var templateCard: some View {
        SettingsCard(header: "TEMPLATE") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                variableToolbar

                TextEditor(text: draftBinding(\.text))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: Theme.Size.snippetTemplateEditorHeight)
                    .padding(Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
                    .focused($focusedField, equals: .template)
                    .accessibilityLabel("Snippet template")
                    .accessibilityHint("Enter the text Tinycast expands. Variable buttons append template tokens.")
            }
            .padding(Theme.Spacing.xl)
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let operationError = session.operationError {
            SettingsCallout(
                title: "The snippet operation failed",
                message: operationError,
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                Button("Retry") {
                    Task { await session.retryLastOperation() }
                }
                .disabled(!session.canRetry)
                .accessibilityHint("Retries the failed snippet operation.")
            }
        }

        switch session.externalChange {
        case .modified:
            SettingsCallout(
                title: "This snippet changed on disk",
                message: "Reload the external version, or keep your draft and save it against the latest revision.",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .orange
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    Button("Reload", action: session.reloadExternal)
                    Button("Keep Editing", action: session.keepEditingExternal)
                }
            }
        case .removed:
            SettingsCallout(
                title: "This snippet was removed or renamed",
                message: "Your draft is still in memory. Save it as a new file or discard it; Tinycast won’t recreate the missing path.",
                systemImage: "doc.badge.minus",
                tint: .orange
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    Button("Save as New") {
                        Task { _ = await session.saveAsNew() }
                    }
                    Button("Discard", role: .destructive) {
                        session.discardRemovedDraft(records: snippetsStore.snippets)
                        onDismiss()
                    }
                }
            }
        case nil:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if session.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(session.isSaving ? "Saving snippet" : "Deleting snippet")
            }
            Spacer()
            Button("Cancel", action: requestDismissal)
                .keyboardShortcut(.cancelAction)
                .disabled(session.isBusy || isRequestingDismissal)
            Button("Revert", action: session.revert)
                .disabled(!session.canRevert)
                .accessibilityHint("Restores the last loaded or saved version.")
            Button("Save") {
                Task {
                    if await session.save() { onDismiss() }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!session.canSave)
            .accessibilityHint(session.isNew ? "Creates the snippet file for the first time." : "Saves changes to the snippet file.")
        }
    }

    private var variableToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                variableButtons
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    variableButtons
                }
            }
            .accessibilityLabel("Template variables")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var variableButtons: some View {
        variableButton("{cursor}")
        variableButton("{clipboard}")
        variableButton("{date}")
        variableButton("{argument name=\"Name\"}")
        variableButton("{snippet:Name}")
    }

    private func editorRow<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsRow(title: title, systemImage: systemImage, tint: .green) {
            content().frame(maxWidth: .infinity)
        }
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<Snippet, Value>) -> Binding<Value> {
        Binding(
            get: { session.draft![keyPath: keyPath] },
            set: { session.update(keyPath, to: $0) })
    }

    private func optionalDraftBinding(_ keyPath: WritableKeyPath<Snippet, String?>) -> Binding<String> {
        Binding(
            get: { session.draft?[keyPath: keyPath] ?? "" },
            set: { session.update(keyPath, to: $0.isEmpty ? nil : $0) })
    }

    private func variableButton(_ value: String) -> some View {
        Button(value) {
            session.appendToText(value)
            focusedField = .template
        }
        .font(.system(.caption, design: .monospaced))
        .buttonStyle(.bordered)
        .accessibilityLabel("Insert \(value) variable")
        .accessibilityHint("Appends this token to the snippet template.")
    }

    private func requestDismissal() {
        guard !isRequestingDismissal else { return }
        isRequestingDismissal = true
        Task {
            let canDismiss = await session.prepareForDeparture()
            isRequestingDismissal = false
            if canDismiss { onDismiss() }
        }
    }
}
