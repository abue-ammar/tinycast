import Foundation
import Observation

@MainActor
@Observable
final class WindowWorkspaceStore {
    private struct Saved: Codable {
        var selectedID: UUID?
        var workspaces: [WindowWorkspace]
    }

    private let fileURL: URL
    private(set) var workspaces: [WindowWorkspace]
    var selectedID: UUID? { didSet { persist() } }

    init(fileURL: URL = AppPaths.applicationSupport().appending(path: "window-workspaces.json")) {
        self.fileURL = fileURL
        let saved =
            (try? Data(contentsOf: fileURL)).flatMap {
                try? JSONDecoder().decode(Saved.self, from: $0)
            } ?? Saved(selectedID: nil, workspaces: [])
        workspaces = saved.workspaces
        selectedID = saved.selectedID.flatMap { id in
            saved.workspaces.contains(where: { $0.id == id }) ? id : nil
        }
    }

    var selected: WindowWorkspace? {
        guard let selectedID else { return nil }
        return workspaces.first { $0.id == selectedID }
    }

    func save(name: String, windows: [WindowWorkspace.Window]) {
        let workspace = WindowWorkspace(name: name, windows: windows)
        workspaces.append(workspace)
        selectedID = workspace.id
        persist()
    }

    func remove(id: UUID) {
        workspaces.removeAll { $0.id == id }
        if selectedID == id { selectedID = workspaces.first?.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Saved(selectedID: selectedID, workspaces: workspaces))
        else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
