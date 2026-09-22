import AppKit

/// Turns a file or pasted picture into what a composer stages; every call runs off-main.
nonisolated enum ChatAttachmentReader {
    /// Carries what a staged file becomes across the detached read.
    struct Staged: Sendable {
        let payload: ChatAttachment.Payload
        let name: String
        let preview: Data?
    }

    /// A refusal rather than a nil, so one bad file in a paste is named instead of vanishing.
    enum Outcome: Sendable {
        case staged(Staged)
        case failed(ChatAttachmentRefusal)
    }

    private static let maxImageEdge: CGFloat = 1_568

    static func image(_ data: Data) -> Outcome {
        guard let png = boundedPNG(data) else { return .failed(.size) }
        return .staged(
            Staged(
                payload: .image(AIImage(data: png, mimeType: "image/png")), name: "Image",
                preview: preview(png)))
    }

    /// Sized before it is read, so a four-gigabyte CSV can never be slurped into memory.
    static func read(_ file: URL) -> Outcome {
        let name = file.lastPathComponent
        guard let kind = AIAttachmentPolicy.kind(forFileName: name) else {
            return .failed(.unsupported(file.pathExtension.lowercased()))
        }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let ceiling =
            kind == .text ? AIAttachmentBudget.maxInlinedTextBytes : AIAttachmentBudget.maxBytes
        guard size <= ceiling else { return .failed(kind == .text ? .textTooLong : .size) }
        guard let bytes = try? Data(contentsOf: file) else { return .failed(.unreadable) }
        let mimeType = AIAttachmentPolicy.mimeType(forFileName: name)
        switch kind {
        case .image:
            guard let png = boundedPNG(bytes) else { return .failed(.unreadable) }
            return .staged(
                Staged(
                    payload: .image(AIImage(data: png, mimeType: "image/png")), name: name,
                    preview: preview(png)))
        case .pdf:
            return .staged(
                Staged(
                    payload: .document(AIDocument(data: bytes, mimeType: mimeType, name: name)),
                    name: name, preview: nil))
        case .text:
            // Re-encoded from the decoded string, so undecodable bytes refuse rather than mojibake.
            guard let decoded = String(data: bytes, encoding: .utf8) else {
                return .failed(.undecodable)
            }
            return .staged(
                Staged(
                    payload: .document(
                        AIDocument(data: Data(decoded.utf8), mimeType: mimeType, name: name)),
                    name: name, preview: nil))
        }
    }

    /// The pill's thumbnail, encoded once here rather than decoded per keystroke in the header.
    private static func preview(_ png: Data) -> Data? {
        guard let source = NSBitmapImageRep(data: png) else { return nil }
        return scaled(source, toFit: 40)
    }

    private static func boundedPNG(_ data: Data) -> Data? {
        guard let source = NSBitmapImageRep(data: data) else { return nil }
        guard max(source.pixelsWide, source.pixelsHigh) > Int(maxImageEdge) else {
            return source.representation(using: .png, properties: [:])
        }
        return scaled(source, toFit: maxImageEdge)
    }

    private static func scaled(_ source: NSBitmapImageRep, toFit edge: CGFloat) -> Data? {
        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        let scale = min(1, edge / max(width, height))
        let size = NSSize(
            width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
        guard
            let scaled = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: scaled)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return scaled.representation(using: .png, properties: [:])
    }
}
