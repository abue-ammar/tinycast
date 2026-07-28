import Foundation
import Combine
import AppKit

@MainActor
final class SnippetsStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []

    let snippetsDirectory: URL
    nonisolated(unsafe) private var fileSource: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var fileDescriptor: CInt = -1

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.snippetsDirectory = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("tinycast", isDirectory: true)
            .appendingPathComponent("snippets", isDirectory: true)

        try? FileManager.default.createDirectory(at: snippetsDirectory, withIntermediateDirectories: true)

        load()
        startFolderWatcher()
    }

    deinit {
        stopFolderWatcher()
    }

    func load() {
        let fm = FileManager.default

        // Check if directory has markdown files
        let mdFiles = (try? fm.contentsOfDirectory(at: snippetsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "md" } ?? []

        if mdFiles.isEmpty {
            // Check for legacy snippets.json migration
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
            let legacyURL = appSupport.appendingPathComponent(bundleID).appendingPathComponent("snippets.json")

            if fm.fileExists(atPath: legacyURL.path),
               let data = try? Data(contentsOf: legacyURL),
               let legacySnippets = try? JSONDecoder().decode([Snippet].self, from: data) {
                for snippet in legacySnippets {
                    saveSnippetFile(snippet)
                }
            } else {
                createDefaultSnippets()
            }
        }

        // Load all .md files from ~/.config/tinycast/snippets/
        let currentFiles = (try? fm.contentsOfDirectory(at: snippetsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "md" } ?? []

        var loaded: [Snippet] = []
        for url in currentFiles {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let snippet = SnippetMarkdownSerializer.parse(content: content, fileURL: url)
                loaded.append(snippet)
            }
        }

        self.snippets = loaded.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func add(_ snippet: Snippet) {
        saveSnippetFile(snippet)
        load()
    }

    func update(_ snippet: Snippet) {
        saveSnippetFile(snippet)
        load()
    }

    func delete(id: UUID) {
        guard let snippet = snippets.first(where: { $0.id == id }) else { return }
        deleteSnippetFile(snippet)
        load()
    }

    func revealInFinder() {
        NSWorkspace.shared.open(snippetsDirectory)
    }

    private func saveSnippetFile(_ snippet: Snippet) {
        let slug = SnippetMarkdownSerializer.slug(for: snippet.name)
        let fileURL = snippetsDirectory.appendingPathComponent("\(slug).md")
        let content = SnippetMarkdownSerializer.serialize(snippet)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func deleteSnippetFile(_ snippet: Snippet) {
        let slug = SnippetMarkdownSerializer.slug(for: snippet.name)
        let fileURL = snippetsDirectory.appendingPathComponent("\(slug).md")
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func createDefaultSnippets() {
        let defaults = [
            Snippet(
                name: "Email Sign-off",
                text: "Best regards,\n\n{cursor}\n{snippet:My Name}",
                keyword: "!bye",
                category: "Personal"
            ),
            Snippet(
                name: "My Name",
                text: "Alex",
                category: "Personal"
            ),
            Snippet(
                name: "Meeting Notes",
                text: "## Meeting Notes - {date}\n\n**Attendees:** {argument name=\"Attendees\"}\n\n**Action Items:**\n- {cursor}",
                keyword: "!notes",
                category: "Work"
            )
        ]
        for s in defaults {
            saveSnippetFile(s)
        }
    }

    private func startFolderWatcher() {
        stopFolderWatcher()

        fileDescriptor = open(snippetsDirectory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        fileSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )

        fileSource?.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.load()
            }
        }

        fileSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        fileSource?.resume()
    }

    private nonisolated func stopFolderWatcher() {
        if let source = fileSource {
            source.cancel()
            fileSource = nil
        }
    }
}
