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

    /// Trimmed from the Oxford Chinese record for `good`: the bilingual schema every Oxford pair shares.
    static let bilingual = """
        <d:entry xmlns:d="x" id="e_20131" d:title="good" class="entry"><span class="hwg">\
        <span d:dhw="1" role="text" class="hw">good<span class="gp tg_hw"> </span></span>\
        <span dialect="BrE" class="prx"><span class="gp tg_prx"> | </span><span class="gp tg_prx">BrE \
        </span><span class="ph">ɡʊd</span><span class="gp tg_prx">, </span></span>\
        <span dialect="AmE" class="prx"><span class="gp tg_prx">AmE </span><span class="ph">ɡʊd</span>\
        <span class="gp tg_prx"> | </span></span><span class="gp tg_hwg"> </span></span>\
        <span class="gramb hasSn"><span class="gp ty_label tg_gramb">A.</span>\
        <span class="gp tg_gramb"> </span><span class="ps">adjective</span><span class="frmg">\
        <span class="gp tg_frmg">(</span><span class="gr">comparative form </span>\
        <span class="frm">better</span><span class="gp tg_frmg">) </span></span>\
        <span class="semb hasSn"><span class="gp ty_label tg_semb">①</span><span class="gp tg_semb"> </span>\
        <span class="ind"><span class="gp tg_ind">(</span>enjoyable<span class="gp tg_ind">)</span></span>\
        <span class="trg"><span class="trans">好的 </span><span class="trans ty_pinyin">hǎo de </span>\
        <span class="co"><span class="gp tg_co">‹</span>book<span class="gp tg_co">›</span></span></span>\
        <span class="exg"><span class="ex">a good joke</span><span class="trg"><span class="trans">有趣的笑话 \
        </span></span></span><span class="xrg"> <span class="gp tg_xrg">→ </span>\
        <span class="xr">riddance</span> </span></span></span></d:entry>
        """

    /// Trimmed from the Oxford Spanish record for `casa`: a sense nested before any text of its own.
    static let nestedSenses = """
        <d:entry xmlns:d="x" class="entry"><span class="gramb"><span class="ps"> f  </span>\
        <span class="semb hasSn"><span class="gp ty_label tg_semb">1 </span>\
        <span class="semb hasSn"><span class="gp ty_label tg_semb">a </span><span class="trg">\
        <span class="ind"><span class="gp tg_ind">(</span>vivienda<span class="gp tg_ind">) </span></span>\
        <span class="trans">house </span></span></span><span class="semb hasSn">\
        <span class="gp ty_label tg_semb">b </span><span class="trg"><span class="trans">home</span>\
        </span></span></span></span></d:entry>
        """

    /// Trimmed from the Vietnamese record for `good`, whose examples carry a `▸` in an `sn`.
    static let bulletedExamples = """
        <d:entry xmlns:d="x" class="entry"><span class="gramb x_xd0"><span class="ps x_xdh">tính từ </span>\
        <span class="semb x_xd1 hasSn"><span class="sn x_xdh">1 </span><span class="trg x_xd2">\
        <span class="trans">tốt; hay </span></span><span class="exg x_xd2 hasSn"><span class="x_xdh">\
        <span class="sn">▸ </span><span class="ex">It’s good to talk. </span></span>\
        <span class="trg x_xd3"><span class="trans">Nên nói. </span></span></span></span></span></d:entry>
        """

    /// Trimmed from the Oxford American Writer's Thesaurus record for `good`.
    static let thesaurus = """
        <d:entry xmlns:d="x" class="entry"><span class="sg"><span class="se1"><span class="gp tg_se1">▶</span>\
        <span role="text" class="posg"><span class="pos"><span class="gp tg_pos">adjective</span></span></span>\
        <span class="se2"> <span class="gp ty_label tg_se2">  1 </span><span class="msThes t_core">\
        <span class="eg"><span class="ex">a good product</span><span class="gp tg_eg">: </span></span>\
        <span class="synList"><span class="syn t_core">fine<span class="gp tg_syn">, </span></span>\
        <span class="syn">superior</span></span></span></span></span></span></d:entry>
        """

    /// Trimmed from the Duden record for `Haus`, whose examples follow a definition with no colon.
    static let definitionThenExamples = """
        <d:entry xmlns:d="x" class="entry"><span class="se2"><span class="msDict">\
        <span role="text" class="df">Gebäude, das Menschen zum Wohnen dient </span>\
        <span role="text" class="eg"><span class="ex">ein großes Haus</span><span class="lbl"> | </span>\
        <span class="ex">das Haus seiner Eltern</span></span></span></span></d:entry>
        """

    /// The Apple Dictionary's record for `Siri`: the plain template, with no classes and no entry span.
    static let plainTemplate = """
        <html xmlns:d="x"><body><d:entry id="Siri"><h1>Siri</h1>\
        <p>An intelligent personal assistant.</p><p>See also <a href="x"><b>Apple TV</b></a>.</p>\
        </d:entry></body></html>
        """

    /// Trimmed from the Korean record for `사랑`, whose spans abut and lead with their separator.
    static let abutting = """
        <d:entry xmlns:d="x" class="entry"><span class="gramb"><span class="semb">\
        <span class="trg"><span class="trans">love</span></span><span class="trg"><span class="gp">; </span>\
        <span class="trans">affection</span></span><span class="exg"><span class="ex">사랑의 신</span>\
        <span class="trg"><span class="trans">the god of love</span></span></span></span></span></d:entry>
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

        expect(
            DictionaryMarkup.blocks(fromXHTML: bilingual),
            [
                .headword("good", homograph: nil, pronunciation: "BrE ɡʊd, AmE ɡʊd"),
                .partOfSpeech([
                    Run(text: "A. ", style: .plain), Run(text: "adjective", style: .label),
                    Run(text: " (", style: .plain), Run(text: "comparative form ", style: .label),
                    Run(text: "better", style: .strong), Run(text: ")", style: .plain)
                ]),
                .sense(
                    number: "①",
                    [
                        Run(text: "(enjoyable)", style: .label), Run(text: " 好的 ", style: .plain),
                        Run(text: "hǎo de ‹book›", style: .label)
                    ]),
                .example([
                    Run(text: "a good joke", style: .example), Run(text: " 有趣的笑话", style: .plain)
                ]),
                .paragraph([Run(text: "→ riddance", style: .plain)])
            ],
            "a bilingual entry splits into headword, part of speech, sense and one line per example")

        expect(
            DictionaryMarkup.blocks(fromXHTML: nestedSenses),
            [
                .partOfSpeech([Run(text: "f", style: .label)]),
                .sense(
                    number: "1 a",
                    [Run(text: "(vivienda) ", style: .label), Run(text: "house", style: .plain)]),
                .sense(number: "b", [Run(text: "home", style: .plain)])
            ],
            "a nested sense shares its parent's number until its parent has text")

        expect(
            DictionaryMarkup.blocks(fromXHTML: abutting),
            [
                .paragraph([Run(text: "love; affection", style: .plain)]),
                .example([
                    Run(text: "사랑의 신", style: .example), Run(text: " the god of love", style: .plain)
                ])
            ],
            "abutting spans get a word break, never one ahead of punctuation")

        expect(
            DictionaryMarkup.blocks(fromXHTML: bulletedExamples),
            [
                .partOfSpeech([Run(text: "tính từ", style: .label)]),
                .sense(number: "1", [Run(text: "tốt; hay", style: .plain)]),
                .example([
                    Run(text: "It’s good to talk. ", style: .example), Run(text: "Nên nói.", style: .plain)
                ])
            ],
            "an example's bullet never reads as a sense number")

        expect(
            DictionaryMarkup.blocks(fromXHTML: thesaurus),
            [
                .partOfSpeech([Run(text: "adjective", style: .label)]),
                .sense(
                    number: "1",
                    [
                        Run(text: "a good product: ", style: .example),
                        Run(text: "fine, superior", style: .plain)
                    ])
            ],
            "a thesaurus sense takes its label as its number")

        expect(
            DictionaryMarkup.blocks(fromXHTML: definitionThenExamples),
            [
                .sense(number: nil, [Run(text: "Gebäude, das Menschen zum Wohnen dient", style: .plain)]),
                .example([Run(text: "ein großes Haus | das Haus seiner Eltern", style: .example)])
            ],
            "examples after a definition with no colon start their own line")

        expect(
            DictionaryMarkup.blocks(fromXHTML: plainTemplate),
            [
                .headword("Siri", homograph: nil, pronunciation: nil),
                .paragraph([Run(text: "An intelligent personal assistant.", style: .plain)]),
                .paragraph([Run(text: "See also Apple TV.", style: .plain)])
            ],
            "the plain template reads its h1 as the headword and each p as a paragraph")

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
