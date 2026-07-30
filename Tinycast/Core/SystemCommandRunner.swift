import AppKit
import Carbon
import CoreAudio
import Darwin

struct SystemCommandFailure: LocalizedError, Sendable {
    enum Settings: Sendable {
        case accessibility
        case automation
        case bluetooth
    }

    let message: String
    let settings: Settings?

    init(_ message: String, settings: Settings? = nil) {
        self.message = message
        self.settings = settings
    }

    var errorDescription: String? { message }
}

struct SystemCommandFeedback: Sendable {
    let title: String
    let symbol: String
    /// Set when the command found nothing to do; it reads as information rather than a completed change.
    let isNoOp: Bool

    init(_ title: String, symbol: String, isNoOp: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.isNoOp = isNoOp
    }
}

@MainActor
enum SystemCommandRunner {
    private struct ProcessOutput: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static let volumeStep: Float32 = 1 / 16

    /// What a command reports back once it succeeded. Only commands whose effect is otherwise invisible
    /// return one, since Show Desktop or Hide Others are their own confirmation.
    static func run(_ id: SystemCommand.ID, previousApp: NSRunningApplication?) async throws
        -> SystemCommandFeedback?
    {
        switch id {
        case .lockScreen:
            try postKey(keyCode: CGKeyCode(kVK_ANSI_Q), flags: [.maskControl, .maskCommand])
        case .sleep:
            try await runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
        case .sleepDisplays:
            try await runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
        case .restart:
            try runAppleScript("tell application \"System Events\" to restart")
        case .shutDown:
            try runAppleScript("tell application \"System Events\" to shut down")
        case .logOut:
            try runAppleScript("tell application \"System Events\" to log out")
        case .showScreenSaver:
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SystemCommandFailure("The macOS screen saver could not be found.")
            }
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    guard let error else { return }
                    Task { @MainActor in
                        AppCore.shared.presentSystemCommandFailure(
                            name: "Show Screen Saver",
                            failure: SystemCommandFailure(error.localizedDescription))
                    }
                }
        case .playPause:
            try postMediaKey(16)
        case .nextTrack:
            try postMediaKey(17)
        case .previousTrack:
            try postMediaKey(18)
        case .toggleMute:
            try toggleMute()
        case .volumeUp:
            try changeVolume(by: volumeStep)
        case .volumeDown:
            try changeVolume(by: -volumeStep)
        case .setVolume:
            break  // AppCore owns the value-picking dialog and calls setVolume directly.
        case .volume0:
            try setVolume(0)
        case .volume25:
            try setVolume(0.25)
        case .volume50:
            try setVolume(0.5)
        case .volume75:
            try setVolume(0.75)
        case .volume100:
            try setVolume(1)
        case .showDesktop:
            try await runProcess(
                "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control",
                arguments: ["1"])
        case .toggleAppearance:
            // The script returns the resulting state, so the confirmation can name it instead of guessing.
            let result = try runAppleScript(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
            let dark = result?.booleanValue ?? false
            return SystemCommandFeedback(
                dark ? "Dark Appearance" : "Light Appearance",
                symbol: dark ? "moon.fill" : "sun.max.fill")
        case .toggleStageManager:
            let on = try await toggleDefault(
                domain: "com.apple.WindowManager", key: "GloballyEnabled")
            return SystemCommandFeedback(
                on ? "Stage Manager On" : "Stage Manager Off",
                symbol: "squares.leading.rectangle")
        case .openTrash:
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            guard NSWorkspace.shared.open(trash) else {
                throw SystemCommandFailure("Finder could not open the Trash.")
            }
        case .emptyTrash:
            // Finder errors out on an already-empty Trash, so ask it for the count first. Finder is also the
            // right oracle rather than reading `~/.Trash` ourselves: that folder is TCC-protected, so a
            // direct read fails without Full Disk Access and would look indistinguishable from "empty".
            let items =
                try runAppleScript("tell application \"Finder\" to count items of trash")?
                .int32Value ?? 0
            guard items > 0 else {
                return SystemCommandFeedback(
                    "Trash Is Already Empty", symbol: "trash", isNoOp: true)
            }
            try runAppleScript("tell application \"Finder\" to empty trash")
            return SystemCommandFeedback("Trash Emptied", symbol: "trash")
        case .ejectAllDisks:
            let ejected = try ejectAllDisks()
            guard ejected > 0 else {
                return SystemCommandFeedback("No Disks to Eject", symbol: "eject", isNoOp: true)
            }
            return SystemCommandFeedback(
                ejected == 1 ? "1 Disk Ejected" : "\(ejected) Disks Ejected", symbol: "eject")
        case .toggleHiddenFiles:
            let shown = try await toggleDefault(
                domain: "com.apple.finder", key: "AppleShowAllFiles")
            let output = try await process("/usr/bin/killall", arguments: ["Finder"])
            if output.status != 0 && output.status != 1 {
                throw processFailure(output, executable: "killall")
            }
            return SystemCommandFeedback(
                shown ? "Hidden Files Shown" : "Hidden Files Hidden",
                symbol: shown ? "eye" : "eye.slash")
        case .hideOtherApps:
            hideOtherApps(except: previousApp)
        case .unhideAllApps:
            let hidden = NSWorkspace.shared.runningApplications.filter(\.isHidden)
            for app in hidden { app.unhide() }
            guard !hidden.isEmpty else {
                return SystemCommandFeedback("Nothing Was Hidden", symbol: "eye", isNoOp: true)
            }
            return SystemCommandFeedback("All Apps Unhidden", symbol: "eye")
        case .quitAllApps:
            for app in AppLauncher.quitAllTargets() { app.terminate() }
        case .dismissNotifications:
            let dismissed = try await dismissNotifications()
            guard dismissed > 0 else {
                return SystemCommandFeedback(
                    "No Notifications", symbol: "bell.slash", isNoOp: true)
            }
            return SystemCommandFeedback("Notifications Dismissed", symbol: "bell.slash")
        }
        return nil
    }

    static func currentVolume() throws -> Float32 {
        let device = try defaultOutputDevice()
        let elements = try volumeElements(on: device)
        // Averaged across the preferred channels when there's no master element, so a balanced pair reads as one level.
        var total: Float32 = 0
        for element in elements {
            var address = volumeAddress(element: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
                throw SystemCommandFailure(
                    "The current audio output does not support software volume.")
            }
            total += value
        }
        return total / Float32(elements.count)
    }

    /// What the HUD renders after a volume or mute command. A device with no mute control reports zero level as muted, since that is how the fallback mutes it.
    static func outputState() throws -> (level: Float32, muted: Bool) {
        let level = try currentVolume()
        let device = try defaultOutputDevice()
        var address = muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &address),
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        else {
            return (level, level == 0)
        }
        return (level, muted != 0)
    }

    static func setVolume(_ requested: Float32) throws {
        let device = try defaultOutputDevice()
        let elements = try volumeElements(on: device)
        let value = min(max(requested, 0), 1)
        for element in elements {
            var address = volumeAddress(element: element)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                settable.boolValue
            else {
                throw SystemCommandFailure(
                    "The current audio output volume is controlled externally.")
            }
            var applied = value
            let status = AudioObjectSetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &applied)
            guard status == noErr else {
                throw SystemCommandFailure(
                    "macOS could not change the output volume (error \(status)).")
            }
        }
        if value > 0 { try? setMuted(false, on: device) }
    }

    /// The master element when the device exposes one, else its preferred stereo channels, since HDMI and some USB outputs only publish per-channel volume.
    private static func volumeElements(on device: AudioDeviceID) throws -> [AudioObjectPropertyElement] {
        var main = volumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &main) { return [kAudioObjectPropertyElementMain] }

        var stereoAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var channels: (UInt32, UInt32) = (1, 2)
        var size = UInt32(MemoryLayout<(UInt32, UInt32)>.size)
        if AudioObjectGetPropertyData(device, &stereoAddress, 0, nil, &size, &channels) != noErr {
            channels = (1, 2)
        }
        let elements = [channels.0, channels.1].filter { channel in
            var address = volumeAddress(element: channel)
            return AudioObjectHasProperty(device, &address)
        }
        guard !elements.isEmpty else {
            throw SystemCommandFailure("The current audio output does not support software volume.")
        }
        return elements
    }

    private static func volumeAddress(element: AudioObjectPropertyElement)
        -> AudioObjectPropertyAddress
    {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            throw SystemCommandFailure("No audio output device is available.")
        }
        return device
    }

    private static func changeVolume(by delta: Float32) throws {
        try setVolume(try currentVolume() + delta)
    }

    private static func toggleMute() throws {
        let device = try defaultOutputDevice()
        var address = muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &address),
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        {
            try setMuted(muted == 0, on: device)
            return
        }
        // No mute control (common on HDMI): fall back to parking the volume at zero and restoring it.
        let current = try currentVolume()
        guard current > 0 else {
            try setVolume(lastNonZeroVolume)
            return
        }
        lastNonZeroVolume = current
        try setVolume(0)
    }

    /// Restore level for the volume-based mute fallback; only written when a mute drops the output to zero.
    private static var lastNonZeroVolume: Float32 = 0.5

    private static func setMuted(_ muted: Bool, on device: AudioDeviceID) throws {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else {
            guard muted else { return }
            let current = try currentVolume()
            if current > 0 { lastNonZeroVolume = current }
            try setVolume(0)
            return
        }
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else {
            throw SystemCommandFailure("macOS could not change mute state (error \(status)).")
        }
    }

    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard Permissions.ensureAccessibility() else {
            throw SystemCommandFailure(
                "Allow Tinycast to control your Mac in Accessibility settings, then try again.",
                settings: .accessibility)
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { throw SystemCommandFailure("macOS could not create the keyboard event.") }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postMediaKey(_ key: Int32) throws {
        guard Permissions.ensureAccessibility() else {
            throw SystemCommandFailure(
                "Allow Tinycast to control your Mac in Accessibility settings, then try again.",
                settings: .accessibility)
        }
        // Auxiliary-key events are the same route as the keyboard's media keys; 0xA/0xB are their down/up states.
        for state in [0xA, 0xB] {
            let data1 = Int((key << 16) | (Int32(state) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func hideOtherApps(except previousApp: NSRunningApplication?) {
        let ownPID = NSRunningApplication.current.processIdentifier
        let keptPID = previousApp?.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular
            && app.processIdentifier != ownPID
            && app.processIdentifier != keptPID
        {
            app.hide()
        }
        previousApp?.unhide()
        previousApp?.activate()
    }

    @discardableResult
    private static func ejectAllDisks() throws -> Int {
        let keys: Set<URLResourceKey> = [
            .volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsLocalKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        let ejectable = urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return false }
            return values.volumeIsEjectable == true
                && values.volumeIsInternal != true
                && values.volumeIsLocal != false
        }
        var failures: [String] = []
        var ejected = 0
        for url in ejectable {
            // One physical disk can publish several volumes, and ejecting the first takes the whole device with it, so a sibling that vanished is done, not failed.
            guard mountedVolumeExists(url) else { continue }
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                ejected += 1
            } catch {
                guard mountedVolumeExists(url) else { continue }
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            throw SystemCommandFailure("Some disks could not be ejected:\n\n" + failures.joined(separator: "\n"))
        }
        return ejected
    }

    private static func mountedVolumeExists(_ url: URL) -> Bool {
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return mounted.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    /// Returns the state the toggle landed in, so the caller can name it rather than re-reading the preference.
    @discardableResult
    private static func toggleDefault(domain: String, key: String) async throws -> Bool {
        let read = try await process("/usr/bin/defaults", arguments: ["read", domain, key])
        let normalized = read.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let current: Bool
        if read.status == 0 {
            guard let parsed = booleanDefault(normalized) else {
                throw SystemCommandFailure("macOS reported an unexpected value for this setting.")
            }
            current = parsed
        } else if read.stderr.contains("does not exist") {
            // Unset keys are genuinely off; any other read failure is unknown state and must not be overwritten.
            current = false
        } else {
            throw processFailure(read, executable: "defaults")
        }
        let requested = !current
        try await runProcess(
            "/usr/bin/defaults",
            arguments: ["write", domain, key, "-bool", requested ? "true" : "false"])
        let verify = try await process("/usr/bin/defaults", arguments: ["read", domain, key])
        let verified = verify.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard verify.status == 0, booleanDefault(verified) == requested else {
            throw SystemCommandFailure("macOS did not save the requested setting.")
        }
        return requested
    }

    private static func booleanDefault(_ value: String) -> Bool? {
        switch value {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    /// Returns how many notifications were dismissed, so "nothing on screen" can read as information instead of a silent no-op.
    private static func dismissNotifications() async throws -> Int {
        guard Permissions.ensureAccessibility() else {
            throw SystemCommandFailure(
                "Allow Tinycast to control your Mac in Accessibility settings, then try again.",
                settings: .accessibility)
        }
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return 0 }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var dismissed = 0
        for _ in 0..<100 {
            // The tree is rebuilt every pass: pressing one control invalidates its siblings.
            let notifications = notificationElements(in: root, depth: 0)
            guard !notifications.isEmpty else { return dismissed }
            guard let button = notifications.compactMap({ dismissControl(in: $0, depth: 0) }).first
            else {
                throw SystemCommandFailure(
                    "This version of Notification Center exposes no dismiss control Tinycast can use.")
            }
            let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            guard result == .success || result == .invalidUIElement else {
                throw SystemCommandFailure("Notification Center did not allow a notification to be dismissed.")
            }
            dismissed += 1
            try await Task.sleep(for: .milliseconds(150))
        }
        throw SystemCommandFailure("Some notifications remain after the safety limit was reached.")
    }

    /// Notification containers, matched on Accessibility subrole so the search never depends on the UI language.
    private static func notificationElements(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < 20 else { return [] }
        let subrole = axString(element, attribute: kAXSubroleAttribute as CFString)?.lowercased()
        if let subrole, subrole.contains("notificationcenter") { return [element] }
        return axChildren(element).flatMap { notificationElements(in: $0, depth: depth + 1) }
    }

    /// A Close / Clear All control inside one notification: the close subrole is language-independent, and the label match is only a fallback. Never falls through to an arbitrary button, because a notification's own action rows (Reply, Open) also press.
    private static func dismissControl(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 20 else { return nil }
        if canPress(element) {
            let subrole = axString(element, attribute: kAXSubroleAttribute as CFString)?.lowercased()
            if subrole == (kAXCloseButtonSubrole as String).lowercased() { return element }
            let text = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                .compactMap { axString(element, attribute: $0 as CFString) }
                .joined(separator: " ").lowercased()
            if text.contains("clear all") || text == "close" || text.contains("dismiss") {
                return element
            }
        }
        for child in axChildren(element) {
            if let found = dismissControl(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func canPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
            let names = actions as? [String]
        else { return false }
        return names.contains(kAXPressAction)
    }

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            == .success,
            let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func axString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    @discardableResult
    private static func runAppleScript(_ source: String) throws -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            throw SystemCommandFailure("The system automation could not be prepared.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return result }
        let number = errorInfo[NSAppleScript.errorNumber] as? Int
        let detail = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown automation error."
        if number == -1743 {
            throw SystemCommandFailure(
                "Allow Tinycast to control the requested app in Automation settings, then try again.",
                settings: .automation)
        }
        throw SystemCommandFailure(detail)
    }

    private static func runProcess(_ executable: String, arguments: [String]) async throws {
        let output = try await process(executable, arguments: arguments)
        guard output.status == 0 else { throw processFailure(output, executable: executable) }
    }

    private static func process(_ executable: String, arguments: [String]) async throws -> ProcessOutput {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            do { try process.run() } catch {
                throw SystemCommandFailure("\(URL(fileURLWithPath: executable).lastPathComponent) could not start: \(error.localizedDescription)")
            }
            process.waitUntilExit()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ProcessOutput(
                status: process.terminationStatus,
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errorData, encoding: .utf8) ?? "")
        }.value
    }

    private static func processFailure(_ output: ProcessOutput, executable: String) -> SystemCommandFailure {
        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return SystemCommandFailure(
            detail.isEmpty ? "\(name) exited with status \(output.status)." : detail)
    }
}
