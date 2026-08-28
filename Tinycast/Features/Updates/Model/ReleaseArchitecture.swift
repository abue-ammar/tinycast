import Foundation

/// Which slice of a release a build can run. macOS 26 is the last release to boot on Intel, so the
/// stable channel publishes a thin arm64 artifact and a universal one beside it.
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
