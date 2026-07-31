import Foundation

/// Latin search aliases for Han-script names, so a Chinese-named app is reachable from an ASCII keyboard: 微信 answers to "weixin" and to "wx".
enum Pinyin {
    /// Full reading first, per-character initials second; nothing at all for a name with no Han character, which is the path that has to stay cheap.
    static func aliases(for name: String) -> [String] {
        guard name.unicodeScalars.contains(where: isHan) else { return [] }

        // App metadata carries bidi and zero-width markers, which FuzzyMatch strips for the same reason. Left in, a BOM ends tokenization early and truncates the reading, and any marker inside a token would inflate the character count the syllable cut is measured against.
        let text = String(
            String.UnicodeScalarView(
                name.unicodeScalars.filter { $0.properties.generalCategory != .format }))

        var full = ""
        var initials = ""
        for token in tokens(of: text) {
            // Latin and digits carry through as typed, so "QQ音乐" still answers to "qqyinyue".
            guard token.raw.unicodeScalars.allSatisfy(isHan) else {
                let carried = asciiFolded(token.raw)
                full += carried
                initials += carried
                continue
            }
            guard let transcription = token.transcription else { continue }
            let reading = asciiFolded(transcription).filter(\.isLetter)
            guard !reading.isEmpty else { continue }

            full += reading
            // A reading that won't cut still searches in full; it just contributes no initial-letter shortcut.
            guard let parts = syllables(of: reading, count: token.raw.count) else {
                initials += reading
                continue
            }
            for part in parts where !part.isEmpty { initials.append(part[part.startIndex]) }
        }

        guard !full.isEmpty else { return [] }
        // A one-letter alias would match everything it leads, so a single-character name searches by its full reading alone.
        guard initials.count > 1, initials != full else { return [full] }
        return [full, initials]
    }

    private struct Token {
        let raw: String
        let transcription: String?
    }

    /// Readings come from `CFStringTokenizer` rather than `kCFStringTransformMandarinLatin` because it segments words before reading them, which is what resolves a polyphone: 音乐 is "yinyue", not "yinle", and 地图 is "ditu", not "detu".
    private static func tokens(of name: String) -> [Token] {
        let text = name as NSString
        guard
            let tokenizer = CFStringTokenizerCreate(
                kCFAllocatorDefault, name as CFString, CFRangeMake(0, text.length),
                kCFStringTokenizerUnitWord, locale as CFLocale)
        else { return [] }

        var result: [Token] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            result.append(
                Token(
                    raw: text.substring(
                        with: NSRange(location: range.location, length: range.length)),
                    transcription: CFStringTokenizerCopyCurrentTokenAttribute(
                        tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String))
        }
        return result
    }

    /// An alias only earns its keep if it can be typed, so tones and accents fold ("yīnyuè" → "yinyue", "café" → "cafe") and anything still not ASCII — emoji, kana, hangul — is dropped rather than embedded in a string no ASCII keyboard can enter.
    private static func asciiFolded(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: nil).lowercased().filter(\.isASCII)
    }

    /// Cuts a toneless reading into exactly `count` syllables — one per character — or nil when no such cut exists. Pinyin is ambiguous on its own ("xian" is 西安 or 险), so it is the known character count that makes the boundaries decidable.
    static func syllables(of reading: String, count: Int) -> [String]? {
        let letters = Array(reading)
        guard count > 0, letters.count >= count else { return nil }

        // Memoizing the dead ends is what keeps the backtracking linear rather than exponential.
        var exhausted = Set<Int>()
        var result: [String] = []

        func cut(from start: Int, into remaining: Int) -> Bool {
            if remaining == 0 { return start == letters.count }
            let state = start * (count + 1) + remaining
            guard !exhausted.contains(state) else { return false }
            // Longest first: "pingan" is 平安, not 拼干.
            for length in stride(
                from: min(longestSyllable, letters.count - start), through: 1, by: -1)
            {
                let candidate = String(letters[start..<(start + length)])
                guard syllableSet.contains(candidate) else { continue }
                result.append(candidate)
                if cut(from: start + length, into: remaining - 1) { return true }
                result.removeLast()
            }
            exhausted.insert(state)
            return false
        }
        return cut(from: 0, into: count) ? result : nil
    }

    /// `isUnifiedIdeograph` covers the unified blocks including the newer extensions; 〇 and the compatibility ideographs sit outside it but the tokenizer still reads them, and 〇 in particular turns 一〇〇 into a wrong reading if it is treated as foreign.
    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isUnifiedIdeograph
            || scalar.value == 0x3007
            || (0xF900...0xFAFF).contains(scalar.value)
            || (0x2_F800...0x2_FA1F).contains(scalar.value)
    }

    private static let locale = Locale(identifier: "zh_Hans")

    /// Every Mandarin syllable macOS itself transliterates to, read off `kCFStringTransformMandarinLatin` across the CJK ideograph blocks, so a reading it produces can always be cut. The interjection-only readings "m", "n", "ng" and "hm" are left out: they never occur inside a word, and admitting them would cut "xian" as "xia" + "n".
    private static let syllableSet: Set<String> = Set(
        """
        a ai an ang ao ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu ca cai can
        cang cao ce cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai
        chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo da dai dan dang dao de den deng
        di dia dian diao die ding diu dong dou du duan dui dun duo e ei en eng er fa fan fang fei
        fen feng fiao fo fou fu ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang
        gui gun guo ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun
        huo ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun ka kai kan kang kao ke kei
        ken keng kong kou ku kua kuai kuan kuang kui kun kuo la lai lan lang lao le lei leng li lia
        lian liang liao lie lin ling liu lo long lou lu luan lue lun luo ma mai man mang mao me
        mei men meng mi mian miao mie min ming miu mo mou mu na nai nan nang nao ne nei nen neng
        ni nian niang niao nie nin ning niu nong nou nu nuan nue nun nuo o ou pa pai pan pang pao
        pei pen peng pi pian piao pie pin ping po pou pu qi qia qian qiang qiao qie qin qing qiong
        qiu qu quan que qun ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo sa sai san
        sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai
        shuan shuang shui shun shuo si song sou su suan sui sun suo ta tai tan tang tao te teng ti
        tian tiao tie ting tong tou tu tuan tui tun tuo wa wai wan wang wei wen weng wo wu xi xia
        xian xiang xiao xie xin xing xiong xiu xu xuan xue xun ya yan yang yao ye yi yin ying yo
        yong you yu yuan yue yun za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe
        zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui
        zun zuo
        """
        .split(whereSeparator: \.isWhitespace).map(String.init))

    private static let longestSyllable = syllableSet.map(\.count).max() ?? 0
}
