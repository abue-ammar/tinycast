// Standalone test for the launcher matcher. FuzzyMatch below is a copy of the one in Tinycast/Core/AppIndex.swift — keep the two in sync; Pinyin is the real source, compiled in: swiftc -swift-version 6 Tinycast/Core/Pinyin.swift Tools/fuzz-test.swift -o /tmp/fuzz-test && /tmp/fuzz-test

import Foundation

enum FuzzyMatch {
    static let romanizedPenalty = 5_000

    static func score(query: String, candidate: String) -> Int? {
        let q = normalized(query)
        let c = normalized(candidate)
        guard !q.isEmpty else { return 0 }

        if c == q { return 100_000 }
        if c.hasPrefix(q) { return 90_000 - c.count }

        if let range = c.range(of: q) {
            let atWordStart = isWordStart(c, range.lowerBound)
            return (atWordStart ? 80_000 : 70_000) - c.count
        }

        return subsequenceScore(Array(q), Array(c))
    }

    private static func normalized(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter {
            $0.properties.generalCategory != .format
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    private static func isWordStart(_ s: String, _ index: String.Index) -> Bool {
        if index == s.startIndex { return true }
        let before = s[s.index(before: index)]
        return !before.isLetter && !before.isNumber
    }

    private static func subsequenceScore(_ q: [Character], _ c: [Character]) -> Int? {
        var qi = 0
        var score = 0
        var run = 0
        var prev = -2
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            var bonus = 1
            if ci == prev + 1 {
                run += 1
                bonus += run * 3
            } else {
                run = 0
            }
            if ci == 0 {
                bonus += 12
            } else {
                let b = c[ci - 1]
                if !b.isLetter && !b.isNumber { bonus += 8 }
            }
            score += bonus
            prev = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        return score
    }
}

@main
@MainActor
struct FuzzTests {
    static var failures = 0

    static let apps = [
        "Google Chrome", "Chess", "Time Machine", "Safari", "Bluetooth File Exchange",
        "Screenshot", "Screen Sharing", "Visual Studio Code", "Photos", "App Store",
        "System Settings", "Calendar", "Terminal", "WhatsApp", "Wick",
        "微信", "网易云音乐", "高德地图", "钉钉", "QQ音乐", "迅雷",
        // Literal names that collide with a reading, to pin the tier order.
        "Xunlei", "WX Tool",
    ]

    /// Mirrors AppIndex.rank: the best score across the entry's name and every alias it carries.
    static func rank(_ query: String, boosts: [String: Int] = [:]) -> [String] {
        apps.compactMap { name -> (String, Int)? in
            var best = FuzzyMatch.score(query: query, candidate: name)
            // Readings land half a tier below the literal ladder, exactly as AppIndex.rank scores them.
            for reading in Pinyin.aliases(for: name) {
                guard let score = FuzzyMatch.score(query: query, candidate: reading) else { continue }
                let demoted = score - FuzzyMatch.romanizedPenalty
                best = max(best ?? demoted, demoted)
            }
            guard let score = best else { return nil }
            return (name, score + boosts[name, default: 0])
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.count < $1.0.count }
        .map(\.0)
    }

    static func check(_ desc: String, _ cond: Bool, _ detail: String = "") {
        if cond {
            print("PASS  \(desc)")
        } else {
            print("FAIL  \(desc)  \(detail)")
            failures += 1
        }
    }

    static func main() {
        let chrome = rank("chrome")
        check("'chrome' top is Google Chrome", chrome.first == "Google Chrome", "got \(chrome)")
        check("'chrome' does not include Chess", !chrome.contains("Chess"), "got \(chrome)")

        let ch = rank("ch")
        check("'ch' includes Google Chrome", ch.contains("Google Chrome"), "got \(ch)")
        check("'ch' includes Chess", ch.contains("Chess"))
        check(
            "'ch' ranks Chess (prefix) above Chrome",
            ch.firstIndex(of: "Chess")! < ch.firstIndex(of: "Google Chrome")!, "got \(ch)")

        check("'saf' top is Safari", rank("saf").first == "Safari", "got \(rank("saf"))")
        check("'tm' includes Time Machine", rank("tm").contains("Time Machine"), "got \(rank("tm"))")
        check(
            "'code' includes Visual Studio Code", rank("code").contains("Visual Studio Code"),
            "got \(rank("code"))")
        check("'terminal' exact top", rank("terminal").first == "Terminal")
        check("'xyz' matches nothing", rank("xyz").isEmpty, "got \(rank("xyz"))")

        let defaultW = rank("w")
        check(
            "shorter Wick wins the default prefix tie",
            defaultW.firstIndex(of: "Wick")! < defaultW.firstIndex(of: "WhatsApp")!,
            "got \(defaultW)")
        let learnedW = rank("w", boosts: ["WhatsApp": 2_100])
        check(
            "learned boost promotes WhatsApp within the prefix tier",
            learnedW.firstIndex(of: "WhatsApp")! < learnedW.firstIndex(of: "Wick")!,
            "got \(learnedW)")
        let markedWhatsApp = "\u{200E}WhatsApp"
        check(
            "invisible format mark does not demote WhatsApp's prefix match",
            FuzzyMatch.score(query: "w", candidate: markedWhatsApp)
                == FuzzyMatch.score(query: "w", candidate: "WhatsApp"))
        check(
            "learned marked WhatsApp can outrank Wick",
            FuzzyMatch.score(query: "w", candidate: markedWhatsApp)! + 2_100
                > FuzzyMatch.score(query: "w", candidate: "Wick")!)

        // Pinyin aliases
        check(
            "full reading and initials, in that order",
            Pinyin.aliases(for: "微信") == ["weixin", "wx"],
            "got \(Pinyin.aliases(for: "微信"))")
        check(
            "a name in no Han script gets no alias",
            Pinyin.aliases(for: "Visual Studio Code").isEmpty
                && Pinyin.aliases(for: "ひらがな").isEmpty && Pinyin.aliases(for: "한글").isEmpty,
            "got \(Pinyin.aliases(for: "ひらがな"))")
        check(
            "Latin inside a Han name carries through as typed",
            Pinyin.aliases(for: "QQ音乐") == ["qqyinyue", "qqyy"],
            "got \(Pinyin.aliases(for: "QQ音乐"))")
        check(
            "a one-letter initial is dropped rather than matching everything it leads",
            Pinyin.aliases(for: "云") == ["yun"], "got \(Pinyin.aliases(for: "云"))")
        check(
            "digits carry through", Pinyin.aliases(for: "3D打印助手") == ["3ddayinzhushou", "3ddyzs"],
            "got \(Pinyin.aliases(for: "3D打印助手"))")

        // An alias only earns its keep if it can be typed, so nothing that isn't ASCII may reach one.
        check(
            "emoji, kana and hangul are dropped, not embedded",
            Pinyin.aliases(for: "微信\u{1F600}音乐") == ["weixinyinyue", "wxyy"]
                && Pinyin.aliases(for: "ひらがな漢字") == ["hanzi", "hz"]
                && Pinyin.aliases(for: "한글漢字") == ["hanzi", "hz"],
            "got \(Pinyin.aliases(for: "微信\u{1F600}音乐")) / \(Pinyin.aliases(for: "ひらがな漢字"))")
        check(
            "an accent folds rather than blocking the alias",
            Pinyin.aliases(for: "café中文") == ["cafezhongwen", "cafezw"],
            "got \(Pinyin.aliases(for: "café中文"))")
        check(
            "every alias is ASCII, whatever the name mixes in",
            ["微信\u{1F600}音乐", "ひらがな漢字", "한글漢字", "café中文", "微信 · 测试", "QQ音乐", "3D打印助手"]
                .flatMap(Pinyin.aliases(for:)).allSatisfy { $0.allSatisfy(\.isASCII) })
        check(
            "a name with no readable character gets no alias",
            Pinyin.aliases(for: "\u{20000}\u{20001}").isEmpty && Pinyin.aliases(for: "!!!").isEmpty
                && Pinyin.aliases(for: "   ").isEmpty)
        // Left in, a BOM ends tokenization early and silently truncates the reading.
        check(
            "an invisible format scalar anywhere leaves the reading alone",
            Pinyin.aliases(for: "\u{200E}微信") == ["weixin", "wx"]
                && Pinyin.aliases(for: "微\u{200E}信") == ["weixin", "wx"]
                && Pinyin.aliases(for: "汽水\u{FEFF}音乐") == ["qishuiyinyue", "qsyy"]
                && Pinyin.aliases(for: "网易\u{200B}云音乐") == ["wangyiyunyinyue", "wyyyy"]
                && Pinyin.aliases(for: "剪映\u{200D}专业版") == ["jianyingzhuanyeban", "jyzyb"],
            "got \(Pinyin.aliases(for: "汽水\u{FEFF}音乐"))")
        check(
            "the ideographic zero is read, not treated as foreign",
            Pinyin.aliases(for: "一〇〇") == ["yilingling", "yll"]
                && Pinyin.aliases(for: "二〇二五") == ["erlingerwu", "elew"],
            "got \(Pinyin.aliases(for: "二〇二五"))")

        // Polyphones — these are the readings a character-at-a-time transliteration gets wrong.
        for (name, reading) in [
            ("音乐", "yinyue"), ("地图", "ditu"), ("银行", "yinhang"), ("长城", "changcheng"),
            ("重庆", "chongqing"),
        ] {
            check(
                "\(name) reads as \(reading)", Pinyin.aliases(for: name).first == reading,
                "got \(Pinyin.aliases(for: name))")
        }

        // The character count is what makes an ambiguous syllable boundary decidable.
        check("xian over two characters is xi + an", Pinyin.syllables(of: "xian", count: 2) == ["xi", "an"])
        check("xian over one character stays whole", Pinyin.syllables(of: "xian", count: 1) == ["xian"])
        check("pingan cuts longest-first, as 平安", Pinyin.syllables(of: "pingan", count: 2) == ["ping", "an"])
        check("alibaba cuts into four", Pinyin.syllables(of: "alibaba", count: 4) == ["a", "li", "ba", "ba"])
        check("an unreadable run does not cut", Pinyin.syllables(of: "zzz", count: 1) == nil)

        // Ranking through the aliases
        check("'weixin' top is 微信", rank("weixin").first == "微信", "got \(rank("weixin"))")
        check("'wx' top is 微信", rank("wx").first == "微信", "got \(rank("wx"))")
        check("'dd' top is 钉钉", rank("dd").first == "钉钉", "got \(rank("dd"))")
        check(
            "'wyyyy' top is 网易云音乐", rank("wyyyy").first == "网易云音乐", "got \(rank("wyyyy"))")
        check(
            "'ditu' top is 高德地图", rank("ditu").first == "高德地图", "got \(rank("ditu"))")
        check(
            "'yinyue' finds both 音乐 apps", rank("yinyue").contains("网易云音乐")
                && rank("yinyue").contains("QQ音乐"), "got \(rank("yinyue"))")
        check(
            "a Han name still matches as typed", rank("微信").first == "微信",
            "got \(rank("微信"))")
        check(
            "aliases do not disturb a Latin name's own ranking",
            rank("saf").first == "Safari" && rank("chrome").first == "Google Chrome")

        // Tier order between a literal name and a reading that spells the same thing.
        check(
            "a literal name beats a reading that spells it",
            rank("xunlei").first == "Xunlei" && rank("xunlei").contains("迅雷"),
            "got \(rank("xunlei"))")
        check(
            "a reading still beats a literal prefix of a longer name",
            rank("wx").first == "微信" && rank("wx").contains("WX Tool"),
            "got \(rank("wx"))")
        check(
            "a demoted exact reading sits between literal exact and literal prefix",
            FuzzyMatch.score(query: "safari", candidate: "safari")! - FuzzyMatch.romanizedPenalty
                < FuzzyMatch.score(query: "safari", candidate: "Safari")!
                && FuzzyMatch.score(query: "safari", candidate: "safari")!
                    - FuzzyMatch.romanizedPenalty
                    > FuzzyMatch.score(query: "safari", candidate: "Safari Technology Preview")!)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
