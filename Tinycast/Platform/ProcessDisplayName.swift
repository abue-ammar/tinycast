import Foundation

/// The name process lists show for this process, which otherwise is its bundle's name.
enum ProcessDisplayName {
    /// LaunchServices has no public setter; a macOS without this SPI keeps the bundle's name.
    static func set(_ name: String) {
        typealias CurrentApplication = @convention(c) () -> Unmanaged<AnyObject>?
        typealias SetInformation =
            @convention(c) (
                Int32, AnyObject, CFString, CFString, UnsafeMutableRawPointer?
            ) -> OSStatus
        let path =
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/"
            + "LaunchServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        defer { dlclose(handle) }
        let defaultSession: Int32 = -2
        guard let current = dlsym(handle, "_LSGetCurrentApplicationASN"),
            let setInformation = dlsym(handle, "_LSSetApplicationInformationItem"),
            let displayNameKey = dlsym(handle, "_kLSDisplayNameKey"),
            let application = unsafeBitCast(current, to: CurrentApplication.self)()
        else { return }
        _ = unsafeBitCast(setInformation, to: SetInformation.self)(
            defaultSession, application.takeUnretainedValue(), displayNameKey.load(as: CFString.self),
            name as CFString, nil)
    }
}
