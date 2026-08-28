import Darwin
import Foundation

/// A command running under its own pseudo-terminal, as its own session leader.
///
/// A pipe is not enough for either half of what the output window promises. libc block-buffers
/// stdout the moment it is not a terminal, so a chatty command delivers nothing until it exits, and
/// stderr — which stays unbuffered — overtakes the stdout it followed. A pty restores line
/// buffering, and with it both live output and the order a terminal would show. Being a session
/// leader is separately what lets one signal reach the whole `a && b && c` chain rather than only
/// the shell in front of it.
final class PseudoTerminal: @unchecked Sendable {
    /// Everything the command writes to any of its three descriptors arrives here.
    let parentEnd: Int32
    let processID: pid_t

    private init(parentEnd: Int32, processID: pid_t) {
        self.parentEnd = parentEnd
        self.processID = processID
    }

    static func spawn(
        executable: String, arguments: [String], environment: [String: String],
        workingDirectory: String
    ) -> PseudoTerminal? {
        // POSIX names these the master and slave ends; these are the same two descriptors.
        var parentEnd: Int32 = 0
        var childEnd: Int32 = 0
        var settings = terminalSettings()
        guard openpty(&parentEnd, &childEnd, nil, &settings, nil) == 0 else { return nil }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        // The whole point: the child leads its own session, so `kill(-pid)` reaches every descendant.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addchdir(&actions, workingDirectory)
        for descriptor in Int32(0)...Int32(2) {
            posix_spawn_file_actions_adddup2(&actions, childEnd, descriptor)
        }
        posix_spawn_file_actions_addclose(&actions, parentEnd)
        posix_spawn_file_actions_addclose(&actions, childEnd)

        defer {
            posix_spawnattr_destroy(&attributes)
            posix_spawn_file_actions_destroy(&actions)
        }

        var processID: pid_t = 0
        let argv = CStringArray([executable] + arguments)
        let envp = CStringArray(environment.map { "\($0.key)=\($0.value)" })
        let status = posix_spawn(
            &processID, executable, &actions, &attributes, argv.pointers, envp.pointers)
        Darwin.close(childEnd)
        guard status == 0, processID > 0 else {
            Darwin.close(parentEnd)
            return nil
        }
        // Stands in for the `/dev/null` stdin a pipe run gets: a command that prompts reads EOF and
        // moves on instead of waiting on a terminal that will never answer.
        var endOfTransmission: UInt8 = 0x04
        _ = write(parentEnd, &endOfTransmission, 1)
        return PseudoTerminal(parentEnd: parentEnd, processID: processID)
    }

    /// Signals the session rather than the process — the negative pid is what reaches the children.
    func signalSession(_ signal: Int32) {
        guard processID > 0 else { return }
        kill(-processID, signal)
    }

    /// Blocks until the command exits. A signalled death reports the signal, the way a shell does.
    func wait() -> Int32 {
        var status: Int32 = 0
        while waitpid(processID, &status, 0) < 0 && errno == EINTR {}
        if status & 0x7F != 0 { return 128 + (status & 0x7F) }
        return (status >> 8) & 0xFF
    }

    func close() {
        Darwin.close(parentEnd)
    }

    /// Canonical so the kernel hands us whole lines, echo off so the EOF byte never comes back as
    /// text, and no output post-processing beyond the CR the window strips anyway.
    private static func terminalSettings() -> termios {
        var settings = termios()
        cfmakeraw(&settings)
        settings.c_lflag = tcflag_t(ICANON | ISIG)
        settings.c_oflag = tcflag_t(OPOST | ONLCR)
        return settings
    }
}

/// Owns the `strdup`ed argv/envp for one spawn. The array has to outlive the `posix_spawn` call, so
/// it is a real allocation rather than a Swift array's temporary buffer.
private final class CStringArray {
    let pointers: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    private let count: Int

    init(_ values: [String]) {
        count = values.count
        pointers = .allocate(capacity: count + 1)
        for (index, value) in values.enumerated() { pointers[index] = strdup(value) }
        pointers[count] = nil
    }

    deinit {
        for index in 0..<count { free(pointers[index]) }
        pointers.deallocate()
    }
}
