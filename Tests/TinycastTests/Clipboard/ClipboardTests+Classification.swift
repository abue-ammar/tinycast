import Foundation
import Testing

@testable import Tinycast

extension ClipboardTests {
    @Test(arguments: [
        ("https://apple.com", ClipboardItem.TextForm.link), ("http://apple.com/path?q=1", .link),
        ("apple.com", .link), ("apple.com/store", .link), ("www.Apple.com", .link),
        ("vscode://file/tmp/x", .link), ("docs.google.com", .link), ("bit.ly/abc", .link),
        ("hi@apple.com", .email), ("mailto:hi@apple.com", .email), ("first.last@mail.example.co.uk", .email),
        ("report.pdf", .plain), ("index.html", .plain), ("App.swift", .plain), ("data.json", .plain),
        ("Safari.app", .plain), ("image.png", .plain), ("hello world", .plain),
        ("visit apple.com today", .plain), ("3.14", .plain), ("", .plain), ("   ", .plain),
        ("no-dot-at-all", .plain), ("two@at@signs.com", .plain), ("@apple.com", .plain),
        ("hi@localhost", .plain), ("line one\nline two", .plain), ("#FF5733", .color),
        ("#0f0", .color), ("rgb(255, 87, 51)", .color), ("hsl(11, 100%, 60%)", .color),
        ("https://apple.com/" + String(repeating: "a", count: 4096), .plain)
    ])
    func textFormDistinguishesLinksAddressesColorsAndProse(_ text: String, _ expected: ClipboardItem.TextForm)
        throws
    {
        let form = try #require(ClipboardItem(text: text, sourceBundleID: nil).textForm)
        #expect(form == expected)
    }

    @Test func anImageHasNoTextForm() {
        #expect(ClipboardItem(imagePath: "/tmp/x.png", sourceBundleID: nil).textForm == nil)
    }

    @Test func aStoredFilePathIsNeitherProseNorAColorNorALink() {
        let file = ClipboardItem(filePath: "/Users/me/apple.com/#FF5733.txt", sourceBundleID: nil)
        #expect(file.textForm == nil)
        #expect(file.colorValue == nil)
        #expect(!ClipboardFilter.link.matches(file))
        #expect(!ClipboardFilter.text.matches(file))
        #expect(ClipboardFilter.file.matches(file))
    }

    @Test(arguments: [
        ("/a/b.mov", false, ClipboardFileKind.movie), ("/a/b.png", false, .image),
        ("/a/b.pdf", false, .pdf), ("/a/b.m4a", false, .audio),
        ("/a/README", false, .other), ("/a/b", true, .folder)
    ])
    func fileKindUsesTheExtensionAndDirectoryFlag(_ path: String, _ isDirectory: Bool, _ kind: ClipboardFileKind) {
        #expect(ClipboardFileKind.of(path: path, isDirectory: isDirectory) == kind)
    }

    @Test(arguments: [
        (ClipboardDefaultAction.paste, [ClipboardDefaultAction?.some(.paste), .copy, .pastePlainText]),
        (.copy, [.copy, .paste, .pastePlainText]),
        (.pastePlainText, [.pastePlainText, .copy, .paste])
    ], [ClipboardItem(text: "hello", sourceBundleID: nil),
        ClipboardItem(filePath: "/Users/me/report.pdf", sourceBundleID: nil)])
    func textAndFilesAssignReturnChordsAroundTheDefault(
        _ row: (ClipboardDefaultAction, [ClipboardDefaultAction?]), _ item: ClipboardItem
    ) {
        let (action, expected) = row
        #expect(ClipboardChord.allCases.map { action.action(for: $0, on: item) } == expected)
    }

    @Test(arguments: [
        (ClipboardDefaultAction.paste, ClipboardDefaultAction.paste),
        (.copy, .copy), (.pastePlainText, .paste)
    ])
    func imageChordsFallBackFromPlainText(_ action: ClipboardDefaultAction, _ expected: ClipboardDefaultAction) {
        let image = ClipboardItem(imagePath: "/tmp/shot.png", sourceBundleID: nil)
        let chords = ClipboardChord.allCases.map { action.action(for: $0, on: image) }
        #expect(chords.first == .some(expected))
        #expect(chords.last == .some(nil))
    }

    @Test(arguments: [
        (ClipboardItem(text: "hi", sourceBundleID: nil), "hi" as String?),
        (ClipboardItem(filePath: "/a/b.pdf", sourceBundleID: nil), "/a/b.pdf"),
        (ClipboardItem(imagePath: "/a/b.png", sourceBundleID: nil), nil)
    ])
    func plainTextYieldsTextOrAPathButNoImage(_ item: ClipboardItem, _ expected: String?) {
        #expect(item.plainText == expected)
    }

    @Test(arguments: [
        (ClipboardItem(imagePath: "/tmp/shot.png", sourceBundleID: nil), true),
        (ClipboardItem(id: UUID(), kind: .image, text: nil, imagePath: nil, createdAt: .now,
            sourceBundleID: nil), false),
        (ClipboardItem(text: "hello", sourceBundleID: nil), false),
        (ClipboardItem(filePath: "/Users/me/shot.png", sourceBundleID: nil), true),
        (ClipboardItem(filePath: "/Users/me/notes.txt", sourceBundleID: nil), false),
        (ClipboardItem(filePath: "/Users/me/report.pdf", sourceBundleID: nil), false)
    ])
    func copyTextIsOfferedForImageBlobsAndImageFiles(_ item: ClipboardItem, _ expected: Bool) {
        #expect(item.offersTextExtraction == expected)
    }
}
