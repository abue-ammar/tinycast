import SwiftUI

/// Maps Raycast's `Icon` / `Color` / `Image.ImageLike` values onto what the palette can draw.
enum ExtensionImage {
    /// A resolved icon: an SF Symbol, a file on disk, a remote URL, or a bare emoji/text glyph.
    enum Source: Equatable {
        case symbol(String)
        case file(String)
        case remote(URL)
        case glyph(String)
    }

    struct Resolved: Equatable {
        var source: Source
        var tint: Color?
        var isCircular = false
    }

    /// An `ImageLike`: a string, or `{source, tintColor, mask, fallback}` with a themed `source`.
    static func resolve(_ value: RenderValue?, assetsPath: String?) -> Resolved? {
        guard let value else { return nil }
        switch value {
        case .string(let text):
            guard let source = source(from: text, assetsPath: assetsPath) else { return nil }
            return Resolved(source: source)
        case .object(let fields):
            // Raycast's icon-with-tooltip form; unwrap only when it looks like one, not when themed.
            if let wrapped = fields["value"]?.objectValue,
                wrapped["source"] != nil || wrapped["value"] != nil
            {
                return resolve(.object(wrapped), assetsPath: assetsPath)
            }
            let raw = fields["source"] ?? fields["value"]
            let text = string(from: raw)
            guard let text, let source = source(from: text, assetsPath: assetsPath) else {
                // A tinted icon with no usable source still deserves the fallback tile.
                return nil
            }
            return Resolved(
                source: source,
                tint: color(fields["tintColor"]),
                isCircular: fields["mask"]?.stringValue == "circle")
        default:
            return nil
        }
    }

    /// `{light, dark}` themed sources collapse to the dark variant — the app is locked to dark.
    private static func string(from value: RenderValue?) -> String? {
        switch value {
        case .string(let text): return text
        case .object(let fields): return fields["dark"]?.stringValue ?? fields["light"]?.stringValue
        default: return nil
        }
    }

    private static func source(from text: String, assetsPath: String?) -> Source? {
        guard !text.isEmpty else { return nil }
        // Icon enum values all carry the `-16` suffix Raycast's generated enum uses.
        if text.hasSuffix("-16") {
            if let digits = numberGlyph(forIcon: text) { return .glyph(digits) }
            if let symbol = symbolName(forIcon: text) { return .symbol(symbol) }
        }
        if let url = URL(string: text), let scheme = url.scheme, scheme.hasPrefix("http") {
            return .remote(url)
        }
        if text.hasPrefix("/") || text.hasPrefix("~") {
            return .file((text as NSString).expandingTildeInPath)
        }
        // A bare name is an asset relative to the extension's `assets/` directory.
        if let assetsPath, text.contains(".") {
            return .file((assetsPath as NSString).appendingPathComponent(text))
        }
        // Anything else short enough to be an emoji or a couple of initials is drawn as a glyph.
        return text.count <= 4 ? .glyph(text) : nil
    }

    static func color(_ value: RenderValue?) -> Color? {
        guard let value else { return nil }
        if let text = value.stringValue { return color(named: text) }
        if let fields = value.objectValue {
            return color(named: fields["dark"]?.stringValue ?? fields["light"]?.stringValue ?? "")
        }
        return nil
    }

    private static func color(named raw: String) -> Color? {
        switch raw {
        case "raycast-blue": return .blue
        case "raycast-green": return .green
        case "raycast-magenta": return Color(red: 0.85, green: 0.24, blue: 0.62)
        case "raycast-orange": return .orange
        case "raycast-purple": return .purple
        case "raycast-red": return .red
        case "raycast-yellow": return .yellow
        case "raycast-primary-text": return .primary
        case "raycast-secondary-text": return Theme.Colors.textSecondary
        default:
            // Extensions also pass raw hex.
            return hexColor(raw)
        }
    }

    private static func hexColor(_ raw: String) -> Color? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("#") else { return nil }
        text.removeFirst()
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8, let value = UInt32(text, radix: 16) else {
            return nil
        }
        let hasAlpha = text.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let alpha = hasAlpha ? Double(value & 0xff) / 255 : 1
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    /// SF only enumerates 0…50, so draw all hundred as glyphs and they look alike.
    private static func numberGlyph(forIcon icon: String) -> String? {
        guard icon.hasPrefix("number-") else { return nil }
        let digits = icon.dropFirst("number-".count).dropLast(3)
        guard digits.count == 2, let value = Int(digits) else { return nil }
        return String(value)
    }

    /// Only icons carrying meaning are hand-mapped; a generic shape beats an empty slot.
    private static func symbolName(forIcon icon: String) -> String? {
        let name = String(icon.dropLast(3))
        if let mapped = symbolMap[name] { return mapped }
        // Many names are already close to a symbol; try the obvious transforms before the fallback.
        let candidates = [name, name.replacingOccurrences(of: "-", with: ".")]
        for candidate in candidates
        where NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil {
            return candidate
        }
        return "circle.dashed"
    }

    private static let symbolMap: [String: String] = [
        "add-person": "person.badge.plus", "airplane": "airplane", "alarm": "alarm",
        "app-window": "macwindow", "app-window-list": "macwindow.badge.plus",
        "arrow-clockwise": "arrow.clockwise", "arrow-counter-clockwise": "arrow.counterclockwise",
        "arrow-down": "arrow.down", "arrow-left": "arrow.left", "arrow-right": "arrow.right",
        "arrow-up": "arrow.up", "arrow-ne": "arrow.up.right",
        "arrows-expand": "arrow.up.left.and.arrow.down.right",
        "at-symbol": "at", "bell": "bell", "bell-disabled": "bell.slash", "bookmark": "bookmark",
        "bug": "ant", "calculator": "plusminus", "calendar": "calendar", "camera": "camera",
        "check": "checkmark", "check-circle": "checkmark.circle", "check-rosette": "checkmark.seal",
        "chevron-down": "chevron.down", "chevron-up": "chevron.up", "chevron-left": "chevron.left",
        "chevron-right": "chevron.right", "circle": "circle", "circle-filled": "circle.fill",
        "circle-progress-100": "circle.fill", "clipboard": "doc.on.clipboard", "clock": "clock",
        "cloud": "cloud", "code": "chevron.left.forwardslash.chevron.right",
        "code-block": "curlybraces", "cog": "gearshape", "coin": "dollarsign.circle",
        "copy-clipboard": "doc.on.doc", "cd": "opticaldiscdrive", "check-list": "checklist",
        "desktop": "desktopcomputer", "document": "doc", "dot": "circle.fill",
        "download": "arrow.down.circle", "duplicate": "plus.square.on.square",
        "envelope": "envelope", "eraser": "eraser", "exclamationmark": "exclamationmark",
        "exclamationmark-2": "exclamationmark.2", "exclamationmark-3": "exclamationmark.3",
        "eye": "eye", "eye-disabled": "eye.slash", "eye-dropper": "eyedropper",
        "finder": "folder", "folder": "folder", "forward": "goforward", "gauge": "speedometer",
        "gear": "gearshape", "globe": "globe", "hammer": "hammer", "hard-drive": "internaldrive",
        "hashtag": "number", "heart": "heart", "heart-disabled": "heart.slash", "house": "house",
        "image": "photo", "info": "info.circle", "key": "key", "keyboard": "keyboard",
        "layers": "square.3.layers.3d", "light-bulb": "lightbulb", "link": "link",
        "list": "list.bullet", "lock": "lock", "lock-disabled": "lock.open", "lock-unlocked": "lock.open",
        "magnifying-glass": "magnifyingglass", "map": "map", "maximize": "arrow.up.left.and.arrow.down.right",
        "megaphone": "megaphone", "memory-chip": "memorychip", "message": "message",
        "microphone": "mic", "minimize": "arrow.down.right.and.arrow.up.left", "minus": "minus",
        "minus-circle": "minus.circle", "mobile": "iphone", "moon": "moon", "mug-steam": "cup.and.saucer",
        "music": "music.note", "network": "network", "paperclip": "paperclip",
        "pie-chart": "chart.pie", "bar-chart": "chart.bar", "line-chart": "chart.xyaxis.line",
        "box": "shippingbox", "brush": "paintbrush", "power": "power", "pulse": "waveform.path.ecg",
        "pause": "pause", "pencil": "pencil",
        "person": "person", "person-circle": "person.circle", "person-lines": "person.text.rectangle",
        "phone": "phone", "pin": "pin", "pin-disabled": "pin.slash", "play": "play",
        "play-filled": "play.fill", "plug": "powerplug", "plus": "plus", "plus-circle": "plus.circle",
        "plus-square": "plus.square", "printer": "printer", "question-mark": "questionmark",
        "question-mark-circle": "questionmark.circle", "quotation-marks": "quote.opening",
        "raindrop": "drop", "redo": "arrow.uturn.forward", "reply": "arrowshape.turn.up.left",
        "repeat": "repeat", "rewind": "gobackward", "rocket": "airplane.departure",
        "rotate-anti-clockwise": "rotate.left", "rotate-clockwise": "rotate.right",
        "ruler": "ruler", "save-document": "square.and.arrow.down", "shield": "shield",
        "sidebar-left": "sidebar.left", "sidebar-right": "sidebar.right", "snippets": "text.badge.plus",
        "speaker-high": "speaker.wave.3", "speaker-off": "speaker.slash", "star": "star",
        "star-circle": "star.circle", "star-disabled": "star.slash", "stars": "sparkles",
        "stop": "stop", "stopwatch": "stopwatch", "sun": "sun.max", "switch": "switch.2",
        "tag": "tag", "terminal": "terminal", "text": "textformat", "text-cursor": "character.cursor.ibeam",
        "text-input": "character.cursor.ibeam", "three-dots": "ellipsis", "thumbs-down": "hand.thumbsdown",
        "thumbs-up": "hand.thumbsup", "trash": "trash", "tray": "tray", "twitter": "bird",
        "undo": "arrow.uturn.backward", "upload": "arrow.up.circle", "video": "video",
        "wallet": "creditcard", "wand": "wand.and.stars", "warning": "exclamationmark.triangle",
        "waveform": "waveform", "weights": "scalemass", "wifi": "wifi", "wifi-disabled": "wifi.slash",
        "window": "macwindow", "wrench-screwdriver": "wrench.and.screwdriver", "xmark": "xmark",
        "xmark-circle": "xmark.circle", "xmark-circle-filled": "xmark.circle.fill",
        "xmark-top-right-square": "xmark.square",
        // No plausible transform; every value was checked, since an unknown name draws a placeholder.
        "airplane-filled": "airplane", "airplane-landing": "airplane.arrival",
        "airplane-takeoff": "airplane.departure",
        "alarm-ringing": "bell.and.waves.left.and.right.fill", "align-centre": "text.aligncenter",
        "align-left": "text.alignleft", "align-right": "text.alignright", "anchor": "water.waves",
        "app-window-grid-2x2": "square.grid.2x2", "app-window-grid-3x3": "square.grid.3x3",
        "app-window-sidebar-left": "sidebar.left", "app-window-sidebar-right": "sidebar.right",
        "arrow-down-circle-filled": "arrow.down.circle.fill",
        "arrow-left-circle-filled": "arrow.left.circle.fill",
        "arrow-right-circle-filled": "arrow.right.circle.fill",
        "arrow-up-circle-filled": "arrow.up.circle.fill",
        "arrows-contract": "arrow.down.right.and.arrow.up.left", "band-aid": "bandage.fill",
        "bank-note": "banknote.fill", "bar-code": "barcode", "bath-tub": "bathtub.fill",
        "battery": "battery.100percent", "battery-charging": "battery.100percent.bolt",
        "battery-disabled": "battery.0percent", "bike": "bicycle", "blank-document": "doc",
        "bluetooth": "dot.radiowaves.right", "boat": "sailboat.fill",
        "bolt-disabled": "bolt.slash", "bullet-points": "list.bullet", "bulls-eye": "target",
        "bulls-eye-missed": "scope", "buoy": "lifepreserver",
        "center": "rectangle.center.inset.filled", "chess-piece": "crown.fill",
        "chevron-down-small": "chevron.down", "chevron-left-small": "chevron.left",
        "chevron-right-small": "chevron.right", "chevron-up-down": "chevron.up.chevron.down",
        "chevron-up-small": "chevron.up", "circle-disabled": "circle.slash",
        "circle-ellipsis": "ellipsis.circle", "circle-progress": "circle.dotted",
        "circle-progress-25": "progress.indicator", "circle-progress-50": "progress.indicator",
        "circle-progress-75": "progress.indicator",
        "clear-formatting": "textformat.abc.dottedunderline", "cloud-lightning": "cloud.bolt.fill",
        "coins": "dollarsign.circle.fill", "command-symbol": "command",
        "compass": "location.north.circle", "computer-chip": "cpu",
        "contrast": "circle.lefthalf.filled", "credit-card": "creditcard",
        "crypto": "bitcoinsign.circle", "delete-document": "trash",
        "devices": "laptopcomputer.and.iphone", "dna": "atom", "droplets": "drop.fill",
        "edit-shape": "pencil.and.outline", "ellipsis-vertical": "ellipsis",
        "emoji": "face.smiling", "emoji-sad": "face.dashed", "female": "figure.stand.dress",
        "film-strip": "film", "filter": "line.3.horizontal.decrease.circle",
        "fingerprint": "touchid", "footprints": "shoeprints.fill",
        "forward-filled": "forward.fill", "fountain-tip": "pencil.tip",
        "full-signal": "cellularbars", "game-controller": "gamecontroller",
        "geopin": "mappin.and.ellipse", "germ": "microbe.fill", "glasses": "eyeglasses",
        "globe-01": "globe", "goal": "target", "heading": "textformat.size",
        "heartbeat": "waveform.path.ecg", "highlight": "highlighter",
        "important-01": "exclamationmark.circle", "info-01": "info.circle", "italics": "italic",
        "leaderboard": "list.number", "light-bulb-off": "lightbulb.slash",
        "livestream-01": "dot.radiowaves.left.and.right",
        "livestream-disabled-01": "antenna.radiowaves.left.and.right.slash",
        "logout": "rectangle.portrait.and.arrow.right", "lorry": "truck.box.fill",
        "lowercase": "textformat.abc", "male": "figure.stand", "mask": "theatermasks.fill",
        "medical-support": "cross.case.fill", "memory-stick": "memorychip",
        "microphone-disabled": "mic.slash", "minus-circle-filled": "minus.circle.fill",
        "monitor": "display", "moon-down": "moonset.fill", "moon-up": "moonrise.fill",
        "mountain": "mountain.2.fill", "mouse": "computermouse.fill",
        "move": "arrow.up.and.down.and.arrow.left.and.right", "new-document": "doc.badge.plus",
        "new-folder": "folder.badge.plus", "patch": "bandage.fill", "pause-filled": "pause.fill",
        "phone-ringing": "phone.badge.waveform.fill", "plus-circle-filled": "plus.circle.fill",
        "plus-minus-divide-multiply": "plusminus",
        "plus-top-right-square": "plus.square.on.square", "print": "printer",
        "quicklink": "arrow.up.right.square", "quote-block": "text.quote",
        "racket": "figure.tennis", "raycast-logo-neg": "macwindow.on.rectangle",
        "raycast-logo-pos": "macwindow.on.rectangle", "remove-person": "person.badge.minus",
        "replace": "rectangle.2.swap", "replace-one": "arrow.triangle.2.circlepath",
        "rewind-filled": "backward.fill", "rss": "dot.radiowaves.up.forward",
        "shield-01": "shield", "short-paragraph": "text.alignleft", "signal-0": "cellularbars",
        "signal-1": "cellularbars", "signal-2": "cellularbars", "signal-3": "cellularbars",
        "soccer-ball": "soccerball", "speaker-down": "speaker.wave.1.fill",
        "speaker-low": "speaker.wave.1.fill", "speaker-on": "speaker.wave.2.fill",
        "speaker-up": "speaker.wave.3.fill", "speech-bubble": "bubble.left",
        "speech-bubble-active": "bubble.left.fill",
        "speech-bubble-important": "exclamationmark.bubble",
        "square-ellipsis": "ellipsis.rectangle", "stacked-bars-1": "chart.bar.fill",
        "stacked-bars-2": "chart.bar.fill", "stacked-bars-3": "chart.bar.fill",
        "stacked-bars-4": "chart.bar.fill", "stop-filled": "stop.fill", "store": "storefront.fill",
        "strike-through": "strikethrough", "swatch": "swatchpalette.fill", "tack": "pin.fill",
        "tack-disabled": "pin.slash", "temperature": "thermometer.medium",
        "tennis-ball": "tennisball.fill", "text-selection": "selection.pin.in.out",
        "thumbs-down-filled": "hand.thumbsdown.fill", "thumbs-up-filled": "hand.thumbsup.fill",
        "torch": "flashlight.on.fill", "train": "train.side.front.car", "two-people": "person.2",
        "uppercase": "textformat", "video-disabled": "video.slash", "windsock": "wind",
        "wrist-watch": "applewatch", "x-mark-circle": "xmark.circle",
        "x-mark-circle-filled": "xmark.circle.fill", "x-mark-circle-half-dash": "xmark.circle",
        "x-mark-top-right-square": "xmark.square"
    ]
}

/// A resolved icon at row size; an unresolvable one draws the faint tile, so rows never jump.
struct ExtensionIconView: View {
    let resolved: ExtensionImage.Resolved?
    var size: CGFloat = Theme.Size.rowIcon
    /// Opt-in, and off for row icons: a playing GIF at 24pt is noise, and a list is hundreds of rows.
    var animates = false
    @State private var loaded: NSImage?

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .task(id: cacheKey) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch resolved?.source {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.62, weight: .regular))
                .symbolRenderingMode(resolved?.tint == nil ? .hierarchical : .monochrome)
                .foregroundStyle(resolved?.tint ?? Theme.Colors.textSecondary)
                .frame(width: size, height: size)
        case .glyph(let text):
            Text(text)
                .font(.system(size: size * 0.72))
                .frame(width: size, height: size)
        case .file, .remote:
            if let loaded {
                // Only a multi-frame image pays for `NSImageView`; a still stays on SwiftUI's path.
                if animates, loaded.isAnimated {
                    AnimatedImageView(image: loaded)
                } else {
                    Image(nsImage: loaded).resizable().aspectRatio(contentMode: .fit)
                }
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            .fill(Color.white.opacity(0.06))
    }

    private var shape: AnyShape {
        resolved?.isCircular == true
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }

    private var cacheKey: String {
        switch resolved?.source {
        case .file(let path): return "file:" + path
        case .remote(let url): return "remote:" + url.absoluteString
        default: return ""
        }
    }

    /// An animating tile takes the image as shipped; the fitted path would hand back one frame.
    private func load() async {
        switch resolved?.source {
        case .file(let path):
            loaded =
                animates
                ? await ExtensionIconCache.loadOriginalAsync(atPath: path)
                : await ExtensionIconCache.loadAsync(atPath: path)
        case .remote(let url):
            loaded = await ExtensionIconCache.loadRemoteAsync(url, asIcon: !animates)
        default:
            loaded = nil
        }
    }
}
