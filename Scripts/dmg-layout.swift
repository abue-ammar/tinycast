#!/usr/bin/env swift
// Dress a mounted, writable DMG volume as the installer window. Usage: dmg-layout.swift <volume> <app>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else { fail("usage: dmg-layout.swift <volume> <app>") }
let volume = URL(fileURLWithPath: arguments[0], isDirectory: true)
let appName = arguments[1]

// Points, from the window content's top-left. Finder centres each label 83pt below its icon.
enum Layout {
    static let canvas = CGSize(width: 640, height: 360)
    // Icon art starts ~51pt above centre and pills end 96pt below; this centres that span, lifted.
    static let iconRow: CGFloat = 152
    static let applications = CGPoint(x: 160, y: iconRow)
    static let app = CGPoint(x: 480, y: iconRow)
    static let labelOffset: CGFloat = 83
    static let iconSize = 128.0
    static let textSize = 13.0
    static let titleBarHeight: CGFloat = 32
    static let windowOrigin = CGPoint(x: 200, y: 200)
}

enum Palette {
    static let ink = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    static let lavender = CGColor(srgbRed: 0.886, green: 0.835, blue: 1, alpha: 1)
    static func brand(_ alpha: CGFloat) -> CGColor {
        CGColor(srgbRed: 0.525, green: 0.231, blue: 1, alpha: alpha)
    }
}

// MARK: - Background

func drawArrow(in context: CGContext) {
    let tip = CGPoint(x: Layout.canvas.width / 2 - 57, y: Layout.applications.y)
    let length: CGFloat = 114, shaft: CGFloat = 11, headLength: CGFloat = 26, headHeight: CGFloat = 40
    context.setFillColor(Palette.lavender)
    context.addPath(
        CGPath(
            roundedRect: CGRect(
                x: tip.x + headLength - 2, y: tip.y - shaft / 2,
                width: length - headLength + 2, height: shaft),
            cornerWidth: shaft / 2, cornerHeight: shaft / 2, transform: nil))
    context.move(to: tip)
    context.addLine(to: CGPoint(x: tip.x + headLength, y: tip.y - headHeight / 2))
    context.addLine(to: CGPoint(x: tip.x + headLength, y: tip.y + headHeight / 2))
    context.closePath()
    context.fillPath()
}

// Both pills share one width, sized for the longest label Finder may show, extension included.
func drawLabelPills(in context: CGContext) {
    let font = CTFontCreateUIFontForLanguage(.system, Layout.textSize, nil)
    let textWidth =
        ["Applications", appName].map { text in
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(
                    string: text,
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font as Any]))
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }.max() ?? 0
    let size = CGSize(width: (textWidth + 38).rounded(.up), height: 26)
    context.setFillColor(Palette.lavender)
    for icon in [Layout.applications, Layout.app] {
        let center = CGPoint(x: icon.x, y: icon.y + Layout.labelOffset)
        let pill = CGRect(
            x: center.x - size.width / 2, y: center.y - size.height / 2,
            width: size.width, height: size.height)
        context.addPath(
            CGPath(
                roundedRect: pill, cornerWidth: size.height / 2,
                cornerHeight: size.height / 2, transform: nil))
    }
    context.fillPath()
}

func renderBackground(scale: CGFloat) -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: Int(Layout.canvas.width * scale), height: Int(Layout.canvas.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fail("cannot create a drawing context") }
    context.scaleBy(x: scale, y: -scale)
    context.translateBy(x: 0, y: -Layout.canvas.height)

    context.setFillColor(Palette.ink)
    context.fill(CGRect(origin: .zero, size: Layout.canvas))
    let glowCenter = CGPoint(x: 190, y: 40)
    if let glow = CGGradient(
        colorsSpace: space,
        colors: [Palette.brand(0.2), Palette.brand(0.07), Palette.brand(0)] as CFArray,
        locations: [0, 0.45, 1])
    {
        context.drawRadialGradient(
            glow, startCenter: glowCenter, startRadius: 0,
            endCenter: glowCenter, endRadius: 330, options: [])
    }
    drawArrow(in: context)
    drawLabelPills(in: context)

    guard let image = context.makeImage() else { fail("cannot render the background") }
    return image
}

// One TIFF holding 1x and 2x, so Finder picks the sharp one on a Retina display.
func writeBackground(to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 2, nil)
    else { fail("cannot write \(url.path)") }
    for scale in [1.0, 2.0] {
        CGImageDestinationAddImage(
            destination, renderBackground(scale: scale),
            [
                kCGImagePropertyDPIWidth: 72 * scale,
                kCGImagePropertyDPIHeight: 72 * scale,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]
            ] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

// MARK: - .DS_Store

extension Data {
    mutating func appendBigEndian(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendCode(_ code: String) {
        precondition(code.utf8.count == 4, "a four-character code")
        append(contentsOf: Array(code.utf8))
    }
}

struct Record {
    enum Value {
        case long(UInt32)
        case blob(Data)
    }

    let file: String
    let code: String
    let value: Value

    var encoded: Data {
        var data = Data()
        data.appendBigEndian(UInt32(file.utf16.count))
        file.utf16.forEach { data.appendBigEndian($0) }
        data.appendCode(code)
        switch value {
        case .long(let number):
            data.appendCode("long")
            data.appendBigEndian(number)
        case .blob(let bytes):
            data.appendCode("blob")
            data.appendBigEndian(UInt32(bytes.count))
            data.append(bytes)
        }
        return data
    }
}

// Buddy-allocated blocks: allocator header at 0, tree header at 32, block table 2048, leaf 4096.
func storeData(_ records: [Record]) -> Data {
    let sorted = records.sorted { ($0.file.lowercased(), $0.code) < ($1.file.lowercased(), $1.code) }
    var leaf = Data()
    leaf.appendBigEndian(UInt32(0))
    leaf.appendBigEndian(UInt32(sorted.count))
    sorted.forEach { leaf.append($0.encoded) }
    guard leaf.count <= 4096 else { fail(".DS_Store records outgrow a single leaf") }

    var tree = Data()
    for field: UInt32 in [2, 0, UInt32(sorted.count), 1, 0x1000] { tree.appendBigEndian(field) }

    var table = Data()
    let blocks: [UInt32] = [2048 | 11, 32 | 5, 4096 | 12]
    table.appendBigEndian(UInt32(blocks.count))
    table.appendBigEndian(UInt32(0))
    for slot in 0..<256 { table.appendBigEndian(slot < blocks.count ? blocks[slot] : 0) }
    table.appendBigEndian(UInt32(1))
    table.append(4)
    table.appendCode("DSDB")
    table.appendBigEndian(UInt32(1))
    for order in 0..<32 {
        let isFree = (6...10).contains(order) || (13...30).contains(order)
        table.appendBigEndian(UInt32(isFree ? 1 : 0))
        if isFree { table.appendBigEndian(UInt32(1) << order) }
    }

    var header = Data()
    header.appendCode("Bud1")
    for field: UInt32 in [2048, 2048, 2048, 0x100C, 0, 0, 0] { header.appendBigEndian(field) }

    var file = Data(count: 4 + 8192)
    file.replaceSubrange(0..<4, with: [0, 0, 0, 1])
    for (offset, block) in [(0, header), (32, tree), (2048, table), (4096, leaf)] {
        file.replaceSubrange((4 + offset)..<(4 + offset + block.count), with: block)
    }
    return file
}

func plist(_ object: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
}

func position(_ point: CGPoint) -> Data {
    var data = Data()
    data.appendBigEndian(UInt32(point.x))
    data.appendBigEndian(UInt32(point.y))
    data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0])
    return data
}

func windowRecords(background: URL) throws -> [Record] {
    let frame = CGRect(
        origin: Layout.windowOrigin,
        size: CGSize(
            width: Layout.canvas.width, height: Layout.canvas.height + Layout.titleBarHeight))
    let window: [String: Any] = [
        "WindowBounds":
            "{{\(Int(frame.minX)), \(Int(frame.minY))}, {\(Int(frame.width)), \(Int(frame.height))}}",
        "ShowToolbar": false, "ShowSidebar": false, "ContainerShowSidebar": false,
        "ShowStatusBar": false, "ShowPathbar": false, "ShowTabView": false
    ]
    let iconView: [String: Any] = [
        "viewOptionsVersion": 1, "arrangeBy": "none", "labelOnBottom": true,
        "iconSize": Layout.iconSize, "textSize": Layout.textSize, "gridSpacing": 100.0,
        "gridOffsetX": 0.0, "gridOffsetY": 0.0, "showItemInfo": false, "showIconPreview": true,
        "backgroundType": 2, "backgroundColorRed": 0.0, "backgroundColorGreen": 0.0,
        "backgroundColorBlue": 0.0
    ]
    return [
        Record(file: ".", code: "bwsp", value: .blob(try plist(window))),
        Record(file: ".", code: "icvp", value: .blob(try plist(iconView))),
        Record(
            file: ".", code: "pBBk",
            value: .blob(try background.bookmarkData(options: .withoutImplicitSecurityScope))),
        Record(file: ".", code: "vSrn", value: .long(1)),
        Record(file: "Applications", code: "Iloc", value: .blob(position(Layout.applications))),
        Record(file: appName, code: "Iloc", value: .blob(position(Layout.app)))
    ]
}

// MARK: - Main

do {
    let background = volume.appending(components: ".background", "background.tiff")
    try writeBackground(to: background)
    try storeData(try windowRecords(background: background)).write(
        to: volume.appending(component: ".DS_Store"))
} catch {
    fail("cannot lay out \(volume.path): \(error.localizedDescription)")
}
