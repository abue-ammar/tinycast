// Adapted from MonitorControl, © MonitorControl contributors; MIT notice in NOTICE.md.
import Foundation

struct MonitorIdentity: Sendable {
    var location = ""
    var name = ""
    var serial: Int64 = 0
    var edidVendor = ""
    var edidProduct = ""

    func score(_ other: Self) -> Int {
        if !location.isEmpty, location == other.location { return 100 }
        guard !edidVendor.isEmpty, edidVendor == other.edidVendor,
            !edidProduct.isEmpty, edidProduct == other.edidProduct
        else { return 0 }
        if serial != 0, other.serial != 0, serial != other.serial { return 0 }
        return 2 + (serial != 0 && serial == other.serial ? 10 : 0)
            + (name.caseInsensitiveCompare(other.name) == .orderedSame ? 1 : 0)
    }

    static func matches(displays: [Self], services: [Self]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (displayIndex, display) in displays.enumerated() {
            let scores = services.map { display.score($0) }
            guard let best = scores.max(), best > 0,
                scores.filter({ $0 == best }).count == 1,
                let serviceIndex = scores.firstIndex(of: best)
            else { continue }
            let competitors = displays.map { $0.score(services[serviceIndex]) }
            guard competitors.max() == best, competitors.filter({ $0 == best }).count == 1 else { continue }
            result[displayIndex] = serviceIndex
        }
        return result
    }

    static func audioTarget(name: String, displays: [UInt32: String], displayTransport: Bool) -> UInt32? {
        guard displayTransport else { return nil }
        let normalized = normalize(name)
        guard !normalized.isEmpty else { return nil }
        let matches = displays.filter { normalize($0.value) == normalized }
        return matches.count == 1 ? matches.first?.key : nil
    }

    private static func normalize(_ name: String) -> String {
        name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }
}
