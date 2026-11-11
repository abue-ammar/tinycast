import Foundation

@main
@MainActor
struct SyntaxHighlightTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        fenceNamesPickTheLanguage()
        unknownLanguagesStayPlain()
        swiftReadsLikeSwift()
        pythonReadsLikePython()
        scriptsReadAsCode()
        dataFilesKeepKeysApart()
        shellColoursOnlyTheCommand()
        sqlIgnoresCase()
        systemsLanguagesKeepTheirSigils()
        markupReadsTagsAndEmbeddedScripts()
        stylesheetsSeparateSelectorsFromValues()
        diffsColourWholeLines()
        rangesAreUTF16()
        streamingNeverBreaksTheScan()
        hugeBlocksStayPlain()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    struct Piece: Equatable {
        let text: String
        let kind: SyntaxKind
    }

    static func pieces(_ code: String, _ language: String?) -> [Piece] {
        let text = code as NSString
        return SyntaxHighlighter.tokens(in: code, language: language)
            .sorted { $0.range.location < $1.range.location }
            .map { Piece(text: text.substring(with: $0.range), kind: $0.kind) }
    }

    static func colours(_ code: String, _ language: String, _ text: String, as kind: SyntaxKind) -> Bool {
        pieces(code, language).contains(Piece(text: text, kind: kind))
    }

    static func check(_ code: String, _ language: String, _ expected: [(String, SyntaxKind)]) {
        for (text, kind) in expected {
            expect(
                colours(code, language, text, as: kind),
                "\(language): \(text.debugDescription) is \(kind), got \(pieces(code, language))")
        }
    }

    static func fenceNamesPickTheLanguage() {
        let code = "let x = 1"
        for name in ["swift", "Swift", "SWIFT", "swift title=main.swift", "swift{1,3}"] {
            expect(colours(code, name, "let", as: .keyword), "the fence \(name.debugDescription) is Swift")
        }
        for name in ["js", "javascript", "jsx", "mjs"] {
            expect(colours("const a = 1", name, "const", as: .keyword), "\(name) is JavaScript")
        }
        for name in ["ts", "tsx", "typescript"] {
            expect(colours("interface A {}", name, "interface", as: .keyword), "\(name) is TypeScript")
        }
        for name in ["sh", "bash", "zsh", "shell", "console"] {
            expect(colours("git status", name, "git", as: .function), "\(name) is shell")
        }
        for name in ["c++", "cpp", "cc", "hpp"] {
            expect(colours("namespace a {}", name, "namespace", as: .keyword), "\(name) is C++")
        }
    }

    static func unknownLanguagesStayPlain() {
        for name in [nil, "", "text", "plaintext", "markdown", "klingon", "  "] {
            expect(
                SyntaxHighlighter.tokens(in: "let x = 1 // not code", language: name).isEmpty,
                "\(name.debugDescription) is left plain")
        }
    }

    static func swiftReadsLikeSwift() {
        let code = """
            @MainActor struct Point: Codable {
                let x = 42 // origin
                func scaled(by factor: Double) -> Point { Point(x: "a\\(x)") }
                #if DEBUG
                #endif
            }
            """
        check(
            code, "swift",
            [
                ("@MainActor", .attribute), ("struct", .keyword), ("Point", .type), ("Codable", .type),
                ("let", .keyword), ("42", .number), ("// origin", .comment), ("func", .keyword),
                ("scaled", .function), ("Double", .type), ("\"a\\(x)\"", .string), ("#if", .attribute)
            ])
        expect(!colours(code, "swift", "x", as: .keyword), "a name is not a keyword")
        check("let a = foo.init(); b.self", "swift", [("init", .function)])
        expect(
            !colours("view.default", "swift", "default", as: .keyword),
            "a member named like a keyword is plain")
    }

    static func pythonReadsLikePython() {
        let code = """
            @dataclass
            class Point(Base):
                def __init__(self, x: int = 0):
                    self.label = f"v={x}"  # note
                    return None

            match command:
                case "go": pass
            MAX_SIZE = 10
            doc = \"\"\"two
            lines\"\"\"
            """
        check(
            code, "python",
            [
                ("@dataclass", .attribute), ("class", .keyword), ("Point", .type), ("Base", .type),
                ("def", .keyword), ("__init__", .function), ("self", .keyword), ("int", .type),
                ("f\"v={x}\"", .string), ("# note", .comment), ("None", .constant), ("match", .keyword),
                ("case", .keyword), ("MAX_SIZE", .constant), ("\"\"\"two\nlines\"\"\"", .string)
            ])
        expect(
            !colours("match = re.match(p, s)", "python", "match", as: .keyword),
            "a variable named match is not the keyword")
        expect(
            colours("x = '#not a comment'", "python", "'#not a comment'", as: .string),
            "a hash inside a string")
    }

    static func scriptsReadAsCode() {
        let javascript = """
            const total = items.reduce((a, b) => a + b, 0)
            console.log(`hello ${name}`)
            export type Alias = string
            """
        check(
            javascript, "js",
            [
                ("const", .keyword), ("reduce", .function), ("log", .function),
                ("`hello ${name}`", .string)
            ])
        expect(!colours(javascript, "js", "type", as: .keyword), "type is a plain word in JavaScript")
        check(
            "export type Alias = string", "ts",
            [("export", .keyword), ("type", .keyword), ("Alias", .type), ("string", .type)])
        check("type = 5", "ts", [("5", .number)])
        expect(!colours("type = 5", "ts", "type", as: .keyword), "an assignment to type is not a declaration")
        check(
            "let a = 0xFF + 1_000 + 3.5e-2 + .5", "ts",
            [("0xFF", .number), ("1_000", .number), ("3.5e-2", .number), (".5", .number)])
    }

    static func dataFilesKeepKeysApart() {
        check(
            #"{"name": "tiny", "n": -1.5e3, "ok": true, "x": null, "list": ["a"]}"#, "json",
            [
                ("\"name\"", .property), ("\"tiny\"", .string), ("1.5e3", .number), ("true", .constant),
                ("null", .constant), ("\"a\"", .string)
            ])
        let yaml = """
            name: tinycast  # the app
            list:
              - a: 1
              - "quoted": yes
            url: http://example.com/x
            """
        check(
            yaml, "yaml",
            [
                ("name", .property), ("# the app", .comment), ("list", .property), ("a", .property),
                ("1", .number), ("\"quoted\"", .property), ("yes", .constant), ("url", .property)
            ])
        expect(!colours(yaml, "yaml", "http", as: .property), "a URL is not a key")
        let toml = """
            [server]
            host = "localhost" # name
            port = 8080
            """
        check(
            toml, "toml",
            [
                ("[server]", .type), ("host", .property), ("\"localhost\"", .string),
                ("# name", .comment), ("port", .property), ("8080", .number)
            ])
    }

    static func shellColoursOnlyTheCommand() {
        let code = """
            $ git commit -m "msg" # note
            if [ -f x ]; then echo $HOME ${PATH}; fi
            sudo rm -rf /tmp/x | grep foo
            """
        check(
            code, "bash",
            [
                ("git", .function), ("-m", .attribute), ("\"msg\"", .string), ("# note", .comment),
                ("if", .keyword), ("-f", .attribute), ("then", .keyword), ("echo", .function),
                ("$HOME", .property), ("${PATH}", .property), ("fi", .keyword), ("sudo", .function),
                ("rm", .function), ("-rf", .attribute), ("grep", .function)
            ])
        expect(!colours(code, "bash", "commit", as: .function), "an argument is not a command")
        expect(!colours(code, "bash", "foo", as: .function), "an argument after a pipe's command is plain")
        check("echo $# and ${#list[@]}", "sh", [("$#", .property)])
        expect(
            pieces("echo $# and a#b", "sh").allSatisfy { $0.kind != .comment },
            "a hash inside a word starts no comment")
        check("FROM swift:6 AS build\nRUN swift build", "dockerfile", [("FROM", .keyword), ("RUN", .keyword)])
    }

    static func sqlIgnoresCase() {
        let code = "select name, Count(*) from users where city = 'it''s' -- why\n/* block */ LIMIT 5"
        check(
            code, "sql",
            [
                ("select", .keyword), ("Count", .function), ("from", .keyword), ("where", .keyword),
                ("'it''s'", .string), ("-- why", .comment), ("/* block */", .comment), ("LIMIT", .keyword),
                ("5", .number)
            ])
        check("create table t (id int, name varchar(20))", "sql", [("int", .type), ("table", .keyword)])
    }

    static func systemsLanguagesKeepTheirSigils() {
        check(
            "#include <stdio.h>\nint main(void) { printf(\"hi\"); return NULL; }", "c",
            [
                ("#include", .attribute), ("<stdio.h>", .string), ("int", .type), ("main", .function),
                ("printf", .function), ("NULL", .constant)
            ])
        let rust = """
            fn main() { let s: &'static str = "x"; println!("{}", s); }
            #[derive(Debug)]
            struct Foo<'a> { x: &'a i32 }
            """
        check(
            rust, "rust",
            [
                ("fn", .keyword), ("main", .function), ("'static", .attribute), ("println", .function),
                ("#[derive(Debug)]", .attribute), ("Foo", .type), ("'a", .attribute), ("i32", .type)
            ])
        expect(colours("let c = 'x'", "rust", "'x'", as: .string), "a character literal is a string")
        check(
            "package main\nfunc (p Person) Name() string { return fmt.Sprintf(\"%d\", 1) }\ntype Person struct{}",
            "go",
            [
                ("func", .keyword), ("Name", .function), ("Sprintf", .function), ("Person", .type),
                ("string", .type)
            ])
        check(
            "@Override\npublic static void main(String[] args) {}", "java",
            [("@Override", .attribute), ("public", .keyword), ("String", .type), ("main", .function)])
        check(
            "local function go() return nil end -- done\n--[[ block ]]", "lua",
            [("-- done", .comment), ("--[[ block ]]", .comment)])
        check(
            "$name = strlen($input); // done", "php",
            [("$name", .property), ("strlen", .function), ("// done", .comment)])
        check(
            "def greet(name)\n  puts \"hi\"\nend", "ruby",
            [("def", .keyword), ("greet", .function), ("end", .keyword)])
    }

    static func markupReadsTagsAndEmbeddedScripts() {
        let code = """
            <div class="a" id=b>text &amp; more<br/></div><!-- note -->
            <script>let x = 1</script><style>a { color: red }</style>
            """
        check(
            code, "html",
            [
                ("<div", .keyword), ("class", .property), ("\"a\"", .string), ("b", .string),
                ("&amp;", .constant), ("<br", .keyword), ("/>", .keyword), ("</div", .keyword),
                ("<!-- note -->", .comment), ("let", .keyword), ("1", .number), ("color", .property)
            ])
        expect(!colours(code, "html", "text", as: .keyword), "text between tags is plain")
        expect(pieces("if a < b && c > d", "html").isEmpty, "a comparison is not a tag")
        check(
            "<?xml version=\"1.0\"?>\n<root xmlns:a=\"u\"/>", "xml",
            [("<root", .keyword), ("xmlns:a", .property)])
    }

    static func stylesheetsSeparateSelectorsFromValues() {
        let code = """
            @media (max-width: 600px) { a:hover, .btn#main { color: #fff; margin: 0 auto 12px; background: url(a.png) } }
            :root { --accent: rgb(10, 20, 30) !important; }
            """
        check(
            code, "css",
            [
                ("@media", .keyword), ("600px", .number), ("a", .keyword), (":hover", .attribute),
                (".btn", .type), ("#main", .type), ("color", .property), ("#fff", .number),
                ("margin", .property), ("12px", .number), ("url", .function), ("--accent", .property),
                ("rgb", .function), ("!important", .keyword)
            ])
        expect(!colours(code, "css", "max-width", as: .keyword), "a media feature is not a tag")
        expect(!colours(code, "css", "a.png", as: .property), "a url is not scanned as css")
    }

    static func diffsColourWholeLines() {
        let code = "--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n-old\n+new\n same"
        check(
            code, "diff",
            [
                ("--- a/x", .comment), ("+++ b/x", .comment), ("@@ -1,2 +1,2 @@", .type), ("-old", .deleted),
                ("+new", .inserted)
            ])
        expect(!pieces(code, "diff").contains { $0.text.contains("same") }, "a context line is plain")
    }

    static func rangesAreUTF16() {
        let code = "let s = \"😀 café\" + 42"
        let text = code as NSString
        let number = SyntaxHighlighter.tokens(in: code, language: "swift").first { $0.kind == .number }
        expect(
            number.map { text.substring(with: $0.range) == "42" } ?? false,
            "a number after an emoji still lands on its digits")
    }

    static func streamingNeverBreaksTheScan() {
        let samples: [(String, String)] = [
            ("swift", "@MainActor final class A { func f() { let s = \"\"\"\nx\n\"\"\" /* c */ } }"),
            ("python", "f\"a{b}\" rb'x' \"\"\"doc\"\"\" # c\n@d\nclass X(Y): pass"),
            ("html", "<a href=\"x\" b=c><!-- c --><script>var x = '1'</script></a> &amp"),
            ("css", "a:hover { color: #fff; background: url(x.png) } /* c */ @media (a: b) {}"),
            ("bash", "$ echo \"$a ${b}\" | grep -rn 'x' # c\nif [ -f x ]; then :; fi"),
            ("yaml", "- \"a\": b\n  c: 'd' # e\nurl: http://x"),
            ("rust", "#![allow(x)] fn f<'a>(x: &'a str) { println!(\"{}\", 'c'); }"),
            ("sql", "SELECT 'a''b', \"c\" FROM t -- x\n/* y"),
            ("diff", "@@ -1 +1 @@\n-a\n+b")
        ]
        for (language, sample) in samples {
            let units = Array(sample.utf16)
            for length in 0...units.count {
                let prefix = String(decoding: units[0..<length], as: UTF16.self)
                let tokens = SyntaxHighlighter.tokens(in: prefix, language: language)
                var end = 0
                var sound = true
                for token in tokens.sorted(by: { $0.range.location < $1.range.location }) {
                    sound = sound && token.range.location >= end && token.range.length > 0
                    end = token.range.location + token.range.length
                }
                sound = sound && end <= length
                expect(sound, "\(language) prefix \(length) keeps its tokens ordered and in bounds")
                if !sound { break }
            }
        }
    }

    static func hugeBlocksStayPlain() {
        let line = "let value = 42 // a line of code\n"
        let big = String(repeating: line, count: SyntaxHighlighter.sizeLimit / line.utf16.count + 2)
        expect(
            SyntaxHighlighter.tokens(in: big, language: "swift").isEmpty, "a block past the limit is plain")
        let fits = String(repeating: line, count: SyntaxHighlighter.sizeLimit / line.utf16.count - 2)
        expect(
            !SyntaxHighlighter.tokens(in: fits, language: "swift").isEmpty, "a block under the limit is read")
    }
}
