import Foundation

/// The 2024-11-05 HTTP+SSE stream, where the event's *name* matters: `endpoint`, then `message`s.
struct MCPEventStream: Sendable {
    struct Event: Equatable, Sendable {
        let name: String
        let data: String
    }

    private var buffer = Data()

    /// Fed whatever arrived; answers every event a blank line has completed.
    mutating func feed(_ data: Data) -> [Event] {
        buffer.append(data)
        var events: [Event] = []
        while let boundary = nextBoundary() {
            let frame = buffer[buffer.startIndex..<boundary.lowerBound]
            buffer.removeSubrange(buffer.startIndex..<boundary.upperBound)
            if let event = Self.event(in: frame) { events.append(event) }
        }
        return events
    }

    /// The endpoint a server announces, held to the stream's own origin so no credential follows
    /// a server elsewhere.
    static func endpoint(_ data: String, relativeTo stream: URL) -> URL? {
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed, relativeTo: stream)?.absoluteURL,
            url.scheme?.lowercased() == stream.scheme?.lowercased(),
            url.host?.lowercased() == stream.host?.lowercased(),
            url.port == stream.port
        else { return nil }
        return url
    }

    private func nextBoundary() -> Range<Data.Index>? {
        let lf = buffer.range(of: Data([0x0A, 0x0A]))
        let crlf = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
        switch (lf, crlf) {
        case (let lhs?, let rhs?): return lhs.lowerBound < rhs.lowerBound ? lhs : rhs
        case (let range?, nil), (nil, let range?): return range
        case (nil, nil): return nil
        }
    }

    private static func event(in frame: Data) -> Event? {
        let text = String(decoding: frame, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        var name = "message"
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue }
            let field = line.prefix { $0 != ":" }
            var value = line.dropFirst(field.count).dropFirst()
            if value.first == " " { value = value.dropFirst() }
            switch field {
            case "event": name = String(value)
            case "data": lines.append(String(value))
            default: continue
            }
        }
        return lines.isEmpty ? nil : Event(name: name, data: lines.joined(separator: "\n"))
    }
}
