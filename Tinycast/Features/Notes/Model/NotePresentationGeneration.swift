import Foundation

struct NotePresentationGeneration: Sendable, Equatable {
    private(set) var current = 0

    mutating func advance() {
        current &+= 1
    }

    func permitsCompletion(capturedGeneration: Int, isVisible: Bool) -> Bool {
        isVisible && capturedGeneration == current
    }

    func permitsPresentation(capturedGeneration: Int) -> Bool {
        capturedGeneration == current
    }
}
