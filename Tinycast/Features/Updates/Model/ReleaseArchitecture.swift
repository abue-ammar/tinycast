import Foundation

/// macOS 26 is the last release to boot on Intel, so stable ships thin and universal.
enum ReleaseArchitecture: Sendable {
    case appleSilicon
    case intel

    /// Resolved per slice at compile time, so a universal binary reports the one macOS launched.
    static var current: ReleaseArchitecture {
        #if arch(x86_64)
            .intel
        #else
            .appleSilicon
        #endif
    }
}
