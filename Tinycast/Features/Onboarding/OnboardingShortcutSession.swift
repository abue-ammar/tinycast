import AppKit
import Carbon.HIToolbox

/// The last step's launcher shortcut: whether it is free, and the Spotlight swap Undo reverses.
@MainActor
@Observable
final class OnboardingShortcutSession {
    enum Notice: Equatable {
        case taken
        case rejected(ShortcutCaptureSession.Conflict)
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

    /// Set once the user presses the shortcut they chose, which ends onboarding.
    private(set) var isConfirmed = false
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
    var isReady: Bool { assignedBinding != nil && availability == .available }

    /// The modifiers held right now, so the keys follow the user's fingers before a shortcut lands.
    var heldCaps: [String] {
        guard hotKeys.recordingAction == .togglePalette else { return [] }
        let capture = hotKeys.capture
        let flags = capture.heldGlobe ? capture.heldModifiers.union(.function) : capture.heldModifiers
        return KeyShortcut.collapsedModifierSymbols(
            from: flags, hyperChord: KeyShortcut.displayedHyperChord())
    }

    var notice: Notice? {
        if let conflict = hotKeys.capture.conflict { return .rejected(conflict) }
        switch availability {
        case .taken: return .taken
        case .heldBySpotlight: return .heldBySpotlight
        case .available:
            if assignedBinding == nil { return .suggestion }
            return spotlightReplacement == nil ? nil : .spotlightOff
        }
    }

    func refresh() {
        guard !isConfirmed else { return }
        availability = availability(of: binding)
    }

    func startListening() {
        guard !isConfirmed, hotKeys.recordingAction == nil else { return }
        hotKeys.startListening(for: .togglePalette)
    }

    func stopListening() {
        guard hotKeys.recordingAction == .togglePalette else { return }
        hotKeys.recordingAction = nil
    }

    func confirm() {
        isConfirmed = true
        stopListening()
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
