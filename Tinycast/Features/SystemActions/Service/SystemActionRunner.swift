import AppKit
import Carbon
import CoreAudio
import Darwin

struct SystemActionFailure: LocalizedError, Sendable {
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

struct SystemActionFeedback: Sendable {
    let title: String
    /// Set when there was nothing to do, so it reads as information, not a change.
    let isNoOp: Bool

    init(_ title: String, isNoOp: Bool = false) {
        self.title = title
        self.isNoOp = isNoOp
    }
}

@MainActor
enum SystemActionRunner {
    /// Failures raised after `run` returned; the runner owns effects, never UI. Set in `start()`.
    static var onAsyncFailure: ((SystemAction.ID, SystemActionFailure) -> Void)?

    private struct ProcessOutput: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// What an action reports on success; only the ones whose effect is invisible do.
    static func run(
        _ id: SystemAction.ID, previousApp: NSRunningApplication?
    ) async throws
        -> SystemActionFeedback?
    {
        switch id {
        case .lockScreen:
            try postKey(keyCode: CGKeyCode(kVK_ANSI_Q), flags: [.maskControl, .maskCommand])
        case .sleep:
            try await runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
        case .sleepDisplays:
            try await runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
        case .restart:
            try await runAppleScript("tell application \"System Events\" to restart")
        case .shutDown:
            try await runAppleScript("tell application \"System Events\" to shut down")
        case .logOut:
            try await runAppleScript("tell application \"System Events\" to log out")
        case .showScreenSaver:
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SystemActionFailure("The macOS screen saver could not be found.")
            }
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    onAsyncFailure?(
                        .showScreenSaver, SystemActionFailure(error.localizedDescription))
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
            try stepVolume(up: true)
        case .volumeDown:
            try stepVolume(up: false)
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
            // The script returns the resulting state, so the confirmation can name it.
            let result = try await runAppleScript(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
            )
            let dark = result.flag
            return SystemActionFeedback(dark ? "Dark Appearance" : "Light Appearance")
        case .toggleStageManager:
            let on = try await toggleDefault(
                domain: "com.apple.WindowManager", key: "GloballyEnabled")
            return SystemActionFeedback(on ? "Stage Manager On" : "Stage Manager Off")
        case .openTrash:
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            guard NSWorkspace.shared.open(trash) else {
                throw SystemActionFailure("Finder could not open the Trash.")
            }
        case .emptyTrash:
            // Count first: Finder errors on an empty Trash, and `~/.Trash` is TCC-protected.
            let items =
                try await runAppleScript("tell application \"Finder\" to count items of trash")
                .number
            guard items > 0 else {
                return SystemActionFeedback("Trash Is Already Empty", isNoOp: true)
            }
            try await runAppleScript("tell application \"Finder\" to empty trash")
            return SystemActionFeedback("Trash Emptied")
        case .ejectAllDisks:
            let ejected = try ejectAllDisks()
            guard ejected > 0 else {
                return SystemActionFeedback("No Disks to Eject", isNoOp: true)
            }
            return SystemActionFeedback(ejected == 1 ? "1 Disk Ejected" : "\(ejected) Disks Ejected")
        case .toggleHiddenFiles:
            let shown = try await toggleDefault(
                domain: "com.apple.finder", key: "AppleShowAllFiles")
            let output = try await process("/usr/bin/killall", arguments: ["Finder"])
            if output.status != 0 && output.status != 1 {
                throw processFailure(output, executable: "killall")
            }
            return SystemActionFeedback(shown ? "Hidden Files Shown" : "Hidden Files Hidden")
        case .hideOtherApps:
            hideOtherApps(except: previousApp)
        case .unhideAllApps:
            let hidden = NSWorkspace.shared.runningApplications.filter(\.isHidden)
            for app in hidden { app.unhide() }
            guard !hidden.isEmpty else {
                return SystemActionFeedback("Nothing Was Hidden", isNoOp: true)
            }
            return SystemActionFeedback("All Apps Unhidden")
        case .quitAllApps:
            for app in AppLauncher.quitAllTargets() { app.terminate() }
        case .dismissNotifications:
            let dismissed = try await dismissNotifications()
            guard dismissed > 0 else {
                return SystemActionFeedback("No Notifications", isNoOp: true)
            }
            return SystemActionFeedback("Notifications Dismissed")
        case .toggleBluetooth:
            let on = try await toggleBluetooth()
            return SystemActionFeedback(on ? "Bluetooth On" : "Bluetooth Off")
        }
        return nil
    }

    static func currentVolume() throws -> Float32 {
        let device = try defaultOutputDevice()
        let elements = try volumeElements(on: device)
        // Averaged across channels without a master, so a pair reads as one level.
        var total: Float32 = 0
        for element in elements {
            var address = volumeAddress(element: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
                throw SystemActionFailure(
                    "The current audio output does not support software volume.")
            }
            total += value
        }
        return total / Float32(elements.count)
    }

    /// What the HUD renders; without a mute control, zero level reads as muted.
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
                throw SystemActionFailure(
                    "The current audio output volume is controlled externally.")
            }
            var applied = value
            let status = AudioObjectSetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &applied)
            guard status == noErr else {
                throw SystemActionFailure(
                    "macOS could not change the output volume (error \(status)).")
            }
        }
        if value > 0 { try? setMuted(false, on: device) }
    }

    /// The master element where there is one, else the preferred stereo channels.
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
            throw SystemActionFailure("The current audio output does not support software volume.")
        }
        return elements
    }

    private static func volumeAddress(
        element: AudioObjectPropertyElement
    )
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
            throw SystemActionFailure("No audio output device is available.")
        }
        return device
    }

    private static func stepVolume(up: Bool) throws {
        try setVolume(Float32(VolumeLevel.stepped(Double(try currentVolume()), up: up)))
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
        // No mute control: park the volume at zero and restore it afterwards.
        let current = try currentVolume()
        guard current > 0 else {
            try setVolume(lastNonZeroVolume)
            return
        }
        lastNonZeroVolume = current
        try setVolume(0)
    }

    /// Restore level for the mute fallback, written only when a mute drops it to zero.
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
            throw SystemActionFailure("macOS could not change mute state (error \(status)).")
        }
    }

    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard Permissions.ensureAccessibility() else {
            throw SystemActionFailure(
                "Allow Tinycast to control your Mac in Accessibility settings, then try again.",
                settings: .accessibility)
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { throw SystemActionFailure("macOS could not create the keyboard event.") }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postMediaKey(_ key: Int32) throws {
        guard Permissions.ensureAccessibility() else {
            throw SystemActionFailure(
                "Allow Tinycast to control your Mac in Accessibility settings, then try again.",
                settings: .accessibility)
        }
        // The same route as the keyboard's media keys; 0xA/0xB are down and up.
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
            .volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsLocalKey
        ]
        let urls =
            FileManager.default.mountedVolumeURLs(
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
            // Ejecting one volume takes the device, so a vanished sibling is done.
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
            throw SystemActionFailure(
                "Some disks could not be ejected:\n\n" + failures.joined(separator: "\n"))
        }
        return ejected
    }

    private static func mountedVolumeExists(_ url: URL) -> Bool {
        let mounted =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return mounted.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    /// Returns the state it landed in, so the caller needn't re-read the preference.
    @discardableResult
    private static func toggleDefault(domain: String, key: String) async throws -> Bool {
        let read = try await process("/usr/bin/defaults", arguments: ["read", domain, key])
        let normalized = read.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let current: Bool
        if read.status == 0 {
            guard let parsed = booleanDefault(normalized) else {
                throw SystemActionFailure("macOS reported an unexpected value for this setting.")
            }
            current = parsed
        } else if read.stderr.contains("does not exist") {
            // Unset is genuinely off; any other failure is unknown and stays untouched.
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
            throw SystemActionFailure("macOS did not save the requested setting.")
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

    /// Returns how many were dismissed, so an empty screen reads as information.
    private static func dismissNotifications() async throws -> Int {
        guard Permissions.ensureAccessibility() else {
            throw SystemActionFailure(
                "Allow Tinycast to control your Mac in Accessibility settings, then try again.",
                settings: .accessibility)
        }
        guard
            let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui"
            ).first
        else { return 0 }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var dismissed = 0
        for _ in 0..<100 {
            // The tree is rebuilt every pass: pressing one control invalidates its siblings.
            let notifications = notificationElements(in: root, depth: 0)
            guard !notifications.isEmpty else { return dismissed }
            guard let button = notifications.compactMap({ dismissControl(in: $0, depth: 0) }).first
            else {
                throw SystemActionFailure(
                    "This version of Notification Center exposes no dismiss control Tinycast can use.")
            }
            let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            guard result == .success || result == .invalidUIElement else {
                throw SystemActionFailure("Notification Center did not allow a notification to be dismissed.")
            }
            dismissed += 1
            try await Task.sleep(for: .milliseconds(150))
        }
        throw SystemActionFailure("Some notifications remain after the safety limit was reached.")
    }

    /// Matched on AX subrole, so the search never depends on the UI language.
    private static func notificationElements(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < 20 else { return [] }
        let subrole = axString(element, attribute: kAXSubroleAttribute as CFString)?.lowercased()
        if let subrole, subrole.contains("notificationcenter") { return [element] }
        return axChildren(element).flatMap { notificationElements(in: $0, depth: depth + 1) }
    }

    /// The close control; never an arbitrary button, a notification's own rows press too.
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
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
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

    /// Returns the state it settled into; the setter is void, so polling is the only way.
    private static func toggleBluetooth() async throws -> Bool {
        let path = "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth"
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw SystemActionFailure("Bluetooth control is unavailable on this Mac.")
        }
        defer { dlclose(handle) }
        typealias Available = @convention(c) () -> Int32
        typealias GetPower = @convention(c) () -> Int32
        typealias SetPower = @convention(c) (Int32) -> Void
        guard let availableSymbol = dlsym(handle, "IOBluetoothPreferencesAvailable"),
            let getSymbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState"),
            let setSymbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { throw SystemActionFailure("This macOS version does not expose Bluetooth power control.") }
        let available = unsafeBitCast(availableSymbol, to: Available.self)
        let getPower = unsafeBitCast(getSymbol, to: GetPower.self)
        let setPower = unsafeBitCast(setSymbol, to: SetPower.self)
        guard available() != 0 else {
            throw SystemActionFailure("No Bluetooth controller is available.", settings: .bluetooth)
        }
        let requested: Int32 = getPower() == 0 ? 1 : 0
        setPower(requested)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if getPower() == requested { return requested == 1 }
        }
        throw SystemActionFailure(
            "Bluetooth did not change state. Check Tinycast’s Bluetooth permission.",
            settings: .bluetooth)
    }

    /// `NSAppleEventDescriptor` isn't `Sendable`, so the two fields callers read cross instead.
    private struct AppleScriptResult: Sendable {
        let number: Int32
        let flag: Bool
    }

    /// A cold Finder answers in seconds, so the send never happens on the main actor.
    @discardableResult
    private static func runAppleScript(_ source: String) async throws -> AppleScriptResult {
        try await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else {
                throw SystemActionFailure("The system automation could not be prepared.")
            }
            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            guard let errorInfo else {
                return AppleScriptResult(number: result.int32Value, flag: result.booleanValue)
            }
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            let detail =
                errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown automation error."
            if number == -1743 {
                throw SystemActionFailure(
                    "Allow Tinycast to control the requested app in Automation settings, then try again.",
                    settings: .automation)
            }
            throw SystemActionFailure(detail)
        }.value
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
                throw SystemActionFailure(
                    "\(URL(fileURLWithPath: executable).lastPathComponent) could not start: \(error.localizedDescription)"
                )
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

    private static func processFailure(_ output: ProcessOutput, executable: String) -> SystemActionFailure {
        let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return SystemActionFailure(
            detail.isEmpty ? "\(name) exited with status \(output.status)." : detail)
    }
}
