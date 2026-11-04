import Foundation
import Security

/// Proves a staged bundle is ours: sealed, and signed by the Tinycast team under Developer ID.
enum BundleSignature {
    /// The team, not the certificate — a leaf is reissued on renewal and on a rename.
    static let developerID = """
        anchor apple generic \
        and certificate leaf[subject.OU] = "J656U8XZ93" \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
        """

    /// No `notarized`: its ticket lookup can hit the network, and the chain already proves ownership.
    static func isTrusted(_ bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode,
            SecRequirementCreateWithString(developerID as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { return false }
        // An unsealed bundle can claim any identity, and a nested helper is where one hides.
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
    }
}
