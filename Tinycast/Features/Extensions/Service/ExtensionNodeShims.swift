import CommonCrypto
import CryptoKit
import Darwin
import Foundation

/// Answered inline on the JS queue, so a blocking answer can never deadlock the UI.
final class ExtensionNodeShims: @unchecked Sendable {
    private let fileManager = FileManager.default
    private var fileHandles: [Int32: FileHandle] = [:]

    /// A lock flag like `O_EXLOCK` would block the JS queue with no way back.
    private static let openableFlags =
        O_RDONLY | O_WRONLY | O_RDWR | O_APPEND | O_CREAT | O_TRUNC | O_EXCL | O_NOFOLLOW
    private static let openFileLimit = 256

    func closeFiles() {
        for handle in fileHandles.values { try? handle.close() }
        fileHandles.removeAll()
    }

    /// Returns the JSON envelope `{ok, value}` / `{ok:false, error, code}` the JS side unwraps.
    func perform(api: String, method: String, argsJSON: String) -> String {
        let arguments = ExtensionRuntime.jsonArray(from: argsJSON)
        do {
            let value = try dispatch(api: api, method: method, arguments: arguments)
            return envelope(["ok": true, "value": value ?? NSNull()])
        } catch let error as ShimError {
            return envelope(["ok": false, "error": error.message, "code": error.code])
        } catch {
            return envelope(["ok": false, "error": error.localizedDescription, "code": "EUNKNOWN"])
        }
    }

    private func envelope(_ payload: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: payload)).map {
            String(decoding: $0, as: UTF8.self)
        } ?? #"{"ok":false,"error":"could not encode host result","code":"EUNKNOWN"}"#
    }

    struct ShimError: Error {
        let message: String
        let code: String

        static func noEntry(_ path: String, _ syscall: String) -> ShimError {
            ShimError(message: "ENOENT: no such file or directory, \(syscall) '\(path)'", code: "ENOENT")
        }
        static func failed(_ message: String, _ code: String = "EIO") -> ShimError {
            ShimError(message: message, code: code)
        }
    }

    private func dispatch(api: String, method: String, arguments: [Any]) throws -> Any? {
        switch api {
        case "fs": return try filesystem(method: method, arguments: arguments)
        case "os": return try operatingSystem(method: method)
        case "proc": return try process(method: method, arguments: arguments)
        case "crypto": return try crypto(method: method, arguments: arguments)
        case "zlib": return try compression(method: method, arguments: arguments)
        default: throw ShimError.failed("Unknown host module '\(api)'.", "ENOSYS")
        }
    }

    // MARK: - os

    private func operatingSystem(method: String) throws -> Any {
        if method == "uptime" { return ProcessInfo.processInfo.systemUptime }
        if method == "loadavg" {
            var averages = [Double](repeating: 0, count: 3)
            let count = averages.withUnsafeMutableBufferPointer {
                getloadavg($0.baseAddress, Int32($0.count))
            }
            guard count == Int32(averages.count) else {
                throw ShimError.failed("Could not read system load averages.")
            }
            return averages
        }
        if method == "freemem" {
            var statistics = vm_statistics64_data_t()
            var count = mach_msg_type_number_t(
                MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
            let result = withUnsafeMutablePointer(to: &statistics) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
                }
            }
            guard result == KERN_SUCCESS else {
                throw ShimError.failed("Could not read free memory (Mach error \(result)).")
            }
            return Double(statistics.free_count) * Double(getpagesize())
        }
        guard method == "cpus" else {
            throw ShimError.failed("os.\(method) is not supported.", "ENOSYS")
        }

        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount,
            &processorInfo, &processorInfoCount)
        guard result == KERN_SUCCESS, let processorInfo else {
            throw ShimError.failed("Could not read CPU load (Mach error \(result)).")
        }
        defer {
            _ = vm_deallocate(
                mach_task_self_, vm_address_t(UInt(bitPattern: processorInfo)),
                vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let millisecondsPerTick = 1_000 / Double(CLK_TCK)
        return (0..<Int(processorCount)).map { processor -> [String: Any] in
            let offset = processor * Int(CPU_STATE_MAX)
            func milliseconds(_ state: Int32) -> Double {
                Double(processorInfo[offset + Int(state)]) * millisecondsPerTick
            }
            return [
                "model": "Apple Silicon",
                "speed": 0,
                "times": [
                    "user": milliseconds(CPU_STATE_USER),
                    "nice": milliseconds(CPU_STATE_NICE),
                    "sys": milliseconds(CPU_STATE_SYSTEM),
                    "idle": milliseconds(CPU_STATE_IDLE),
                    "irq": 0
                ]
            ]
        }
    }

    // MARK: - fs

    private func filesystem(method: String, arguments: [Any]) throws -> Any? {
        func path(_ index: Int) throws -> String {
            guard let value = arguments[safe: index] as? String, !value.isEmpty else {
                throw ShimError.failed("fs.\(method) needs a path.", "EINVAL")
            }
            return (value as NSString).expandingTildeInPath
        }

        switch method {
        case "open":
            let target = try path(0)
            guard fileHandles.count < Self.openFileLimit else {
                throw ShimError.failed("EMFILE: too many open files, open '\(target)'", "EMFILE")
            }
            let flags = (arguments[safe: 1] as? NSNumber)?.int32Value ?? O_RDONLY
            let mode = (arguments[safe: 2] as? NSNumber)?.uint16Value ?? 0o666
            let descriptor = Darwin.open(
                target, (flags & Self.openableFlags) | O_CLOEXEC, mode_t(mode))
            guard descriptor >= 0 else { throw fileError("open", target) }
            fileHandles[descriptor] = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            return descriptor

        case "close", "read", "write":
            return try fileOperation(method: method, arguments: arguments)

        case "readFile":
            let target = try path(0)
            guard let data = fileManager.contents(atPath: target) else {
                throw ShimError.noEntry(target, "open")
            }
            return data.base64EncodedString()

        case "writeFile":
            let target = try path(0)
            let data = Data(base64Encoded: arguments[safe: 1] as? String ?? "") ?? Data()
            let append = arguments[safe: 2] as? Bool ?? false
            if append, let handle = FileHandle(forWritingAtPath: target) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                return nil
            }
            guard fileManager.createFile(atPath: target, contents: data) else {
                throw ShimError.failed("EACCES: could not write '\(target)'", "EACCES")
            }
            return nil

        // `createReadStream` walks a file a chunk at a time rather than materialising all of it.
        case "readRange":
            let target = try path(0)
            let offset = max(0, (arguments[safe: 1] as? NSNumber)?.intValue ?? 0)
            let count = max(0, (arguments[safe: 2] as? NSNumber)?.intValue ?? 0)
            guard let handle = FileHandle(forReadingAtPath: target) else {
                throw ShimError.noEntry(target, "open")
            }
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            return (try handle.read(upToCount: count) ?? Data()).base64EncodedString()

        case "exists":
            return fileManager.fileExists(atPath: try path(0))

        case "stat":
            let target = try path(0)
            let followLinks = !(arguments[safe: 1] as? Bool ?? false)
            return try stat(path: target, followLinks: followLinks)

        case "readdir":
            let target = try path(0)
            guard let names = try? fileManager.contentsOfDirectory(atPath: target) else {
                throw ShimError.noEntry(target, "scandir")
            }
            return names.map { name -> [String: Any] in
                let child = (target as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                let exists = fileManager.fileExists(atPath: child, isDirectory: &isDirectory)
                let isLink =
                    (try? fileManager.destinationOfSymbolicLink(atPath: child)) != nil
                return [
                    "name": name, "parentPath": target,
                    "_isFile": exists && !isDirectory.boolValue,
                    "_isDirectory": isDirectory.boolValue,
                    "_isSymbolicLink": isLink
                ]
            }

        case "mkdir":
            let target = try path(0)
            let recursive = arguments[safe: 1] as? Bool ?? false
            try fileManager.createDirectory(
                atPath: target, withIntermediateDirectories: recursive)
            return recursive ? target : nil

        case "remove":
            let target = try path(0)
            let force = arguments[safe: 2] as? Bool ?? false
            if !fileManager.fileExists(atPath: target) {
                if force { return nil }
                throw ShimError.noEntry(target, "unlink")
            }
            try fileManager.removeItem(atPath: target)
            return nil

        case "rename":
            let from = try path(0)
            let to = try path(1)
            if fileManager.fileExists(atPath: to) { try fileManager.removeItem(atPath: to) }
            try fileManager.moveItem(atPath: from, toPath: to)
            return nil

        case "copyFile":
            let from = try path(0)
            let to = try path(1)
            if fileManager.fileExists(atPath: to) { try fileManager.removeItem(atPath: to) }
            try fileManager.copyItem(atPath: from, toPath: to)
            return nil

        case "realpath":
            let target = try path(0)
            guard fileManager.fileExists(atPath: target) else {
                throw ShimError.noEntry(target, "realpath")
            }
            return URL(fileURLWithPath: target).resolvingSymlinksInPath().path

        case "chmod":
            let target = try path(0)
            guard let mode = arguments[safe: 1] as? NSNumber else {
                throw ShimError.failed("fs.chmod needs a mode.", "EINVAL")
            }
            guard fileManager.fileExists(atPath: target) else {
                throw ShimError.noEntry(target, "chmod")
            }
            try fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: target)
            return nil

        case "mkdtemp":
            // Node's contract: the prefix already includes the parent directory.
            let prefix = try path(0)
            let target = prefix + String(UUID().uuidString.prefix(6))
            try fileManager.createDirectory(atPath: target, withIntermediateDirectories: true)
            return target

        default:
            throw ShimError.failed("fs.\(method) is not supported.", "ENOSYS")
        }
    }

    private func fileOperation(method: String, arguments: [Any]) throws -> Any? {
        guard let descriptor = (arguments.first as? NSNumber)?.int32Value,
            let handle = fileHandles[descriptor]
        else { throw ShimError.failed("EBADF: bad file descriptor, \(method)", "EBADF") }
        switch method {
        case "close":
            fileHandles[descriptor] = nil
            do { try handle.close() } catch { throw fileError("close") }
            return nil
        case "read":
            let count = max(0, (arguments[safe: 1] as? NSNumber)?.intValue ?? 0)
            let position = (arguments[safe: 2] as? NSNumber)?.int64Value
            var data = Data(count: count)
            let read = data.withUnsafeMutableBytes { bytes in
                uninterrupted {
                    if let position {
                        return Darwin.pread(descriptor, bytes.baseAddress, count, off_t(position))
                    }
                    return Darwin.read(descriptor, bytes.baseAddress, count)
                }
            }
            guard read >= 0 else { throw fileError("read") }
            return data.prefix(read).base64EncodedString()
        default:
            let data = Data(base64Encoded: arguments[safe: 1] as? String ?? "") ?? Data()
            let position = (arguments[safe: 2] as? NSNumber)?.int64Value
            var written = 0
            // fs-minipass drops the remainder it is handed, so a short write truncates in silence.
            try data.withUnsafeBytes { bytes in
                while written < data.count {
                    let start = bytes.baseAddress!.advanced(by: written)
                    let remaining = data.count - written
                    let step = uninterrupted {
                        if let position {
                            return Darwin.pwrite(
                                descriptor, start, remaining, off_t(position) + off_t(written))
                        }
                        return Darwin.write(descriptor, start, remaining)
                    }
                    guard step > 0 else { throw fileError("write") }
                    written += step
                }
            }
            return written
        }
    }

    private func uninterrupted(_ body: () -> Int) -> Int {
        while true {
            let result = body()
            if result >= 0 || errno != EINTR { return result }
        }
    }

    private func fileError(_ syscall: String, _ path: String? = nil) -> ShimError {
        let code = errno
        let name = Self.errorNames[code] ?? "EIO"
        let target = path.map { " '\($0)'" } ?? ""
        return ShimError.failed(
            "\(name): \(String(cString: strerror(code))), \(syscall)\(target)", name)
    }

    private static let errorNames: [Int32: String] = [
        EACCES: "EACCES", EBADF: "EBADF", EEXIST: "EEXIST", EISDIR: "EISDIR", EMFILE: "EMFILE",
        EINVAL: "EINVAL", ENOENT: "ENOENT", ENOSPC: "ENOSPC", ENOTDIR: "ENOTDIR", EPERM: "EPERM",
        ESRCH: "ESRCH"
    ]

    private func stat(path: String, followLinks: Bool) throws -> [String: Any] {
        let attributes =
            followLinks
            ? try? fileManager.attributesOfItem(
                atPath: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
            : try? fileManager.attributesOfItem(atPath: path)
        guard let attributes else { throw ShimError.noEntry(path, "stat") }

        let type = attributes[.type] as? FileAttributeType
        func milliseconds(_ key: FileAttributeKey) -> Double {
            ((attributes[key] as? Date)?.timeIntervalSince1970 ?? 0) * 1000
        }
        return [
            "size": (attributes[.size] as? NSNumber)?.doubleValue ?? 0,
            "mode": (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0,
            "mtimeMs": milliseconds(.modificationDate),
            "atimeMs": milliseconds(.modificationDate),
            "ctimeMs": milliseconds(.creationDate),
            "birthtimeMs": milliseconds(.creationDate),
            "_isFile": type == .typeRegular,
            "_isDirectory": type == .typeDirectory,
            "_isSymbolicLink": type == .typeSymbolicLink
        ]
    }

    // MARK: - child_process

    private func process(method: String, arguments: [Any]) throws -> Any? {
        if method == "kill" { return try signal(arguments) }
        guard let spec = arguments.first as? [String: Any] else {
            throw ShimError.failed("No command given.", "EINVAL")
        }
        let timeout = (spec["timeout"] as? NSNumber)?.doubleValue

        switch method {
        case "run":
            // This runs on the JS queue, so a child that never exits would freeze the whole runtime.
            return try launch(spec).collect(timeout: timeout)
        case "start":
            let child = try launch(spec)
            // A detached child outlives its caller, so nothing ever waits on it.
            if spec["detached"] as? Bool != true {
                ExtensionAsyncProcess.enqueue(child, timeout: timeout)
            }
            return Int(child.task.processIdentifier)
        default:
            throw ShimError.failed("child_process.\(method) is not supported.", "ENOSYS")
        }
    }

    private func launch(_ spec: [String: Any]) throws -> ExtensionAsyncProcess.Child {
        let command = spec["command"] as? String ?? ""
        guard !command.isEmpty else { throw ShimError.failed("No command given.", "EINVAL") }
        let useShell = spec["shell"] as? Bool ?? false

        let task = Process()
        if useShell {
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", command]
        } else {
            guard let resolved = ExtensionAsyncProcess.resolveExecutable(command) else {
                throw ShimError.noEntry(command, "spawn")
            }
            task.executableURL = resolved
            task.arguments = (spec["args"] as? [String] ?? [])
        }
        if let cwd = spec["cwd"] as? String, !cwd.isEmpty {
            task.currentDirectoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath)
        }
        if let overrides = spec["env"] as? [String: String] {
            task.environment = overrides
        } else {
            task.environment = ProcessInfo.processInfo.environment
        }

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        let input = (spec["input"] as? String).flatMap { Data(base64Encoded: $0) }
        let stdin = input.map { _ in Pipe() }
        if let stdin { task.standardInput = stdin }

        do {
            try task.run()
        } catch {
            throw ShimError.failed("Could not run '\(command)': \(error.localizedDescription)", "ENOENT")
        }
        if let input, let stdin { feed(input, to: stdin) }
        return ExtensionAsyncProcess.Child(task: task, stdout: stdout, stderr: stderr)
    }

    /// A pipe holds 64 KB, so a larger input written before the child reads it would never finish.
    private func feed(_ input: Data, to stdin: Pipe) {
        let writer = stdin.fileHandleForWriting
        // A child that exits without reading everything must fail the write, not SIGPIPE Tinycast.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        DispatchQueue.global(qos: .userInitiated).async {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }
    }

    /// `process.kill`, refusing every target that would signal Tinycast along with the child.
    private func signal(_ arguments: [Any]) throws -> Any? {
        guard let pid = (arguments[safe: 0] as? NSNumber).flatMap({ Int32(exactly: $0.doubleValue) }),
            let signal = (arguments[safe: 1] as? NSNumber).flatMap({ Int32(exactly: $0.doubleValue) })
        else { throw ShimError.failed("kill EINVAL", "EINVAL") }
        guard pid > 0 || pid < -1, pid != getpid(), pid != -getpgrp() else {
            throw ShimError.failed("kill EPERM", "EPERM")
        }
        guard Darwin.kill(pid, signal) == 0 else {
            let name = Self.errorNames[errno] ?? "EIO"
            throw ShimError.failed("kill \(name)", name)
        }
        return nil
    }

    // MARK: - crypto

    private func crypto(method: String, arguments: [Any]) throws -> Any? {
        switch method {
        case "uuid":
            return UUID().uuidString.lowercased()

        case "random":
            let count = max(0, (arguments.first as? NSNumber)?.intValue ?? 0)
            var bytes = [UInt8](repeating: 0, count: count)
            for index in 0..<count { bytes[index] = UInt8.random(in: 0...255) }
            return Data(bytes).base64EncodedString()

        case "hash":
            let algorithm = arguments[safe: 0] as? String ?? "sha256"
            let data = Data(base64Encoded: arguments[safe: 1] as? String ?? "") ?? Data()
            return try digest(algorithm: algorithm, data: data).base64EncodedString()

        case "hmac":
            let algorithm = arguments[safe: 0] as? String ?? "sha256"
            let data = Data(base64Encoded: arguments[safe: 1] as? String ?? "") ?? Data()
            let key = Data(base64Encoded: arguments[safe: 2] as? String ?? "") ?? Data()
            return try authenticate(algorithm: algorithm, data: data, key: key).base64EncodedString()

        case "pbkdf2":
            let algorithm = arguments[safe: 0] as? String ?? ""
            let password = Data(base64Encoded: arguments[safe: 1] as? String ?? "") ?? Data()
            let salt = Data(base64Encoded: arguments[safe: 2] as? String ?? "") ?? Data()
            let iterations = (arguments[safe: 3] as? NSNumber)?.intValue ?? 0
            let length = (arguments[safe: 4] as? NSNumber)?.intValue ?? -1
            return try deriveKey(
                algorithm: algorithm, password: password, salt: salt,
                iterations: iterations, length: length
            ).base64EncodedString()

        case "cipher":
            let mode = arguments[safe: 0] as? String ?? ""
            let decrypt = arguments[safe: 1] as? Bool ?? false
            let key = Data(base64Encoded: arguments[safe: 2] as? String ?? "") ?? Data()
            let iv = Data(base64Encoded: arguments[safe: 3] as? String ?? "") ?? Data()
            let data = Data(base64Encoded: arguments[safe: 4] as? String ?? "") ?? Data()
            let padding = arguments[safe: 5] as? Bool ?? true
            return try crypt(
                mode: mode, decrypt: decrypt, key: key, iv: iv, data: data, padding: padding
            ).base64EncodedString()

        default:
            throw ShimError.failed("crypto.\(method) is not supported.", "ENOSYS")
        }
    }

    private func digest(algorithm: String, data: Data) throws -> Data {
        switch algorithm.lowercased() {
        case "md5": return Data(Insecure.MD5.hash(data: data))
        case "sha1": return Data(Insecure.SHA1.hash(data: data))
        case "sha256": return Data(SHA256.hash(data: data))
        case "sha384": return Data(SHA384.hash(data: data))
        case "sha512": return Data(SHA512.hash(data: data))
        default:
            throw ShimError.failed("Unsupported hash algorithm '\(algorithm)'.", "ENOSYS")
        }
    }

    private func authenticate(algorithm: String, data: Data, key: Data) throws -> Data {
        let symmetric = SymmetricKey(data: key)
        switch algorithm.lowercased() {
        case "md5": return Data(HMAC<Insecure.MD5>.authenticationCode(for: data, using: symmetric))
        case "sha1": return Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetric))
        case "sha256": return Data(HMAC<SHA256>.authenticationCode(for: data, using: symmetric))
        case "sha384": return Data(HMAC<SHA384>.authenticationCode(for: data, using: symmetric))
        case "sha512": return Data(HMAC<SHA512>.authenticationCode(for: data, using: symmetric))
        default:
            throw ShimError.failed("Unsupported HMAC algorithm '\(algorithm)'.", "ENOSYS")
        }
    }

    private func deriveKey(
        algorithm: String, password: Data, salt: Data, iterations: Int, length: Int
    ) throws -> Data {
        let function: Int
        switch algorithm.lowercased().replacing("-", with: "") {
        case "sha1": function = kCCPRFHmacAlgSHA1
        case "sha224": function = kCCPRFHmacAlgSHA224
        case "sha256": function = kCCPRFHmacAlgSHA256
        case "sha384": function = kCCPRFHmacAlgSHA384
        case "sha512": function = kCCPRFHmacAlgSHA512
        default: throw ShimError.failed("Invalid digest: \(algorithm)", "ERR_CRYPTO_INVALID_DIGEST")
        }
        guard (1...Int(Int32.max)).contains(iterations) else {
            throw ShimError.failed(#"The value of "iterations" is out of range."#, "ERR_OUT_OF_RANGE")
        }
        guard (0...Int(Int32.max)).contains(length) else {
            throw ShimError.failed(#"The value of "keylen" is out of range."#, "ERR_OUT_OF_RANGE")
        }
        guard length > 0 else { return Data() }

        var key = Data(count: length)
        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(function), UInt32(iterations),
                        keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), length)
                }
            }
        }
        guard status == kCCSuccess else {
            throw ShimError.failed("PBKDF2 failed (CommonCrypto status \(status)).")
        }
        return key
    }

    private func crypt(
        mode: String, decrypt: Bool, key: Data, iv: Data, data: Data, padding: Bool
    ) throws -> Data {
        guard mode == "cbc" || mode == "ecb" else {
            throw ShimError.failed("Unknown cipher", "ERR_CRYPTO_UNKNOWN_CIPHER")
        }
        // CCCrypt reads a full block from the IV pointer, whatever the buffer's real size.
        guard mode == "ecb" || iv.count == kCCBlockSizeAES128 else {
            throw ShimError.failed("Invalid initialization vector", "ERR_CRYPTO_INVALID_IV")
        }

        let blockSize = kCCBlockSizeAES128
        let wrongBlockLength = ShimError.failed(
            "error:1C80006B:Provider routines::wrong final block length",
            "ERR_OSSL_WRONG_FINAL_BLOCK_LENGTH")
        // CommonCrypto accepts padding OpenSSL rejects, which would hide a wrong key.
        let unpads = decrypt && padding
        guard !unpads || (!data.isEmpty && data.count % blockSize == 0) else { throw wrongBlockLength }

        var options = CCOptions(0)
        if padding && !decrypt { options |= CCOptions(kCCOptionPKCS7Padding) }
        if mode == "ecb" { options |= CCOptions(kCCOptionECBMode) }

        var output = Data(count: data.count + blockSize)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    data.withUnsafeBytes { dataBytes in
                        CCCrypt(
                            CCOperation(decrypt ? kCCDecrypt : kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES), options,
                            keyBytes.baseAddress, key.count,
                            mode == "ecb" ? nil : ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outputBytes.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard Int(status) != kCCAlignmentError else { throw wrongBlockLength }
        guard status == kCCSuccess else {
            throw ShimError.failed("AES failed (CommonCrypto status \(status)).")
        }
        output.count = written
        guard unpads else { return output }

        let padLength = Int(output.last ?? 0)
        guard (1...blockSize).contains(padLength),
            output.suffix(padLength).allSatisfy({ Int($0) == padLength })
        else {
            throw ShimError.failed("error:1C800064:Provider routines::bad decrypt", "ERR_OSSL_BAD_DECRYPT")
        }
        return output.dropLast(padLength)
    }

    // MARK: - zlib

    private func compression(method: String, arguments: [Any]) throws -> Any? {
        let data = Data(base64Encoded: arguments.first as? String ?? "") ?? Data()
        let result: Data
        switch method {
        case "gunzip": result = try Zlib.gunzip(data)
        case "inflate": result = try Zlib.inflate(data)
        case "inflateRaw": result = try Zlib.inflateRaw(data)
        case "gzip": result = try Zlib.gzip(data)
        case "deflate": result = try Zlib.deflate(data)
        case "deflateRaw": result = try Zlib.deflateRaw(data)
        default: throw ShimError.failed("zlib.\(method) is not supported.", "ENOSYS")
        }
        return result.base64EncodedString()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
