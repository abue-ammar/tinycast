// How a Dictionary Services record — XHTML, or the public API's plain text — becomes page blocks.

import Foundation

@main
@MainActor
struct DictionaryEntryTests {
    typealias Block = DictionaryEntry.Block
    typealias Run = DictionaryEntry.Run

    static var failures = 0
    static var passes = 0

    static func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)\n  got  \(actual)\n  want \(expected)")
        }
    }

    /// Trimmed from the New Oxford American record for `mango`, classes and whitespace intact.
    static let mango = """
        <html xmlns:d="http://www.apple.com/DTDs/DictionaryService-1.0.rng"><head/><body>\
        <d:entry id="m" d:title="mango" class="entry"><span class="hg x_xh0">\
        <span role="text" class="hw">man<span class="hsb"/>go </span>\
        <span d:syl="1" class="syl_txt">man·go<d:syl/></span><span dialect="AmE" class="prx"> | \
        <span d:prn="US" class="ph t_respell">ˈmaNGɡō<d:prn/></span> | </span></span>\
        <span class="sg"><span class="se1 x_xd0"><span role="text" class="posg x_xdh">\
        <span d:pos="1" class="pos"><span class="gp tg_pos">noun </span><d:pos/></span>\
        <span class="infg"><span class="gp tg_infg">(</span><span class="sy">plural </span>\
        <span class="inf">mangoes</span><span class="gp tg_infg">) </span></span></span>\
        <span class="se2 x_xd1 hasSn"><span class="gp x_xdh sn ty_label tg_se2">  1 </span>\
        <span class="msDict x_xd1sub t_first"><span d:def="1" role="text" class="df">a tropical fruit\
        <span class="gp tg_df">: </span><d:def/></span><span role="text" class="eg">\
        <span class="ex"> a ripe mango</span><span class="gp tg_eg">. </span></span></span>\
        <span class="msDict x_xd1sub hasSn t_subsense">\
        <span role="text" class="gp sn tg_msDict">  • </span>\
        <span role="text" class="lg"><span class="reg">informal </span></span>\
        <span role="text" class="df">a mango tree</span></span></span>\
        <span class="se2 x_xd1 hasSn"><span class="gp x_xdh sn ty_label tg_se2">  2 </span>\
        <span class="msDict x_xd1sub t_first"><span d:def="1" role="text" class="df">a hummingbird. \
        <d:def/></span><span role="text" class="note">Genus <span class="tx">Anthracothorax</span>\
        </span></span></span></span></span>\
        <span role="text" class="etym x_xo0"><span class="gp x_xoLblBlk ty_label tg_etym">ORIGIN </span>\
        <span class="x_xo1"><span class="dg"><span class="date">late 16th century</span></span>: \
        from <span class="la">Portuguese </span><span class="ff">manga</span>.</span></span>\
        </d:entry></body></html>
        """

    static func main() {
        let blocks = DictionaryMarkup.blocks(fromXHTML: mango)
        let expected: [Block] = [
            .headword("man·go", homograph: nil, pronunciation: "ˈmaNGɡō"),
            .partOfSpeech([
                Run(text: "noun ", style: .label), Run(text: "(", style: .plain),
                Run(text: "plural ", style: .label), Run(text: "mangoes", style: .strong),
                Run(text: ")", style: .plain)
            ]),
            .sense(
                number: "1",
                [
                    Run(text: "a tropical fruit: ", style: .plain),
                    Run(text: "a ripe mango.", style: .example)
                ]),
            .subsense([
                Run(text: "informal ", style: .label), Run(text: "a mango tree", style: .plain)
            ]),
            .sense(number: "2", [Run(text: "a hummingbird.", style: .plain)]),
            .note([Run(text: "Genus ", style: .plain), Run(text: "Anthracothorax", style: .italic)]),
            .section("ORIGIN"),
            .paragraph([
                Run(text: "late 16th century: from Portuguese ", style: .plain),
                Run(text: "manga", style: .italic), Run(text: ".", style: .plain)
            ])
        ]
        expect(blocks.count, expected.count, "every structural span becomes one block")
        for (index, pair) in zip(blocks, expected).enumerated() {
            expect(pair.0, pair.1, "block \(index)")
        }
        expect(DictionaryMarkup.blocks(fromXHTML: "<html><body"), [], "broken markup reads as nothing")

        let homograph = DictionaryMarkup.blocks(
            fromXHTML: """
                <d:entry xmlns:d="x" class="entry"><span class="hg"><span class="hw">light\
                <span class="gp ty_hom tg_hw"> 1 </span></span><span class="pr"> | \
                <span class="ph">līt</span>, <span class="ph">lite</span> | </span></span></d:entry>
                """)
        expect(
            homograph, [.headword("light", homograph: "1", pronunciation: "līt, lite")],
            "a homograph number and every pronunciation stay on the headword")

        let plain = DictionaryEntry(
            term: "hello",
            plainText: "hello hel·lo | həˈlō | used as a greeting. • used to attract attention.")
        expect(
            plain.blocks,
            [
                .headword("hello", homograph: nil, pronunciation: "həˈlō"),
                .paragraph([Run(text: "used as a greeting.", style: .plain)]),
                .paragraph([Run(text: "used to attract attention.", style: .plain)])
            ],
            "plain text splits into pronunciation and one paragraph per bullet")
        expect(
            DictionaryEntry(term: "x", plainText: "a letter").blocks,
            [
                .headword("x", homograph: nil, pronunciation: nil),
                .paragraph([Run(text: "a letter", style: .plain)])
            ],
            "plain text with no pipes is all body")

        expect(
            DictionaryEntry(term: "mango", blocks: expected).text,
            """
            man·go | ˈmaNGɡō |
            noun (plural mangoes)
            1 a tropical fruit: a ripe mango.
            • informal a mango tree
            2 a hummingbird.
            Genus Anthracothorax

            ORIGIN
            late 16th century: from Portuguese manga.
            """,
            "the copy keeps one line per block")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
