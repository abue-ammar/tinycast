import Carbon.HIToolbox
import Observation

/// The last step's launcher shortcut: whether it is free, and the Spotlight swap Undo reverses.
@MainActor
@Observable
final class OnboardingShortcutSession {
    enum Notice {
        case taken
        case heldBySpotlight
        case suggestion
        case spotlightOff
    }

    private enum Availability {
        case available
        /// Spotlight holds it and no Tinycast action does; other holders surface once it is off.
        case heldBySpotlight
        case taken
    }

    private struct SpotlightReplacement {
        let shortcut: KeyShortcut
        let previousBinding: HotKeyBinding?
    }

    private static let suggestedBinding = HotKeyBinding.combo(
        KeyShortcut(carbonKeyCode: kVK_Space, carbonModifiers: cmdKey))

    private var availability = Availability.available
    private var spotlightReplacement: SpotlightReplacement?
    @ObservationIgnored private let hotKeys: HotKeyManager
    @ObservationIgnored private let reportFailure: (String) -> Void

    init(hotKeys: HotKeyManager, reportFailure: @escaping (String) -> Void) {
        self.hotKeys = hotKeys
        self.reportFailure = reportFailure
    }

    var assignedBinding: HotKeyBinding? { hotKeys.binding(for: .togglePalette) }
    /// The suggestion stands in until a binding exists, so the keys always show something.
    var binding: HotKeyBinding { assignedBinding ?? Self.suggestedBinding }
    var isRecording: Bool { hotKeys.recordingAction == .togglePalette }
    var isReady: Bool { assignedBinding != nil && availability == .available }

    var notice: Notice? {
        switch availability {
        case .taken: return .taken
        case .heldBySpotlight: return isRecording ? nil : .heldBySpotlight
        case .available:
            guard !isRecording else { return nil }
            if assignedBinding == nil { return .suggestion }
            return spotlightReplacement == nil ? nil : .spotlightOff
        }
    }

    func refresh() {
        availability = availability(of: binding)
    }

    func useSuggestion() {
        refresh()
        guard availability == .available else { return }
        assign(binding)
    }

    func replaceSpotlight() {
        let binding = binding
        guard let shortcut = binding.shortcut, SpotlightShortcut.current == shortcut else {
            return refresh()
        }
        guard SpotlightShortcut.setEnabled(false) else { return reportSpotlightFailure() }
        guard isFree(binding) else {
            if !SpotlightShortcut.setEnabled(true) { reportSpotlightFailure() }
            availability = .taken
            return
        }
        spotlightReplacement = SpotlightReplacement(shortcut: shortcut, previousBinding: assignedBinding)
        assign(binding)
        availability = .available
    }

    /// Restores the previous binding only while the launcher still uses Spotlight's shortcut.
    func undoSpotlightReplacement() {
        guard let replacement = spotlightReplacement else { return }
        guard SpotlightShortcut.setEnabled(true) else { return reportSpotlightFailure() }
        spotlightReplacement = nil
        if assignedBinding == .combo(replacement.shortcut) { assign(replacement.previousBinding) }
        refresh()
    }

    private func availability(of binding: HotKeyBinding) -> Availability {
        if let shortcut = binding.shortcut, SpotlightShortcut.current == shortcut,
            hotKeys.conflictOwner(of: binding, excluding: .togglePalette) == nil
        {
            return .heldBySpotlight
        }
        return isFree(binding) ? .available : .taken
    }

    private func isFree(_ binding: HotKeyBinding) -> Bool {
        hotKeys.conflictOwner(of: binding, excluding: .togglePalette, includingExternal: true) == nil
    }

    private func assign(_ binding: HotKeyBinding?) {
        guard binding != assignedBinding else { return }
        hotKeys.setBinding(binding, for: .togglePalette)
    }

    private func reportSpotlightFailure() {
        reportFailure(String(localized: "Couldn't change Spotlight's shortcut."))
    }
}
