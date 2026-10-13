import Foundation

enum SyntaxKind: Sendable {
    case keyword, string, number, comment, type, function, constant, attribute, property
    case inserted, deleted
}

struct SyntaxToken: Equatable, Sendable {
    let range: NSRange
    let kind: SyntaxKind
}

enum SyntaxLanguage: Sendable {
    case code(SyntaxGrammar)
    case markup
    case stylesheet
    case diff

    init?(named info: String?) {
        let word = info?.lowercased().split(whereSeparator: { " \t{,:".contains($0) }).first
        guard let word else { return nil }
        switch word {
        case "swift": self = .code(.swift)
        case "javascript", "js", "jsx", "mjs", "cjs", "node": self = .code(.javascript)
        case "typescript", "ts", "tsx", "mts": self = .code(.typescript)
        case "python", "py", "python3", "py3": self = .code(.python)
        case "java": self = .code(.java)
        case "kotlin", "kt", "kts": self = .code(.kotlin)
        case "c", "h": self = .code(.c)
        case "cpp", "c++", "cc", "cxx", "hpp", "hh", "hxx": self = .code(.cpp)
        case "objc", "objective-c", "objectivec", "objective-cpp", "m", "mm": self = .code(.objectiveC)
        case "csharp", "cs", "c#", "dotnet": self = .code(.csharp)
        case "go", "golang": self = .code(.go)
        case "rust", "rs": self = .code(.rust)
        case "ruby", "rb": self = .code(.ruby)
        case "php": self = .code(.php)
        case "lua": self = .code(.lua)
        case "sql", "mysql", "postgres", "postgresql", "sqlite", "pgsql", "plsql", "tsql", "psql":
            self = .code(.sql)
        case "bash", "sh", "shell", "zsh", "ksh", "console", "shell-session", "shellscript", "terminal":
            self = .code(.shell)
        case "dockerfile", "docker": self = .code(.dockerfile)
        case "json", "jsonc", "json5", "jsonl": self = .code(.json)
        case "yaml", "yml": self = .code(.yaml)
        case "toml": self = .code(.toml)
        case "ini", "conf", "cfg", "properties": self = .code(.ini)
        case "html", "htm", "xhtml", "xml", "svg", "plist", "xsl", "xaml": self = .markup
        case "css", "scss", "less": self = .stylesheet
        case "diff", "patch", "udiff": self = .diff
        default: return nil
        }
    }
}

struct SyntaxGrammar: Sendable {
    struct StringRule: Sendable {
        let delimiter: [UInt16]
        var multiline = false
        var escapes = true
        var doubling = false

        init(_ delimiter: String, multiline: Bool = false, escapes: Bool = true, doubling: Bool = false) {
            self.delimiter = Array(delimiter.utf16)
            self.multiline = multiline
            self.escapes = escapes
            self.doubling = doubling
        }
    }

    struct BlockComment: Sendable {
        let open: [UInt16]
        let close: [UInt16]

        init(_ open: String, _ close: String) {
            self.open = Array(open.utf16)
            self.close = Array(close.utf16)
        }
    }

    enum LineKeys: Sendable {
        case colon
        case equals
    }

    struct Options: OptionSet, Sendable {
        let rawValue: Int
        static let caseInsensitive = Options(rawValue: 1 << 0)
        static let capitalizedTypes = Options(rawValue: 1 << 1)
        static let upperConstants = Options(rawValue: 1 << 2)
        static let decorators = Options(rawValue: 1 << 3)
        static let directives = Options(rawValue: 1 << 4)
        static let lifetimes = Options(rawValue: 1 << 5)
        static let macros = Options(rawValue: 1 << 6)
        static let dollarVariables = Options(rawValue: 1 << 7)
        static let keyedStrings = Options(rawValue: 1 << 8)
        static let stringPrefixes = Options(rawValue: 1 << 9)
        static let shell = Options(rawValue: 1 << 10)
        /// A word before a parenthesis is not a call; this is data, not code.
        static let plainCalls = Options(rawValue: 1 << 11)
    }

    var keywords: Set<String> = []
    var constants: Set<String> = []
    var types: Set<String> = []
    var softKeywords: Set<String> = []
    var functionIntroducers: Set<String> = []
    var typeIntroducers: Set<String> = []
    var lineComments: [[UInt16]] = []
    var blockComment: BlockComment?
    var strings: [StringRule] = []
    var lineKeys: LineKeys?
    var options: Options = []
}

private func words(_ list: String) -> Set<String> {
    Set(list.split(whereSeparator: \.isWhitespace).map(String.init))
}

private func comments(_ openers: String...) -> [[UInt16]] {
    openers.map { Array($0.utf16) }
}

private let cBlock = SyntaxGrammar.BlockComment("/*", "*/")
private let cStrings = [SyntaxGrammar.StringRule("\""), .init("'")]
private let functionWords = words("func fn def function fun sub")
private let typeWords = words(
    "class struct enum protocol extension interface trait impl actor record typealias")

extension SyntaxGrammar {
    static let swift = SyntaxGrammar(
        keywords: words(
            """
            actor any as associatedtype async await borrowing break case catch class consuming continue \
            convenience default defer deinit didSet do dynamic else enum extension fallthrough fileprivate \
            final for func guard if import in indirect init inout internal is isolated lazy let macro \
            mutating nonisolated nonmutating open operator optional override package precedencegroup \
            private protocol public repeat required rethrows return self Self sending some static struct \
            subscript super switch throw throws try typealias unowned var weak where while willSet
            """),
        constants: words("true false nil"),
        functionIntroducers: functionWords, typeIntroducers: typeWords,
        lineComments: comments("//"), blockComment: cBlock,
        strings: [.init("\"\"\"", multiline: true), .init("\"")],
        options: [.capitalizedTypes, .decorators, .directives])

    private static let javascriptKeywords = words(
        """
        as async await break case catch class const continue debugger default delete do else export \
        extends finally for from function if import in instanceof let new of return static super switch \
        this throw try typeof var void while with yield
        """)

    static let javascript = SyntaxGrammar(
        keywords: javascriptKeywords,
        constants: words("true false null undefined NaN Infinity"),
        functionIntroducers: functionWords, typeIntroducers: typeWords,
        lineComments: comments("//"), blockComment: cBlock,
        strings: [.init("\""), .init("'"), .init("`", multiline: true)],
        options: [.capitalizedTypes, .decorators])

    static let typescript = SyntaxGrammar(
        keywords: javascriptKeywords.union(
            words(
                """
                abstract asserts declare enum implements infer interface is keyof module namespace \
                override private protected public readonly satisfies unique
                """)),
        constants: words("true false null undefined NaN Infinity"),
        types: words("string number boolean any unknown never object symbol bigint"),
        softKeywords: words("type"),
        functionIntroducers: functionWords, typeIntroducers: typeWords.union(["type"]),
        lineComments: comments("//"), blockComment: cBlock,
        strings: [.init("\""), .init("'"), .init("`", multiline: true)],
        options: [.capitalizedTypes, .decorators])

    static let python = SyntaxGrammar(
        keywords: words(
            """
            and as assert async await break class cls continue def del elif else except finally for from \
            global if import in is lambda nonlocal not or pass raise return self try while with yield
            """),
        constants: words("True False None"),
        types: words("int float str bool list dict set tuple bytes bytearray object complex frozenset"),
        softKeywords: words("match case"),
        functionIntroducers: functionWords, typeIntroducers: typeWords,
        lineComments: comments("#"),
        strings: [
            .init("\"\"\"", multiline: true), .init("'''", multiline: true), .init("\""), .init("'")
        ],
        options: [.capitalizedTypes, .upperConstants, .decorators, .stringPrefixes])

    static let java = SyntaxGrammar(
        keywords: words(
            """
            abstract assert break case catch class const continue default do else enum extends final \
            finally for goto if implements import instanceof interface native new package permits private \
            protected public record return sealed static strictfp super switch synchronized this throw \
            throws transient try var volatile while yield
            """),
        constants: words("true false null"),
        types: words("boolean byte char double float int long short void"),
        functionIntroducers: [], typeIntroducers: typeWords,
        lineComments: comments("//"), blockComment: cBlock,
        strings: [.init("\"\"\"", multiline: true), .init("\""), .init("'")],
        options: [.capitalizedTypes, .upperConstants, .decorators])

    static let kotlin = SyntaxGrammar(
        keywords: words(
            """
            abstract annotation as break by catch class companion const constructor continue crossinline \
            data do dynamic else enum expect external final finally for fun get if import in infix init \
            inline inner interface internal is lateinit noinline object open operator out override package \
            private protected public reified return sealed set super suspend tailrec this throw try \
            typealias val var vararg when where while
            """),
        constants: words("true false null"),
        functionIntroducers: functionWords, typeIntroducers: typeWords.union(["object"]),
        lineComments: comments("//"), blockComment: cBlock,
        strings: [.init("\"\"\"", multiline: true), .init("\""), .init("'")],
        options: [.capitalizedTypes, .upperConstants, .decorators])

    private static let cKeywords = words(
        """
        auto break case const continue default do else enum extern for goto if inline register restrict \
        return sizeof static struct switch typedef union volatile while
        """)
    private static let cTypes = words(
        """
        bool char double float int int8_t int16_t int32_t int64_t intptr_t long ptrdiff_t short signed \
        size_t ssize_t uint8_t uint16_t uint32_t uint64_t uintptr_t unsigned void wchar_t
        """)

    static let c = SyntaxGrammar(
        keywords: cKeywords, constants: words("true false NULL"), types: cTypes,
        typeIntroducers: ["struct", "enum", "union"],
        lineComments: comments("//"), blockComment: cBlock, strings: cStrings,
        options: [.capitalizedTypes, .upperConstants, .directives])

    static let cpp = SyntaxGrammar(
        keywords: cKeywords.union(
            words(
                """
                catch class constexpr const_cast decltype delete dynamic_cast explicit export final friend \
                mutable namespace new noexcept operator override private protected public reinterpret_cast \
                static_cast template this throw try typename using virtual
                """)),
        constants: words("true false NULL nullptr"), types: cTypes,
        typeIntroducers: ["class", "struct", "enum", "union", "namespace"],
        lineComments: comments("//"), blockComment: cBlock, strings: cStrings,
        options: [.capitalizedTypes, .upperConstants, .directives])

    static let objectiveC: SyntaxGrammar = {
        var grammar = cpp
        grammar.keywords.formUnion(["self", "super", "nil", "id"])
        grammar.options.insert(.decorators)
        return grammar
    }()

    static let csharp = SyntaxGrammar(
        keywords: words(
            """
            abstract as async await base bool break byte case catch char checked class const continue \
            decimal default delegate do double else enum event explicit extern finally fixed float for \
            foreach goto if implicit in init int interface internal is lock long namespace new object \
            operator out override params private protected public readonly record ref required return \
            sbyte sealed short sizeof stackalloc static string struct switch this throw try typeof uint \
            ulong unchecked unsafe ushort using var virtual void volatile while yield
            """),
        constants: words("true false null"),
        typeIntroducers: typeWords.union(["namespace"]),
        lineComments: comments("//"), blockComment: cBlock,
        strings: [.init("\"")],
        options: [.capitalizedTypes, .upperConstants, .directives])

    static let go = SyntaxGrammar(
        keywords: words(
            """
            break case chan const continue default defer else fallthrough for func go goto if import \
            interface map package range return select struct switch type var
            """),
        constants: words("true false nil iota"),
        types: words(
            """
            any bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune \
            string uint uint8 uint16 uint32 uint64 uintptr
            """),
        functionIntroducers: ["func"], typeIntroducers: ["type"],
        lineComments: comments("//"), blockComment: cBlock,
        strings: [.init("\""), .init("`", multiline: true, escapes: false), .init("'")],
        options: [])

    static let rust = SyntaxGrammar(
        keywords: words(
            """
            as async await break const continue crate dyn else enum extern fn for if impl in let loop match \
            mod move mut pub ref return self Self static struct super trait type unsafe use where while
            """),
        constants: words("true false"),
        types: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str"),
        functionIntroducers: ["fn"], typeIntroducers: ["struct", "enum", "trait", "impl", "type"],
        lineComments: comments("//"), blockComment: cBlock,
        strings: [.init("\""), .init("'")],
        options: [.capitalizedTypes, .upperConstants, .directives, .lifetimes, .macros])

    static let ruby = SyntaxGrammar(
        keywords: words(
            """
            alias and begin break case class def do else elsif end ensure for if in module next not or redo \
            rescue retry return self super then undef unless until when while yield
            """),
        constants: words("true false nil"),
        functionIntroducers: ["def"], typeIntroducers: ["class", "module"],
        lineComments: comments("#"), strings: [.init("\""), .init("'")],
        options: [.capitalizedTypes, .upperConstants, .decorators])

    static let php = SyntaxGrammar(
        keywords: words(
            """
            abstract and array as break callable case catch class clone const continue declare default do \
            echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final \
            finally fn for foreach function global goto if implements include include_once instanceof \
            insteadof interface isset list match namespace new or print private protected public readonly \
            require require_once return static switch throw trait try unset use var while xor yield
            """),
        constants: words("true false null TRUE FALSE NULL"),
        functionIntroducers: ["function", "fn"], typeIntroducers: ["class", "interface", "trait"],
        lineComments: comments("//", "#"), blockComment: cBlock, strings: cStrings,
        options: [.capitalizedTypes, .upperConstants, .dollarVariables])

    static let lua = SyntaxGrammar(
        keywords: words(
            """
            and break do else elseif end for function goto if in local not or repeat return then until while
            """),
        constants: words("true false nil"),
        functionIntroducers: ["function"],
        lineComments: comments("--"), blockComment: BlockComment("--[[", "]]"),
        strings: [.init("\""), .init("'")])

    static let sql = SyntaxGrammar(
        keywords: words(
            """
            add all alter and as asc begin between by case check column commit constraint create cross \
            database default delete desc distinct drop else end exists foreign from full group having if \
            ilike in index inner insert into is join key left like limit not offset on or order outer over \
            partition primary recursive references returning right rollback schema select set table \
            then transaction truncate union unique update values view when where with
            """),
        constants: words("null true false"),
        types: words(
            """
            bigint bigserial blob bool boolean bytea char date datetime decimal double float int integer \
            json jsonb numeric real serial smallint text time timestamp timestamptz tinyint uuid varchar
            """),
        lineComments: comments("--"), blockComment: cBlock,
        strings: [.init("'", escapes: false, doubling: true), .init("\"", escapes: false)],
        options: [.caseInsensitive])

    static let shell = SyntaxGrammar(
        keywords: words(
            "case do done elif else esac fi for function if in select then time until while"),
        lineComments: comments("#"),
        strings: [.init("\""), .init("'", escapes: false)],
        options: [.shell, .dollarVariables, .plainCalls])

    static let dockerfile = SyntaxGrammar(
        keywords: words(
            """
            ADD ARG AS CMD COPY ENTRYPOINT ENV EXPOSE FROM HEALTHCHECK LABEL MAINTAINER ONBUILD RUN SHELL \
            STOPSIGNAL USER VOLUME WORKDIR
            """),
        lineComments: comments("#"),
        strings: [.init("\""), .init("'", escapes: false)],
        options: [.dollarVariables, .plainCalls])

    static let json = SyntaxGrammar(
        constants: words("true false null"),
        lineComments: comments("//"), blockComment: cBlock, strings: [.init("\"")],
        options: [.keyedStrings, .plainCalls])

    static let yaml = SyntaxGrammar(
        constants: words("true false null yes no on off True False Null Yes No On Off"),
        lineComments: comments("#"), strings: [.init("\""), .init("'", escapes: false, doubling: true)],
        lineKeys: .colon, options: [.plainCalls])

    static let toml = SyntaxGrammar(
        constants: words("true false"),
        lineComments: comments("#"),
        strings: [
            .init("\"\"\"", multiline: true), .init("'''", multiline: true, escapes: false), .init("\""),
            .init("'", escapes: false)
        ],
        lineKeys: .equals, options: [.plainCalls])

    static let ini = SyntaxGrammar(
        constants: words("true false yes no on off"),
        lineComments: comments(";", "#"),
        strings: [.init("\""), .init("'", escapes: false)],
        lineKeys: .equals, options: [.plainCalls])
}
