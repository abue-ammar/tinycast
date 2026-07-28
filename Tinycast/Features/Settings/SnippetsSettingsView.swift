import SwiftUI

struct SnippetsSettingsView: View {
    @EnvironmentObject var snippetsStore: SnippetsStore
    @State private var selectedSnippetID: UUID?
    @State private var searchText = ""

    init() {}

    var body: some View {
        HStack(spacing: 0) {
            // Snippets List Sidebar
            VStack(spacing: 0) {
                searchHeader

                List(filteredSnippets, selection: $selectedSnippetID) { snippet in
                    SnippetRow(snippet: snippet)
                        .tag(snippet.id)
                }
                .listStyle(.sidebar)

                sidebarFooter
            }
            .frame(width: 220)

            Divider()

            // Snippet Detail Editor
            Group {
                if let selectedSnippet {
                    SnippetDetailEditor(snippet: selectedSnippet, onSave: { updated in
                        snippetsStore.update(updated)
                    })
                    .id(selectedSnippet.id)
                } else {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select or create a snippet")
                            .font(Theme.Typography.rowTitle)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedSnippetID == nil {
                selectedSnippetID = snippetsStore.snippets.first?.id
            }
        }
    }

    private var selectedSnippet: Snippet? {
        snippetsStore.snippets.first(where: { $0.id == selectedSnippetID })
    }

    private var filteredSnippets: [Snippet] {
        if searchText.isEmpty {
            return snippetsStore.snippets
        } else {
            return snippetsStore.snippets.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.keyword?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.category?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

    private var searchHeader: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search snippets…", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(Theme.Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sidebarFooter: some View {
        HStack {
            Button(action: createNewSnippet) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)

            Button(action: deleteSelectedSnippet) {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .disabled(selectedSnippetID == nil)

            Spacer()

            Button(action: {
                snippetsStore.revealInFinder()
            }) {
                Label("Open Folder", systemImage: "folder")
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.brand)
            .help("Open ~/.config/tinycast/snippets/ in Finder")
        }
        .padding(Theme.Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func createNewSnippet() {
        let newSnippet = Snippet(name: "New Snippet", text: "Hello {cursor}", keyword: "!new")
        snippetsStore.add(newSnippet)
        selectedSnippetID = newSnippet.id
    }

    private func deleteSelectedSnippet() {
        guard let id = selectedSnippetID else { return }
        snippetsStore.delete(id: id)
        selectedSnippetID = snippetsStore.snippets.first?.id
    }
}

private struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                if let kw = snippet.keyword, !kw.isEmpty {
                    Text(kw)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.brand)
                        .lineLimit(1)
                } else {
                    Text("Not defined")
                        .font(.system(size: 11).italic())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SnippetDetailEditor: View {
    @State var snippet: Snippet
    var onSave: (Snippet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header Section
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.name.isEmpty ? "Untitled Snippet" : snippet.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                    if let kw = snippet.keyword, !kw.isEmpty {
                        Text(kw)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.Colors.brand)
                    } else {
                        Text("Not defined")
                            .font(.system(size: 11).italic())
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }

            Divider()

            // Form Fields
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("Name", text: $snippet.name)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keyword (auto-expansion)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("e.g. !notes", text: Binding(
                            get: { snippet.keyword ?? "" },
                            set: { snippet.keyword = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Category")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("e.g. Work", text: Binding(
                            get: { snippet.category ?? "" },
                            set: { snippet.category = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            // Behavior Settings - Uniform macOS Toggles
            HStack(spacing: Theme.Spacing.xl) {
                Toggle("Enabled", isOn: $snippet.isEnabled)
                    .toggleStyle(.switch)
                    .fixedSize()

                Toggle("Show in Launcher search", isOn: $snippet.showInLauncher)
                    .toggleStyle(.switch)
                    .fixedSize()

                Spacer()
            }
            .padding(.vertical, 4)

            Divider()

            // Variable toolbar and spacious template editor
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Template Content")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        variableButton("{cursor}")
                        variableButton("{clipboard}")
                        variableButton("{date}")
                        variableButton("{argument name=\"Name\"}")
                        variableButton("{snippet:Name}")
                    }
                }

                TextEditor(text: $snippet.text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }
        }
        .padding(Theme.Spacing.lg)
        .onChange(of: snippet) { _, newValue in
            onSave(newValue)
        }
    }

    private func variableButton(_ tag: String) -> some View {
        Button(tag) {
            snippet.text += tag
        }
        .font(.system(size: 10, design: .monospaced))
        .buttonStyle(.bordered)
    }
}
