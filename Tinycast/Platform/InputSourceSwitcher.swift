import AppKit
import Carbon.HIToolbox

@MainActor
final class InputSourceSwitcher {
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
    }

    private struct Session {
        let previousInputSourceID: String
        let preferredInputSourceID: String
        var didApplyPreferredSource = false
    }

    private var session: Session?

    func availableSources() -> [Option] {
        Self.selectableSources().compactMap { source in
            guard
                let id = Self.stringProperty(kTISPropertyInputSourceID, source: source),
                let title = Self.stringProperty(kTISPropertyLocalizedName, source: source)
            else { return nil }
            return Option(id: id as String, title: title as String)
        }
    }

    func beginSession(preferredInputSourceID: String?) {
        guard session == nil, let preferredInputSourceID,
            Self.source(id: preferredInputSourceID) != nil,
            let currentInputSourceID = Self.currentInputSourceID()
        else { return }
        session = Session(
            previousInputSourceID: currentInputSourceID,
            preferredInputSourceID: preferredInputSourceID)
    }

    func applySession(to inputContext: NSTextInputContext) {
        guard var session, !session.didApplyPreferredSource else { return }
        inputContext.selectedKeyboardInputSource = session.preferredInputSourceID
        session.didApplyPreferredSource = true
        self.session = session
    }

    func endSession() {
        guard let session else { return }
        self.session = nil
        Self.selectInputSource(id: session.previousInputSourceID)
    }

    private static func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let id = stringProperty(kTISPropertyInputSourceID, source: source)
        else { return nil }
        return id as String
    }

    @discardableResult
    private static func selectInputSource(id: String) -> Bool {
        guard let source = source(id: id) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    private static func source(id: String) -> TISInputSource? {
        selectableSources().first {
            stringProperty(kTISPropertyInputSourceID, source: $0) as String? == id
        }
    }

    private static func selectableSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
        var sources: [TISInputSource] = []
        for case let source as TISInputSource in list as NSArray {
            guard
                let category = stringProperty(kTISPropertyInputSourceCategory, source: source),
                CFEqual(category, kTISCategoryKeyboardInputSource),
                boolProperty(kTISPropertyInputSourceIsSelectCapable, source: source)
            else { continue }
            sources.append(source)
        }
        return sources
    }

    private static func stringProperty(
        _ key: CFString, source: TISInputSource
    ) -> CFString? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return unsafeBitCast(value, to: CFString.self)
    }

    private static func boolProperty(_ key: CFString, source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
    }
}
