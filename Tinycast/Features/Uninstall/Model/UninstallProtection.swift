import Foundation

/// All the classifier may know about one path, injected so it stays pure.
struct PathFacts: Hashable, Sendable {
    let path: String
    var exists = true
    /// Never followed: sizing through one could walk the whole disk.
    var isSymbolicLink = false
    var volumeIsReadOnly = false
    /// `SF_RESTRICTED` / `SF_IMMUTABLE` — SIP.
    var isSystemRestricted = false
    /// `UF_IMMUTABLE` — Finder's "Locked" checkbox, which the user can clear themselves.
    var isUserImmutable = false
    var isDirectory = false
    /// Only decides anything for a directory — see `classify`.
    var isWritable = true
    /// Only decides anything under a sticky parent — see `classify`.
    var isOwnedByCurrentUser = true
    var parentIsWritable = true
    /// `S_ISVTX` on the parent: the `/tmp` rule, where only an owner may unlink an item.
    var parentIsSticky = false
}

/// Process-wide facts, probed once per scan rather than once per candidate.
struct UninstallEnvironment: Hashable, Sendable {
    let home: String
    let hasFullDiskAccess: Bool
}

/// Why a candidate can or can't be trashed. Advisory: TCC is evaluated at the syscall.
enum UninstallProtection: String, Hashable, Sendable, CaseIterable {
    case removable
    case systemProtected
    case userLocked
    case notOwned
    case needsFullDiskAccess
    case parentNotWritable
    case notWritable
    case missing

    var isRemovable: Bool { self == .removable }

    /// Nil for exactly `.removable`; the row's lock icon keys off it.
    var lockReason: String? {
        switch self {
        case .removable:
            return nil
        case .systemProtected:
            return String(localized: "Part of macOS and protected by the system.")
        case .userLocked:
            return String(localized: "Locked in Finder. Unlock it in Get Info, then try again.")
        case .notOwned:
            return String(
                localized: "Owned by another user, in a folder that only lets owners remove things.")
        case .needsFullDiskAccess:
            return String(
                localized: """
                    Needs Full Disk Access, which Tinycast doesn’t request. \
                    Grant it in System Settings › Privacy & Security to include this item.
                    """)
        case .parentNotWritable:
            return String(
                localized: """
                    Its enclosing folder isn’t writable by you, and Tinycast never asks for an \
                    administrator password.
                    """)
        case .notWritable:
            return String(
                localized: """
                    Only an administrator can move it, as with App Store apps. \
                    Drag it to the Trash in Finder instead.
                    """)
        case .missing:
            return String(localized: "No longer on disk.")
        }
    }
}

enum UninstallProtectionRules {
    /// Precedence is asserted; a SIP file is also root-owned, and "part of macOS" reads best.
    static func classify(_ facts: PathFacts, environment: UninstallEnvironment) -> UninstallProtection {
        guard facts.exists else { return .missing }
        if facts.isSystemRestricted || facts.volumeIsReadOnly { return .systemProtected }
        if facts.isUserImmutable { return .userLocked }
        if !environment.hasFullDiskAccess,
            isTCCProtected(path: facts.path, home: environment.home)
        {
            return .needsFullDiskAccess
        }
        // Trashing renames out of the parent, so its write bit counts, not the item's owner.
        if !facts.parentIsWritable { return .parentNotWritable }
        // The one case where ownership does decide: a sticky parent lets only an owner unlink.
        if facts.parentIsSticky, !facts.isOwnedByCurrentUser { return .notOwned }
        // Moving a directory to a new parent rewrites its `..`, so its own write bit counts too.
        if facts.isDirectory, !facts.isWritable { return .notWritable }
        return .removable
    }

    /// Wider than the current roots, so adding one can't silently attempt a denied read.
    static func isTCCProtected(path: String, home: String) -> Bool {
        let relative = tccRelativePrefixes.contains { path.hasPrefix(home + "/" + $0) }
        return relative || path.hasPrefix("/Library/Application Support/com.apple.TCC")
    }

    /// Measured, never assumed: listing is not the test. See docs/features/uninstall.md.
    static let tccRelativePrefixes: [String] = [
        "Library/Containers/",
        "Library/Group Containers/",
        "Library/Cookies/",
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Calendars",
        "Library/Suggestions",
        "Library/HomeKit",
        "Library/IdentityServices",
        "Library/Sharing",
        "Library/Biome",
        "Library/Trial",
        "Library/Metadata/CoreSpotlight",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/MobileSync",
        "Library/Application Support/com.apple.sharedfilelist/"
    ]
}
