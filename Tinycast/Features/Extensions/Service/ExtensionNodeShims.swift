import CryptoKit
import Foundation

/// Services the JS Node shims call *synchronously*. Safe to answer inline because none of this needs
/// the main actor: it all runs on `ExtensionRuntime`'s private JS queue, so a blocking answer can
/// never deadlock against the UI. Binary payloads cross as base64.
///
/// `@unchecked Sendable`: stateless apart from `FileManager.default`, which is thread-safe.
final class ExtensionNodeShims: @unchecked Sendable {
    private let fileManager = FileManager.default

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
        case "proc": return try process(method: method, arguments: arguments)
        case "crypto": return try crypto(method: method, arguments: arguments)
        case "zlib": return try compression(method: method, arguments: arguments)
        default: throw ShimError.failed("Unknown host module '\(api)'.", "ENOSYS")
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
        guard method == "run", let spec = arguments.first as? [String: Any] else {
            throw ShimError.failed("child_process.\(method) is not supported.", "ENOSYS")
        }
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
        if let inputBase64 = spec["input"] as? String, let data = Data(base64Encoded: inputBase64) {
            let stdin = Pipe()
            task.standardInput = stdin
            try? stdin.fileHandleForWriting.write(contentsOf: data)
            try? stdin.fileHandleForWriting.close()
        }

        do {
            try task.run()
        } catch {
            throw ShimError.failed("Could not run '\(command)': \(error.localizedDescription)", "ENOENT")
        }

        // This runs on the JS queue, so a child that never exits would freeze the whole runtime.
        let (outData, errData) = ExtensionAsyncProcess.drain(
            task, stdout: stdout, stderr: stderr,
            timeout: (spec["timeout"] as? NSNumber)?.doubleValue)

        return [
            "stdout": outData.base64EncodedString(),
            "stderr": errData.base64EncodedString(),
            "status": Int(task.terminationStatus),
            "signal": task.terminationReason == .uncaughtSignal ? "SIGTERM" : NSNull()
        ]
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
