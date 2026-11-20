import Foundation

/// The frames both helpers and Settings' own process speak: bounded both ways, nil at a clean end.
@main
enum PipeFramingTests {
    struct Message: Codable, Equatable {
        let text: String
    }

    static func main() throws {
        var failures = 0
        func check(_ name: String, _ passed: Bool) {
            if !passed {
                failures += 1
                print("FAIL \(name)")
            }
        }

        let pipe = Pipe()
        try PipeFraming.write(Message(text: "hello"), to: pipe.fileHandleForWriting, maximum: 64)
        check(
            "a frame round-trips",
            try PipeFraming.read(Message.self, from: pipe.fileHandleForReading, maximum: 64)
                == Message(text: "hello"))

        let long = Message(text: String(repeating: "x", count: 100))
        check(
            "a write over its bound is refused",
            (try? PipeFraming.write(long, to: pipe.fileHandleForWriting, maximum: 64)) == nil)

        let oversized = Pipe()
        try PipeFraming.write(long, to: oversized.fileHandleForWriting, maximum: 256)
        check(
            "a frame over the reader's bound is corrupt",
            (try? PipeFraming.read(Message.self, from: oversized.fileHandleForReading, maximum: 64)) == nil)

        let closed = Pipe()
        try closed.fileHandleForWriting.close()
        check(
            "a clean end of stream reads nil",
            try PipeFraming.read(Message.self, from: closed.fileHandleForReading, maximum: 64) == nil)

        print("\(4 - failures)/4 framing checks passed")
        if failures > 0 { exit(1) }
    }
}
