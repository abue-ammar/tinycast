import Foundation

protocol DictationRecognizer {
    func transcribe(_ samples: [Float], language: String?) throws -> String
}

extension QwenRecognizer: DictationRecognizer {}
extension ParakeetRecognizer: DictationRecognizer {
    func transcribe(_ samples: [Float], language: String?) throws -> String {
        try transcribe(samples)
    }
}

@main
enum DictationHelper {
    static func main() {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        guard fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { exit(1) }
        var recognizer: (any DictationRecognizer)?
        var loaded: DictationModel?
        do {
            while let request = try PipeFraming.read(
                DictationWire.Request.self, from: input, maximum: DictationWire.maximumMessageBytes)
            {
                try DictationTensor.checkParent()
                guard (1...DictationWire.maximumSamples).contains(request.sampleCount),
                    request.directory.isFileURL
                else {
                    throw DictationInferenceError.invalidAudio
                }
                if loaded != request.model {
                    recognizer = nil
                    loaded = nil
                    do {
                        recognizer = try autoreleasepool { () throws -> any DictationRecognizer in
                            request.model.isQwen
                                ? try QwenRecognizer(directory: request.directory)
                                : try ParakeetRecognizer(directory: request.directory, model: request.model)
                        }
                        loaded = request.model
                    } catch {
                        try PipeFraming.write(
                            DictationWire.Response(id: request.id, status: .failed), to: output,
                            maximum: DictationWire.maximumMessageBytes)
                        continue
                    }
                }
                guard let recognizer else { throw DictationInferenceError.incompatibleModel }
                try PipeFraming.write(
                    DictationWire.Response(id: request.id, status: .ready), to: output,
                    maximum: DictationWire.maximumMessageBytes)
                try autoreleasepool {
                    let data = try PipeFraming.readExactly(
                        request.sampleCount * MemoryLayout<Float>.size, from: input)
                    let samples = [Float](unsafeUninitializedCapacity: request.sampleCount) { buffer, count in
                        data.withUnsafeBytes { bytes in
                            UnsafeMutableRawBufferPointer(buffer).copyMemory(from: bytes)
                        }
                        count = request.sampleCount
                    }
                    guard samples.allSatisfy({ $0.isFinite }) else {
                        throw DictationInferenceError.invalidAudio
                    }
                    do {
                        let text = try recognizer.transcribe(samples, language: request.language)
                        try PipeFraming.write(
                            DictationWire.Response(id: request.id, status: .result, text: text), to: output,
                            maximum: DictationWire.maximumMessageBytes)
                    } catch {
                        try PipeFraming.write(
                            DictationWire.Response(id: request.id, status: .failed), to: output,
                            maximum: DictationWire.maximumMessageBytes)
                    }
                }
            }
        } catch {
            exit(1)
        }
    }
}
