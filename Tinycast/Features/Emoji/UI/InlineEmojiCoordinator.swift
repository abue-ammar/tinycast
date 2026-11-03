import AppKit
import Carbon.HIToolbox

@MainActor
@Observable
final class InlineEmojiCoordinator {
    private static let resultLimit = 6
    private(set) var query = ""
    private(set) var entries: [EmojiEntry] = []
    private(set) var selection = 0
    let listener: InlineEmojiListener
    private let index: EmojiIndex
    private let frequent: FrequentEmojiStore
    private let pinned: PinnedEmojiStore
    private let settings: AppSettings
    private let injector: TextInjector
    private let window: InlineEmojiWindowController
    private var target: InlineEmojiTarget?
    private var version: InlineEmojiListener.Version?

    init(
        index: EmojiIndex, frequent: FrequentEmojiStore, pinned: PinnedEmojiStore,
        settings: AppSettings, injector: TextInjector, listener: InlineEmojiListener,
        window: InlineEmojiWindowController
    ) {
        self.index = index
        self.frequent = frequent
        self.pinned = pinned
        self.settings = settings
        self.injector = injector
        self.listener = listener
        self.window = window
    }

    func applyEnabled() {
        guard settings.inlineEmojiEnabled else { stop(); return }
        listener.start { [weak self] message in await self?.receive(message) }
    }

    func stop() {
        listener.stop()
        dismiss()
    }

    func dismiss() {
        window.hide()
        listener.setPanelBounds(nil)
        target = nil
        version = nil
        entries = []
        selection = 0
    }

    func select(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        selection = index
    }

    func insertSelection() {
        guard let target, let version, entries.indices.contains(selection), listener.isCurrent(version),
            target.matches(query: query)
        else { listener.reset(); dismiss(); return }
        let entry = entries[selection]
        let keyword = ":" + query
        listener.finishSelection(version: version)
        dismiss()
        injector.replaceTypedText(
            entry.display(tone: settings.emojiSkinTone), keyword: keyword, in: target.app,
            isValid: { [weak self] in
                guard let self else { return false }
                return self.settings.inlineEmojiEnabled && self.listener.isCurrent(version)
                    && !IsSecureEventInputEnabled() && target.isFocused()
            },
            matchesKeyword: { target.matches(query: String(keyword.dropFirst())) },
            onDelivered: { [frequent] in frequent.record(entry.glyph) })
    }

    private func receive(_ message: InlineEmojiListener.Message) async {
        guard settings.inlineEmojiEnabled, listener.isCurrent(message.version) else { return }
        switch message.effect {
        case .search(let query):
            await show(query: query, version: message.version)
        case .move(let offset):
            guard !entries.isEmpty else { return }
            selection = min(max(selection + offset, 0), entries.count - 1)
        case .insert(let query):
            guard self.query == query else { return }
            version = message.version
            insertSelection()
        case .dismiss:
            dismiss()
        }
    }

    private func show(query: String, version: InlineEmojiListener.Version) async {
        for _ in 0..<8 {
            guard !Task.isCancelled, settings.inlineEmojiEnabled, listener.isCurrent(version) else { return }
            if let captured = InlineEmojiTarget.capture(query: query) {
                if let target,
                    target.app.processIdentifier != captured.app.processIdentifier
                        || !CFEqual(target.element, captured.element) || target.start != captured.start
                {
                    listener.reset(); dismiss(); return
                }
                target = captured
                self.query = query
                self.version = version
                entries = suggestions(for: query)
                selection = 0
                window.show(coordinator: self, settings: settings, caret: captured.caret)
                listener.setHasResults(!entries.isEmpty, version: version)
                return
            }
            do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
        }
        guard listener.isCurrent(version) else { return }
        listener.reset()
        dismiss()
    }

    private func suggestions(for query: String) -> [EmojiEntry] {
        guard query.isEmpty else { return index.search(query, frequent: frequent, limit: Self.resultLimit) }
        let glyphs =
            settings.inlineEmojiSuggestions == .pinned ? pinned.glyphs : frequent.top(Self.resultLimit)
        return Array(glyphs.compactMap { index.entry(for: $0) }.prefix(Self.resultLimit))
    }
}
