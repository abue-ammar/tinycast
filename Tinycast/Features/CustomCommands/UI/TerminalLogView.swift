import AppKit
import SwiftUI

/// The log itself. An `NSTextView` rather than a `Text`: a quarter-megabyte of output re-laid-out
/// on every append is seconds of work, and only the text system appends in place.
struct TerminalLogView: NSViewRepresentable {
    let run: CommandRun

    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let inset = CGSize(width: Theme.Spacing.xxl, height: Theme.Spacing.xs)
    /// Within this of the bottom counts as following along, matching the chat transcript's band.
    private static let tailSlack = Theme.Spacing.chatFollowTailSlack

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        /// What is on screen. A new run and a trimmed log both make the drawn text wrong, and
        /// neither is visible from the revision alone — Run Again starts a fresh run back at zero.
        var runID: UUID?
        var generation = -1
        var revision = 0
        var interpreter = ANSIInterpreter()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = Self.inset
        // Zeroed so the inset alone sets the left edge, lining the log up with the header text.
        textView.textContainer?.lineFragmentPadding = 0
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
            let storage = textView.textStorage
        else { return }
        let coordinator = context.coordinator
        let following = isAtBottom(scrollView)

        let isSameRun = coordinator.runID == run.id && coordinator.generation == run.generation
        guard !isSameRun || run.revision != coordinator.revision else { return }

        // One step on is the streaming case and costs only the new text. Anything else — Run Again
        // starting a fresh run, a trim, a window reopened onto a finished one — is drawn whole.
        let isAppend = isSameRun && run.revision == coordinator.revision + 1
        if !isAppend {
            coordinator.interpreter = ANSIInterpreter()
            storage.setAttributedString(NSAttributedString())
        }
        coordinator.runID = run.id
        coordinator.generation = run.generation
        coordinator.revision = run.revision
        coordinator.interpreter.render(isAppend ? run.delta : run.log, into: storage, font: Self.font)
        if following { textView.scrollToEndOfDocument(nil) }
    }

    /// A reader who scrolled up is left alone; arriving back at the end resumes the follow.
    private func isAtBottom(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let visible = scrollView.contentView.bounds
        return visible.maxY >= documentView.frame.height - Self.tailSlack
    }
}

/// Turns a terminal's byte stream into attributed text: SGR colour carried across chunks, a
/// carriage return rewinding the line it lands on, and everything else it emits dropped.
struct ANSIInterpreter {
    private var colour: NSColor = .labelColor
    private var isBold = false
    private var isDim = false
    /// A control sequence can be split across reads, so a partial one waits for the rest.
    private var partial = ""

    mutating func render(_ text: String, into storage: NSTextStorage, font: NSFont) {
        var run = ""
        var characters = Array(partial + text)[...]
        partial = ""

        func flush() {
            guard !run.isEmpty else { return }
            storage.append(NSAttributedString(string: run, attributes: attributes(font)))
            run = ""
        }

        while let character = characters.first {
            characters = characters.dropFirst()
            switch character {
            case "\u{1B}":
                guard let sequence = Self.take(&characters) else {
                    // Truncated mid-sequence: hold it back rather than printing the escape.
                    partial = "\u{1B}" + String(characters)
                    characters = characters.prefix(0)
                    continue
                }
                flush()
                apply(sequence)
            case "\r":
                // A progress bar redraws its line in place; appending the frames would stack them.
                flush()
                rewindLine(in: storage)
            default:
                run.append(character)
            }
        }
        flush()
    }

    private func attributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
        let face = isBold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        return [.font: face, .foregroundColor: isDim ? colour.withAlphaComponent(0.6) : colour]
    }

    /// Reads one CSI/OSC body; nil when the sequence has not all arrived yet.
    private static func take(_ characters: inout ArraySlice<Character>) -> String? {
        guard let introducer = characters.first else { return nil }
        characters = characters.dropFirst()
        guard introducer == "[" else {
            // OSC and the rest carry no meaning here; swallow to their terminator.
            while let character = characters.first, character != "\u{07}", character != "\u{1B}" {
                characters = characters.dropFirst()
            }
            return ""
        }
        var body = ""
        while let character = characters.first {
            characters = characters.dropFirst()
            body.append(character)
            if character.isLetter { return body }
        }
        return nil
    }

    private mutating func apply(_ sequence: String) {
        // Only SGR is drawn; cursor moves and erases have no meaning in a document.
        guard sequence.hasSuffix("m") else { return }
        let codes = sequence.dropLast().split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        var index = 0
        while index < max(codes.count, 1) {
            let code = codes.isEmpty ? 0 : codes[index]
            switch code {
            case 0: colour = .labelColor; isBold = false; isDim = false
            case 1: isBold = true
            case 2: isDim = true
            case 22: isBold = false; isDim = false
            case 30...37: colour = Self.palette[code - 30]
            case 90...97: colour = Self.palette[code - 90]
            case 39: colour = .labelColor
            // Extended colour carries its own parameters; skipping them keeps the rest in step.
            case 38, 48: index += codes.count > index + 1 && codes[index + 1] == 5 ? 2 : 4
            default: break
            }
            index += 1
        }
    }

    /// Deletes back to the start of the last line, which is what a bare carriage return means.
    private func rewindLine(in storage: NSTextStorage) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let lineStart = text.range(
            of: "\n", options: .backwards, range: NSRange(location: 0, length: text.length))
        let start = lineStart.location == NSNotFound ? 0 : lineStart.location + 1
        guard start < text.length else { return }
        storage.deleteCharacters(in: NSRange(location: start, length: text.length - start))
    }

    /// System colours so the log stays legible in both appearances, unlike raw terminal values —
    /// orange stands in for yellow, which is unreadable on a light background.
    private static let palette: [NSColor] = [
        .secondaryLabelColor, .systemRed, .systemGreen, .systemOrange,
        .systemBlue, .systemPurple, .systemTeal, .labelColor
    ]
}
