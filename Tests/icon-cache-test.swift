import Foundation

@main
@MainActor
struct IconCacheTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        var generation = IconCacheGeneration()
        let captured = generation.value
        var stored: [Int] = []

        let current = generation.publish(1, capturedAt: captured) { stored.append($0) }
        expect(current == 1, "a current decode reaches its caller")
        expect(stored == [1], "a current decode populates the cache")

        generation.invalidate()
        let stale = generation.publish(2, capturedAt: captured) { stored.append($0) }
        expect(stale == 2, "a stale decode still reaches its active caller")
        expect(stored == [1], "a stale decode cannot repopulate the cache")

        print(failures == 0 ? "Icon cache tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
