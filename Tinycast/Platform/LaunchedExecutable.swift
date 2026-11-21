import Foundation

/// This app's executable as found at launch; once it changes, the bundle holds another build.
@MainActor
enum LaunchedExecutable {
    struct Replaced: Error {}

    private static var launched: Identity?

    /// First thing in `main`, before anything can replace the file.
    static func pin() {
        launched = .current
    }

    static func checkUnchanged() throws {
        guard let launched, Identity.current == launched else { throw Replaced() }
    }

    /// The inode catches a swapped bundle; the timestamp, a binary rewritten in place.
    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let seconds: Int
        let nanoseconds: Int

        static var current: Identity? {
            var status = stat()
            guard let path = Bundle.main.executablePath, stat(path, &status) == 0 else { return nil }
            return Identity(
                device: status.st_dev, inode: status.st_ino, seconds: status.st_mtimespec.tv_sec,
                nanoseconds: status.st_mtimespec.tv_nsec)
        }
    }
}
