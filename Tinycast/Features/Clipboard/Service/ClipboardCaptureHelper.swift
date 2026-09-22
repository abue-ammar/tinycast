import AppKit
import Darwin
import Foundation

@main
nonisolated enum ClipboardCaptureHelper {
    static func main() {
        let input = FileHandle.standardInput.fileDescriptor
        let output = FileHandle.standardOutput
        // Parent death mid-response is a closed pipe, not a signal that kills the helper.
        _ = fcntl(input, F_SETNOSIGPIPE, 1)
        _ = fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1)
        while let request = readRequest(from: input) {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(request.board))
            // AppKit objects from one read must not accumulate in the resident process.
            let payload = autoreleasepool { ClipboardCapture.read(pasteboard) }
            guard write(payload, id: request.id, to: output) else { return }
        }
    }

    private static func readRequest(from fd: Int32) -> ClipboardCaptureWire.Request? {
        var line = Data()
        while line.count <= 4096 {
            var byte: UInt8 = 0
            let count = Darwin.read(fd, &byte, 1)
            if count == 0 { return nil }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if byte == 10 { return ClipboardCaptureWire.request(from: line) }
            line.append(byte)
        }
        return nil
    }

    private static func write(
        _ payload: ClipboardCapture.Payload, id: UInt64, to output: FileHandle
    ) -> Bool {
        guard let header = ClipboardCaptureWire.header(for: payload, id: id) else { return false }
        do {
            try output.write(contentsOf: try ClipboardCaptureWire.headerLine(header))
            if case .png(let data) = payload {
                try output.write(contentsOf: data)
            }
            return true
        } catch {
            return false
        }
    }
}
