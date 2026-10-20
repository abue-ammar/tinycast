import AppKit
import Observation
import SwiftUI

@main
@MainActor
struct OnboardingTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task {
            let core = AppCore()
            let onboarding = OnboardingCoordinator(core: core)
            onboarding.showOnboarding()
            for _ in 0..<100 where NSApp.keyWindow?.title != "Welcome to Tinycast" {
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard NSApp.keyWindow?.title == "Welcome to Tinycast" else {
                print("FAIL: introduction becomes key")
                exit(1)
            }
            guard NSApp.activationPolicy() == .accessory,
                !core.activationPolicy.hasOpenWindows
            else {
                print("FAIL: introduction does not register Dock ownership")
                exit(1)
            }
            onboarding.finishOnboarding()
            var stayedOpen = true
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(20))
                stayedOpen =
                    stayedOpen && core.paletteCoordinator.panel.isVisible
                    && core.paletteCoordinator.panel.isKeyWindow
            }
            core.paletteCoordinator.panel.close()
            guard stayedOpen else {
                print("FAIL: launcher stays visible and key after introduction closes")
                exit(1)
            }
            let settings = AppWindowController(
                title: "Settings", contentSize: CGSize(width: 400, height: 300),
                activation: core.activationPolicy)
            settings.show { Text("Settings fixture") }
            guard NSApp.activationPolicy() == .regular, core.activationPolicy.hasOpenWindows else {
                print("FAIL: ordinary windows still register Dock ownership")
                exit(1)
            }
            onboarding.showOnboarding()
            onboarding.finishOnboarding()
            guard NSApp.activationPolicy() == .regular, core.activationPolicy.hasOpenWindows else {
                print("FAIL: introduction leaves another window's Dock ownership intact")
                exit(1)
            }
            core.paletteCoordinator.panel.close()
            settings.close()
            guard NSApp.activationPolicy() == .accessory, !core.activationPolicy.hasOpenWindows else {
                print("FAIL: closing the last ordinary window restores accessory mode")
                exit(1)
            }
            print("PASS: introduction handoff and ordinary window activation")
            exit(0)
        }
        app.run()
    }
}

@MainActor
@Observable
final class AppCore {
    let activationPolicy = ActivationPolicy()
    let settings = AppSettings()
    let hotKeys = HotKeyManager()
    let paletteCoordinator = PaletteCoordinator()
}

@MainActor
@Observable
final class AppSettings {}

@MainActor
@Observable
final class HotKeyManager {}

struct OnboardingView: View {
    static let initialSize = CGSize(width: 520, height: 352)
    static let width: CGFloat = 520

    var body: some View { Text("Fixture") }
}

@MainActor
final class PaletteCoordinator: NSObject, NSWindowDelegate {
    enum Mode { case launcher }

    final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    let panel = Panel(
        contentRect: NSRect(x: 300, y: 300, width: 500, height: 300),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

    func showPalette(mode: Mode) {
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
    }
}
