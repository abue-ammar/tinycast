import Foundation

struct NoteDisplayProjection: Sendable, Equatable {
    enum Affinity: Sendable {
        case upstream
        case downstream
    }

    enum SegmentKind: Sendable, Equatable {
        case identity
        case elision
        case replacement
    }

    enum Style: Sendable, Equatable {
        case heading(level: Int)
        case strong
        case emphasis
        case strongEmphasis
        case strikethrough
        case inlineCode
        case link
        case image
        case blockquote
        case listMarker
        case taskMarker
        case horizontalRule
        case codeBlock
        case markup
    }

    struct Segment: Sendable, Equatable {
        let kind: SegmentKind
        let sourceRange: NSRange
        let displayRange: NSRange
    }

    struct StyleSpan: Sendable, Equatable {
        let style: Style
        let range: NSRange
    }

    struct TaskAnchor: Sendable, Equatable {
        let sourceRange: NSRange
        let displayRange: NSRange
        let checked: Bool
        let label: String
    }

    struct LinkAnchor: Sendable, Equatable {
        let sourceRange: NSRange
        let displayRange: NSRange
        let destination: String
    }

    struct CopyAnchor: Sendable, Equatable {
        let sourceRange: NSRange
        let displayRange: NSRange
    }

    let sourceLength: Int
    let string: String
    let segments: [Segment]
    let styles: [StyleSpan]
    let tasks: [TaskAnchor]
    let links: [LinkAnchor]
    let copyAnchors: [CopyAnchor]
    let activeRange: NSRange?

    static func build(
        source: String,
        presentation: NoteMarkdownPresentation,
        activeSourceLocation: Int?
    ) -> NoteDisplayProjection {
        let text = source as NSString
        let active = activeSourceLocation.flatMap(presentation.activeConstruct(at:))
        let transforms = transformations(
            source: text,
            presentation: presentation,
            activeRange: active?.range)
        var output = ""
        var segments: [Segment] = []
        var sourceLocation = 0
        var displayLocation = 0

        for transform in transforms {
            guard transform.range.location >= sourceLocation else { continue }
            if transform.range.location > sourceLocation {
                let range = NSRange(
                    location: sourceLocation,
                    length: transform.range.location - sourceLocation)
                let value = text.substring(with: range)
                output += value
                let length = (value as NSString).length
                segments.append(
                    Segment(
                        kind: .identity,
                        sourceRange: range,
                        displayRange: NSRange(location: displayLocation, length: length)))
                displayLocation += length
            }
            output += transform.replacement
            let replacementLength = (transform.replacement as NSString).length
            segments.append(
                Segment(
                    kind: transform.replacement.isEmpty ? .elision : .replacement,
                    sourceRange: transform.range,
                    displayRange: NSRange(location: displayLocation, length: replacementLength)))
            sourceLocation = NSMaxRange(transform.range)
            displayLocation += replacementLength
        }

        if sourceLocation < text.length {
            let range = NSRange(location: sourceLocation, length: text.length - sourceLocation)
            let value = text.substring(with: range)
            output += value
            segments.append(
                Segment(
                    kind: .identity,
                    sourceRange: range,
                    displayRange: NSRange(
                        location: displayLocation,
                        length: (value as NSString).length)))
        }
        if segments.isEmpty {
            segments = [
                Segment(
                    kind: .identity,
                    sourceRange: NSRange(location: 0, length: text.length),
                    displayRange: NSRange(location: 0, length: text.length))
            ]
        }

        var projection = NoteDisplayProjection(
            sourceLength: text.length,
            string: output,
            segments: segments,
            styles: [],
            tasks: [],
            links: [],
            copyAnchors: [],
            activeRange: active?.range)
        projection = projection.addingMetadata(source: text, presentation: presentation, active: active)
        return projection
    }

    func displayLocation(forSourceLocation location: Int, affinity: Affinity) -> Int {
        let clamped = min(max(0, location), sourceLength)
        if clamped == sourceLength { return (string as NSString).length }
        guard let segment = segment(containingSourceLocation: clamped, affinity: affinity) else {
            return (string as NSString).length
        }
        let lower = segment.sourceRange.location
        let upper = NSMaxRange(segment.sourceRange)
        switch segment.kind {
        case .identity:
            return segment.displayRange.location + min(clamped - lower, segment.displayRange.length)
        case .elision:
            return segment.displayRange.location
        case .replacement:
            if clamped == lower { return segment.displayRange.location }
            if clamped == upper { return NSMaxRange(segment.displayRange) }
            return affinity == .upstream
                ? segment.displayRange.location : NSMaxRange(segment.displayRange)
        }
    }

    func sourceLocation(forDisplayLocation location: Int, affinity: Affinity) -> Int {
        let displayLength = (string as NSString).length
        let clamped = min(max(0, location), displayLength)
        if clamped == displayLength { return sourceLength }
        guard let segment = segment(containingDisplayLocation: clamped, affinity: affinity) else {
            return sourceLength
        }
        let lower = segment.displayRange.location
        let upper = NSMaxRange(segment.displayRange)
        switch segment.kind {
        case .identity:
            return segment.sourceRange.location + min(clamped - lower, segment.sourceRange.length)
        case .elision:
            return affinity == .upstream
                ? segment.sourceRange.location : NSMaxRange(segment.sourceRange)
        case .replacement:
            if clamped == lower { return segment.sourceRange.location }
            if clamped == upper { return NSMaxRange(segment.sourceRange) }
            return affinity == .upstream
                ? segment.sourceRange.location : NSMaxRange(segment.sourceRange)
        }
    }

    func displayRange(forSourceRange range: NSRange) -> NSRange {
        let start = displayLocation(forSourceLocation: range.location, affinity: .downstream)
        if range.length == 0 { return NSRange(location: start, length: 0) }
        let end = displayLocation(forSourceLocation: NSMaxRange(range), affinity: .upstream)
        return NSRange(location: min(start, end), length: abs(end - start))
    }

    func sourceRange(forDisplayRange range: NSRange) -> NSRange {
        let start = sourceLocation(forDisplayLocation: range.location, affinity: .downstream)
        if range.length == 0 { return NSRange(location: start, length: 0) }
        let end = sourceLocation(forDisplayLocation: NSMaxRange(range), affinity: .upstream)
        return NSRange(location: min(start, end), length: abs(end - start))
    }

    func sourceRange(forCopyingDisplayRange range: NSRange) -> NSRange {
        let displayLength = (string as NSString).length
        guard range.length > 0 else { return sourceRange(forDisplayRange: range) }
        if range.location == 0, NSMaxRange(range) == displayLength {
            return NSRange(location: 0, length: sourceLength)
        }
        var result = sourceRange(forDisplayRange: range)
        for anchor in copyAnchors
        where range.location <= anchor.displayRange.location
            && NSMaxRange(range) >= NSMaxRange(anchor.displayRange)
        {
            result = NSUnionRange(result, anchor.sourceRange)
        }
        return result
    }

    func sourceRange(forReplacingDisplayRange range: NSRange) -> NSRange {
        sourceRange(forCopyingDisplayRange: range)
    }

    private struct Transform {
        let range: NSRange
        let replacement: String
        let priority: Int
    }

    private static func transformations(
        source: NSString,
        presentation: NoteMarkdownPresentation,
        activeRange: NSRange?
    ) -> [Transform] {
        var result: [Transform] = []
        for construct in presentation.constructs {
            if let activeRange, NSIntersectionRange(activeRange, construct.range).length > 0 {
                continue
            }
            switch construct.kind {
            case .image, .orderedList:
                continue
            case .unorderedList:
                if let marker = construct.markerRanges.first {
                    result.append(Transform(range: marker, replacement: "•", priority: 20))
                }
            case .task(let checked):
                if let marker = construct.markerRanges.first {
                    result.append(
                        Transform(range: marker, replacement: checked ? "☑" : "☐", priority: 30))
                }
            case .horizontalRule:
                result.append(Transform(range: construct.range, replacement: "\u{200B}", priority: 50))
            default:
                result.append(contentsOf: construct.markerRanges.map {
                    Transform(range: $0, replacement: "", priority: 10)
                })
            }
        }
        result.sort {
            if $0.range.location == $1.range.location {
                if $0.priority == $1.priority { return $0.range.length > $1.range.length }
                return $0.priority > $1.priority
            }
            return $0.range.location < $1.range.location
        }
        var accepted: [Transform] = []
        for transform in result {
            if let last = accepted.last,
                NSIntersectionRange(last.range, transform.range).length > 0
            {
                continue
            }
            accepted.append(transform)
        }
        return accepted.sorted { $0.range.location < $1.range.location }
    }

    private func segment(containingSourceLocation location: Int, affinity: Affinity) -> Segment? {
        var lower = 0
        var upper = segments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if segments[middle].sourceRange.location <= location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        var index = max(0, lower - 1)
        if affinity == .upstream, segments[index].sourceRange.location == location, index > 0 {
            index -= 1
        }
        let segment = segments[index]
        return location <= NSMaxRange(segment.sourceRange) ? segment : nil
    }

    private func segment(containingDisplayLocation location: Int, affinity: Affinity) -> Segment? {
        var lower = 0
        var upper = segments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if segments[middle].displayRange.location <= location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        var index = max(0, lower - 1)
        if affinity == .upstream, segments[index].displayRange.location == location, index > 0 {
            index -= 1
        }
        let segment = segments[index]
        return location <= NSMaxRange(segment.displayRange) ? segment : nil
    }

    private func addingMetadata(
        source: NSString,
        presentation: NoteMarkdownPresentation,
        active: NoteMarkdownPresentation.Construct?
    ) -> NoteDisplayProjection {
        var styles: [StyleSpan] = []
        var tasks: [TaskAnchor] = []
        var links: [LinkAnchor] = []
        var copyAnchors: [CopyAnchor] = []
        for construct in presentation.constructs {
            let style = style(for: construct.kind)
            let contentDisplayRange = displayRange(forSourceRange: construct.contentRange)
            let activeHorizontalRule: Bool
            if case .horizontalRule = construct.kind {
                activeHorizontalRule = active?.range == construct.range
            } else {
                activeHorizontalRule = false
            }
            if contentDisplayRange.length > 0, !activeHorizontalRule {
                styles.append(StyleSpan(style: style, range: contentDisplayRange))
            }
            switch construct.kind {
            case .task(let checked):
                guard active?.range != construct.range, let marker = construct.markerRanges.first else {
                    continue
                }
                let markerDisplayRange = displayRange(forSourceRange: marker)
                let label = source.substring(with: construct.contentRange)
                    .trimmingCharacters(in: .whitespaces)
                tasks.append(
                    TaskAnchor(
                        sourceRange: marker,
                        displayRange: markerDisplayRange,
                        checked: checked,
                        label: label.isEmpty ? "Task" : label))
            case .link(let destination):
                links.append(
                    LinkAnchor(
                        sourceRange: construct.range,
                        displayRange: contentDisplayRange,
                        destination: destination))
            default:
                break
            }
            if active?.range != construct.range, contentDisplayRange.length > 0 {
                copyAnchors.append(
                    CopyAnchor(
                        sourceRange: construct.range,
                        displayRange: contentDisplayRange))
            }
        }
        return NoteDisplayProjection(
            sourceLength: sourceLength,
            string: string,
            segments: segments,
            styles: styles,
            tasks: tasks,
            links: links,
            copyAnchors: copyAnchors,
            activeRange: activeRange)
    }

    private func style(for kind: NoteMarkdownPresentation.Construct.Kind) -> Style {
        switch kind {
        case .heading(let level): .heading(level: level)
        case .strong: .strong
        case .emphasis: .emphasis
        case .strongEmphasis: .strongEmphasis
        case .strikethrough: .strikethrough
        case .inlineCode: .inlineCode
        case .link: .link
        case .image: .image
        case .blockquote: .blockquote
        case .unorderedList, .orderedList: .listMarker
        case .task: .taskMarker
        case .horizontalRule: .horizontalRule
        case .codeBlock: .codeBlock
        }
    }
}
