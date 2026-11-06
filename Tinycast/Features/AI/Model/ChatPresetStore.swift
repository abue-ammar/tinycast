import Foundation

@MainActor
@Observable
final class ChatPresetStore {
    private(set) var presets: [ChatPreset] = []
    /// False when the file wouldn't read; every mutation then refuses rather than pretends.
    private(set) var isAvailable = true

    private let fileURL: URL

    init(directory: URL? = nil) {
        fileURL = (directory ?? Self.defaultDirectory).appendingPathComponent("chat-presets.json")
    }

    private static var defaultDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    /// Runs each time AI is switched on, so it starts over rather than keep an old refusal.
    func load() {
        presets = []
        isAvailable = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        // A file that exists but won't read is authored data: report, never write over it.
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([ChatPreset].self, from: data)
        else {
            isAvailable = false
            return
        }
        var ids = Set<UUID>()
        presets = decoded.compactMap { try? Self.validated($0) }
            .filter { ids.insert($0.id).inserted }
            .sorted(by: ChatPreset.precedes)
    }

    func preset(id: UUID) -> ChatPreset? {
        presets.first { $0.id == id }
    }

    @discardableResult
    func add(_ draft: ChatPreset) throws(ChatPresetError) -> ChatPreset {
        let value = try Self.validated(draft)
        try commit(presets + [value])
        return value
    }

    func update(_ draft: ChatPreset) throws(ChatPresetError) {
        guard let index = presets.firstIndex(where: { $0.id == draft.id }) else { return }
        var updated = presets
        updated[index] = try Self.validated(draft)
        try commit(updated)
    }

    @discardableResult
    func remove(id: UUID) throws(ChatPresetError) -> ChatPreset? {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = presets
        let removed = updated.remove(at: index)
        try commit(updated)
        return removed
    }

    private static func validated(_ draft: ChatPreset) throws(ChatPresetError) -> ChatPreset {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol = draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        value.iconSymbol = symbol.isEmpty ? nil : symbol
        value.instructions = draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.name.contains("\0") else { throw .invalidCharacter }
        guard !value.instructions.isEmpty else { throw .emptyInstructions }
        return value
    }

    /// Persisted before the list moves, so a save the reader was told landed is on disk.
    private func commit(_ updated: [ChatPreset]) throws(ChatPresetError) {
        guard isAvailable else { throw .storageUnavailable }
        let ordered = updated.sorted(by: ChatPreset.precedes)
        guard ordered != presets else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(ordered),
            (try? data.write(to: fileURL, options: .atomic)) != nil
        else { throw .storageUnavailable }
        presets = ordered
    }
}
