import AppKit
import Carbon.HIToolbox

/// Holds the keyboard input source at the palette's preferred one for the life of one summon.
@MainActor
final class InputSourceSwitcher {
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
    }

    /// Posted by TIS when a keyboard source is added or removed in System Settings.
    static let sourcesDidChange = Notification.Name(
        kTISNotifyEnabledKeyboardInputSourcesChanged as String)

    /// The source to restore is kept as the object TIS vended, so hiding never re-reads the list.
    private struct Session {
        let previousSource: TISInputSource
        let preferredInputSourceID: String
        var applied = false
    }

    private var session: Session?

    /// Every enabled keyboard source; a `selected` one that is gone stays listed, so Settings keeps it.
    func options(selecting selected: String?) -> [Option] {
        var options = Self.enabledKeyboardSources().compactMap(Self.option(for:))
        if let selected, !options.contains(where: { $0.id == selected }) {
            options.append(Option(id: selected, title: selected))
        }
        return options
    }

    /// Records what to go back to; skipped when the preferred source is already the active one.
    func beginSession(preferredInputSourceID: String?) {
        guard session == nil, let preferredInputSourceID,
            let current = Self.currentSource(),
            Self.identifier(of: current) != preferredInputSourceID
        else { return }
        session = Session(previousSource: current, preferredInputSourceID: preferredInputSourceID)
    }

    /// Goes through the field's own context, so the switch follows the palette's focus.
    func applySession(to inputContext: NSTextInputContext) {
        guard let session, !session.applied else { return }
        inputContext.selectedKeyboardInputSource = session.preferredInputSourceID
        self.session?.applied = true
    }

    /// Undoes only our own switch: a source picked since, by the user or another app, stands.
    func endSession() {
        guard let session else { return }
        self.session = nil
        guard session.applied, let current = Self.currentSource(),
            Self.identifier(of: current) == session.preferredInputSourceID
        else { return }
        TISSelectInputSource(session.previousSource)
    }

    private static func currentSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private static func option(for source: TISInputSource) -> Option? {
        guard let id = identifier(of: source),
            let title: String = property(kTISPropertyLocalizedName, of: source)
        else { return nil }
        return Option(id: id, title: title)
    }

    private static func identifier(of source: TISInputSource) -> String? {
        property(kTISPropertyInputSourceID, of: source)
    }

    private static func enabledKeyboardSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
        var sources: [TISInputSource] = []
        for case let source as TISInputSource in list as NSArray where isSelectableKeyboard(source) {
            sources.append(source)
        }
        return sources
    }

    private static func isSelectableKeyboard(_ source: TISInputSource) -> Bool {
        let category: String? = property(kTISPropertyInputSourceCategory, of: source)
        return category == kTISCategoryKeyboardInputSource as String
            && property(kTISPropertyInputSourceIsSelectCapable, of: source) == true
    }

    /// TIS vends properties as untyped pointers, so an unexpected type must read as absent, not trap.
    private static func property<Value>(_ key: CFString, of source: TISInputSource) -> Value? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue() as? Value
    }
}
