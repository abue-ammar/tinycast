import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shortcut recorder that's deliberately *not* a focusable control: the active recorder is just `HotKeyManager.recordingAction`, so clicking one is a plain state flip with no first-responder handoff, and `CaptureSession` captures keystrokes via a local monitor while it's active.
struct ShortcutRecorder: View {
    let action: HotKeyAction

    @ObservedObject private var hotKeys: HotKeyManager = AppCore.shared.hotKeys
    /// Observed so bound chips re-render when the Hyper Key display settings (✦ collapse, Include Shift) change how `keycaps` renders.
    @ObservedObject private var settings = AppCore.shared.settings
    @StateObject private var session = CaptureSession()
    @State private var hovered = false

    private var isRecording: Bool { hotKeys.recordingAction == action }

    var body: some View {
        content
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(Theme.Colors.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .strokeBorder(
                        isRecording ? Color.accentColor : Theme.Colors.cardStroke,
                        lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
            .onTapGesture { hotKeys.recordingAction = action }
            .onHover { hovered = $0 }
            .onChange(of: isRecording) { _, recording in
                if recording {
                    session.start(action: action, hotKeys: hotKeys)
                } else {
                    session.stop()
                }
            }
            // Rows in the app-hotkeys list are lazy: a recording row scrolled out of existence must release its monitors and unpause the global hotkeys.
            .onDisappear {
                if isRecording { hotKeys.recordingAction = nil }
                session.stop()
            }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    @ViewBuilder
    private var content: some View {
        if isRecording {
            recordingLabel
        } else if let shortcut = hotKeys.shortcut(for: action) {
            boundLabel(shortcut)
        } else {
            Text("Record Shortcut")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingLabel: some View {
        Group {
            if let owner = session.conflictOwner {
                Text("Used by \(owner)")
                    .foregroundStyle(.orange)
            } else if !session.heldModifiers.isEmpty {
                // Collapsed so holding the Hyper key previews as "✦" while recording.
                Text(KeyShortcut.collapsedModifierSymbols(from: session.heldModifiers).joined())
                    .foregroundStyle(.primary)
            } else {
                Text("Type shortcut…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(Theme.Typography.keyCap)
    }

    private func boundLabel(_ shortcut: KeyShortcut) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(shortcut.keycaps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(
                        minWidth: Theme.Size.recorderKeyCap, minHeight: Theme.Size.recorderKeyCap
                    )
                    .background(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.recorderKeyCap, style: .continuous
                        )
                        .fill(Color.primary.opacity(0.08))
                    )
            }
            // Constant-width slot so the clear button doesn't shift the caps on hover.
            Button {
                hotKeys.setShortcut(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
    }
}

/// Owns the local event monitors for the one active recording, live only between `start()` and `stop()` and entirely on the main actor.
@MainActor
private final class CaptureSession: ObservableObject {
    /// Modifiers currently held, for the live "⌃⌥…" preview while recording.
    @Published var heldModifiers: NSEvent.ModifierFlags = []
    /// Owner of a just-typed conflicting combo; shown for a moment, then recording resumes.
    @Published var conflictOwner: String?

    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var conflictReset: Task<Void, Never>?

    func start(action: HotKeyAction, hotKeys: HotKeyManager) {
        stop()
        heldModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])

        // The handlers run on the main thread but AppKit predates actor annotations, hence assumeIsolated; only Sendable event pieces (key code, flags) cross in.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: {
                [weak self, weak hotKeys] event in
                let keyCode = Int(event.keyCode)
                let flags = event.modifierFlags
                MainActor.assumeIsolated {
                    guard let self, let hotKeys else { return }
                    self.handleKeyDown(
                        keyCode: keyCode, flags: flags, action: action, hotKeys: hotKeys)
                }
                return nil  // always consume: no beeps, no leaking keys to the window
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: {
                [weak self] event in
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                MainActor.assumeIsolated { self?.heldModifiers = flags }
                return event
            })
        {
            monitors.append(monitor)
        }

        // A click anywhere ends the recording, then travels on — so a click on another recorder cancels this one and starts that one in a single click.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak hotKeys] event in
                MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
                return event
            })
        {
            monitors.append(monitor)
        }

        // Local monitors go quiet when the settings window resigns key — treat it as a cancel so the paused global hotkeys come back.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak hotKeys] _ in
            MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        conflictReset?.cancel()
        conflictReset = nil
        conflictOwner = nil
        heldModifiers = []
    }

    private func handleKeyDown(
        keyCode: Int, flags: NSEvent.ModifierFlags, action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        let bareKey = flags.intersection([.command, .option, .control, .shift]).isEmpty

        if bareKey, keyCode == kVK_Escape {
            hotKeys.recordingAction = nil
            return
        }
        // Plain Delete clears the existing binding.
        if bareKey, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            hotKeys.setShortcut(nil, for: action)
            hotKeys.recordingAction = nil
            return
        }
        // Not a bindable combo (e.g. a bare letter): swallow it and keep recording.
        guard let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags) else { return }

        if let owner = hotKeys.conflictOwner(of: shortcut, excluding: action) {
            flashConflict(owner)
            return
        }
        hotKeys.setShortcut(shortcut, for: action)
        hotKeys.recordingAction = nil
    }

    private func flashConflict(_ owner: String) {
        conflictOwner = owner
        conflictReset?.cancel()
        conflictReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.conflictOwner = nil
        }
    }
}
