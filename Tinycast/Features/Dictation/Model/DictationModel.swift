import Foundation

enum DictationModel: String, CaseIterable, Identifiable, Codable, Sendable {
    struct ParakeetConfiguration: Sendable {
        let joint: String
        let blankToken: Int
        let encoderUsesGPU: Bool
    }
    enum Family: String, CaseIterable, Identifiable {
        case parakeet = "Parakeet", qwen = "Qwen"
        var id: Self { self }
        var summary: String {
            self == .parakeet
                ? String(localized: "Fast and memory-efficient")
                : String(localized: "More languages, but slower")
        }
    }
    case redux
    case ultra
    case qwenSmall = "qwen-0.6b"
    case qwenLarge = "qwen-1.7b"

    var id: Self { self }
    var title: String { "\(family.rawValue) · \(variantTitle)" }
    var variantTitle: String {
        switch self {
        case .ultra: "Ultra"
        case .redux: "Redux"
        case .qwenSmall: "0.6B"
        case .qwenLarge: "1.7B"
        }
    }

    var summary: String {
        switch self {
        case .redux: String(localized: "Lightweight and efficient.")
        case .ultra: String(localized: "Higher accuracy, larger download.")
        case .qwenSmall: String(localized: "Smaller and faster.")
        case .qwenLarge: String(localized: "Higher accuracy, more memory.")
        }
    }

    var family: Family {
        switch self {
        case .ultra, .redux: .parakeet
        case .qwenSmall, .qwenLarge: .qwen
        }
    }
    var isQwen: Bool { family == .qwen }
    var parakeetConfiguration: ParakeetConfiguration? {
        switch self {
        case .ultra, .redux:
            .init(joint: "JointDecisionv3", blankToken: 8192, encoderUsesGPU: self == .redux)
        case .qwenSmall, .qwenLarge: nil
        }
    }
    var coverage: String {
        switch self {
        case .ultra, .redux: String(localized: "25 languages")
        case .qwenSmall, .qwenLarge: String(localized: "30 languages and 22 Chinese dialects")
        }
    }
    var folderName: String { isQwen ? rawValue : "parakeet-\(rawValue)" }
    var approximateInstalledMegabytes: Int {
        switch self {
        case .ultra: 632
        case .redux: 220
        case .qwenSmall: 940
        case .qwenLarge: 2352
        }
    }

    var components: Set<String> {
        if isQwen { return ["encoder.mlmodelc", "decoder.mlmodelc", "embedding.mlmodelc", "config.json"] }
        guard let configuration = parakeetConfiguration else { return [] }
        return [
            "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
            configuration.joint + ".mlmodelc", "parakeet_vocab.json"
        ]
    }

    var requiredFiles: Set<String> { components.union(isQwen ? ["vocab.json", "merges.txt"] : []) }

    var repository: String {
        switch self {
        case .ultra, .redux: "FluidInference/\(folderName)-coreml"
        case .qwenSmall: "UniMocha/Qwen3-ASR-0.6B-CoreML-INT8"
        case .qwenLarge: "UniMocha/Qwen3-ASR-1.7B-CoreML-INT8"
        }
    }

    var revision: String {
        switch self {
        case .ultra: "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
        case .redux: "8c5ef97a29cd120dc76b354b3f22b7fec3b486f9"
        case .qwenSmall: "27b7a26835d7c2cd1cf774b4c490eb5519ca71a0"
        case .qwenLarge: "06312fbac1383cd22e1000c28b017634e03251a2"
        }
    }
}
