import Foundation

@main
struct RankingTest {
    @MainActor
    static func main() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ranking-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var clock = Date(timeIntervalSince1970: 2_000_000_000)
        let store = LauncherRankingStore(fileURL: fileURL) { clock }
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        let whatsApp = "net.whatsapp.WhatsApp"
        let wick = "com.example.wick"

        check("unvisited result has no boost", store.boost(itemKey: whatsApp, query: "w") == 0)

        store.record(itemKey: whatsApp, query: "Wha")
        let firstBoost = store.boost(itemKey: whatsApp, query: "w")
        check("visit teaches first query prefix", firstBoost > 0)
        check("visit teaches full normalized query", store.boost(itemKey: whatsApp, query: "WHA") > 0)
        check("visit does not teach a different query", store.boost(itemKey: whatsApp, query: "wa") == 0)

        store.record(itemKey: whatsApp, query: "w")
        check(
            "frequency increases the boost",
            store.boost(itemKey: whatsApp, query: "w") > firstBoost)

        clock.addTimeInterval(60 * 86_400)
        check(
            "recency decays over time",
            store.boost(itemKey: whatsApp, query: "w") < firstBoost)

        for _ in 0..<100 { store.record(itemKey: whatsApp, query: "w") }
        clock.addTimeInterval(60 * 86_400)
        let oldFrequentBoost = store.boost(itemKey: whatsApp, query: "w")
        for _ in 0..<8 { store.record(itemKey: wick, query: "w") }
        check(
            "a newer habit can overtake an old frequent result",
            store.boost(itemKey: wick, query: "w") > oldFrequentBoost)

        let persistedWickBoost = store.boost(itemKey: wick, query: "w")
        let reloaded = LauncherRankingStore(fileURL: fileURL) { clock }
        check(
            "records persist across store instances",
            reloaded.boost(itemKey: wick, query: "w") == persistedWickBoost)

        reloaded.reset(itemKey: whatsApp)
        check("per-item reset clears every learned query", !reloaded.hasRanking(for: whatsApp))
        check("per-item reset preserves other items", reloaded.hasRanking(for: wick))

        reloaded.resetAll()
        check("global reset clears all learned ranking", reloaded.isEmpty)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
