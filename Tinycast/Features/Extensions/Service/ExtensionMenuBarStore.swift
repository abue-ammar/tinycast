import Foundation
import os

@MainActor
@Observable
final class ExtensionMenuBarStore {
    struct Record: Codable, Equatable {
        var snapshot: ExtensionMenuBarSnapshot?
        var nextRefresh: Date?
    }

    private(set) var records: [String: Record]
    private let file: URL

    init(file: URL) {
        self.file = file
        records = (try? Data(contentsOf: file)).flatMap {
            try? JSONDecoder().decode([String: Record].self, from: $0)
        } ?? [:]
    }

    func set(_ record: Record?, for entryID: String) {
        guard records[entryID] != record else { return }
        records[entryID] = record
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: file, options: .atomic)
        } catch {
            Logger(subsystem: "com.tinycast", category: "extension-menu-bar")
                .error("Could not save menu bar items: \(error.localizedDescription, privacy: .public)")
        }
    }
}
