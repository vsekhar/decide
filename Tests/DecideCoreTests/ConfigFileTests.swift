import Testing

@testable import DecideCore

/// The file every test names, so each error proves it carries the path.
private let path = "/tmp/x/.decide/config"

/// Parses text as the file at `path`.
private func parse(_ text: String) throws -> [Entry] {
    try ConfigFile.parse(text, path: path)
}

/// The error a line must throw.
private func failure(line: Int, _ problem: String) -> ConfigError {
    ConfigError(path: path, line: line, problem: problem)
}

/// What a value that is not a quoted string reports.
private let quotedValue = """
    value must be a quoted string, for example DECIDE_MODEL = "typesafe:jev-latest"
    """

@Suite("ConfigFile")
struct ConfigFileTests {
    @Test("Both keys take a basic string")
    func basicStrings() throws {
        let entries = try parse(
            """
            DECIDE_MODEL = "typesafe:jev-latest"
            DECIDE_MODEL_API_KEY = "sk-test"
            """
        )
        #expect(
            entries == [
                Entry(key: "DECIDE_MODEL", value: "typesafe:jev-latest", line: 1),
                Entry(key: "DECIDE_MODEL_API_KEY", value: "sk-test", line: 2),
            ]
        )
    }

    @Test("A literal string keeps every character")
    func literalStrings() throws {
        let entries = try parse(
            #"""
            DECIDE_MODEL = 'typesafe:jev-latest'
            DECIDE_MODEL_API_KEY = 'sk-a\b'
            """#
        )
        #expect(
            entries == [
                Entry(key: "DECIDE_MODEL", value: "typesafe:jev-latest", line: 1),
                Entry(key: "DECIDE_MODEL_API_KEY", value: #"sk-a\b"#, line: 2),
            ]
        )
    }

    @Test("Each of the five escapes is decoded")
    func escapes() throws {
        let cases: [(text: String, value: String)] = [
            (#"DECIDE_MODEL = "a\"b""#, "a\"b"),
            (#"DECIDE_MODEL = "a\\b""#, "a\\b"),
            (#"DECIDE_MODEL = "a\nb""#, "a\nb"),
            (#"DECIDE_MODEL = "a\tb""#, "a\tb"),
            (#"DECIDE_MODEL = "a\rb""#, "a\rb"),
        ]
        for (text, value) in cases {
            let entries = try parse(text)
            #expect(entries == [Entry(key: "DECIDE_MODEL", value: value, line: 1)], "\(text)")
        }
    }

    @Test("A comment line, a trailing comment, and a # in quotes")
    func comments() throws {
        let entries = try parse(
            """
            # the model to use
            DECIDE_MODEL = "typesafe:jev-latest" # the newest
            DECIDE_MODEL_API_KEY = "sk-a#b"
            """
        )
        #expect(
            entries == [
                Entry(key: "DECIDE_MODEL", value: "typesafe:jev-latest", line: 2),
                Entry(key: "DECIDE_MODEL_API_KEY", value: "sk-a#b", line: 3),
            ]
        )
    }

    @Test("A trailing comment needs no space before its #")
    func tightComment() throws {
        let entries = try parse("DECIDE_MODEL = \"a\"# why\n")
        #expect(entries == [Entry(key: "DECIDE_MODEL", value: "a", line: 1)])
    }

    @Test("Blank and whitespace-only lines are skipped")
    func blankLines() throws {
        let entries = try parse("\n   \n\t\nDECIDE_MODEL = \"a\"\n")
        #expect(entries == [Entry(key: "DECIDE_MODEL", value: "a", line: 4)])
    }

    @Test("CRLF endings read as lines")
    func carriageReturnLineFeed() throws {
        let entries = try parse("DECIDE_MODEL = \"a\"\r\nDECIDE_MODEL_API_KEY = \"b\"\r\n")
        #expect(
            entries == [
                Entry(key: "DECIDE_MODEL", value: "a", line: 1),
                Entry(key: "DECIDE_MODEL_API_KEY", value: "b", line: 2),
            ]
        )
    }

    @Test("A leading byte order mark is dropped")
    func byteOrderMark() throws {
        let entries = try parse("\u{FEFF}DECIDE_MODEL = \"a\"\n")
        #expect(entries == [Entry(key: "DECIDE_MODEL", value: "a", line: 1)])
    }

    @Test("Spaces or tabs around the = are optional")
    func spacingAroundEquals() throws {
        let texts = [
            "DECIDE_MODEL=\"a\"",
            "DECIDE_MODEL = \"a\"",
            "DECIDE_MODEL   =   \"a\"",
            "DECIDE_MODEL\t=\t\"a\"",
            "  DECIDE_MODEL =\t\"a\"  ",
        ]
        for text in texts {
            let entries = try parse(text)
            #expect(entries == [Entry(key: "DECIDE_MODEL", value: "a", line: 1)], "\(text)")
        }
    }

    @Test("Entries come back in file order with their line numbers")
    func fileOrder() throws {
        let entries = try parse(
            """
            # a comment

            DECIDE_MODEL_API_KEY = "b"

            DECIDE_MODEL = "a"
            """
        )
        #expect(
            entries == [
                Entry(key: "DECIDE_MODEL_API_KEY", value: "b", line: 3),
                Entry(key: "DECIDE_MODEL", value: "a", line: 5),
            ]
        )
    }

    @Test("A value may hold an = sign")
    func valueWithEquals() throws {
        let entries = try parse("DECIDE_MODEL_API_KEY = \"a=b=c\"\n")
        #expect(entries == [Entry(key: "DECIDE_MODEL_API_KEY", value: "a=b=c", line: 1)])
    }

    @Test("Each string kind holds the other kind's quote")
    func quotesInsideStrings() throws {
        let entries = try parse(
            #"""
            DECIDE_MODEL = "it's"
            DECIDE_MODEL_API_KEY = 'say "hi"'
            """#
        )
        #expect(
            entries == [
                Entry(key: "DECIDE_MODEL", value: "it's", line: 1),
                Entry(key: "DECIDE_MODEL_API_KEY", value: #"say "hi""#, line: 2),
            ]
        )
    }

    @Test("A value that is not a quoted string is refused")
    func bareValues() {
        let texts = [
            "DECIDE_MODEL = typesafe:jev-latest",
            "DECIDE_MODEL = 1",
            "DECIDE_MODEL = true",
        ]
        for text in texts {
            #expect(throws: failure(line: 1, quotedValue), "\(text)") {
                try parse(text)
            }
        }
    }

    @Test("Nothing after the = is refused")
    func missingValue() {
        #expect(throws: failure(line: 1, quotedValue)) {
            try parse("DECIDE_MODEL =\n")
        }
        #expect(throws: failure(line: 1, quotedValue)) {
            try parse("DECIDE_MODEL =   \n")
        }
    }

    @Test("An unknown key names the keys the tool takes")
    func unknownKey() {
        #expect(
            throws: failure(
                line: 2,
                "unknown key \"DECIDE_MODE\"; the keys are DECIDE_MODEL and DECIDE_MODEL_API_KEY"
            )
        ) {
            try parse("DECIDE_MODEL = \"a\"\nDECIDE_MODE = \"b\"\n")
        }
    }

    @Test("A quoted key is refused")
    func quotedKey() {
        #expect(throws: failure(line: 1, "quoted keys are not supported")) {
            try parse("\"DECIDE_MODEL\" = \"a\"\n")
        }
        #expect(throws: failure(line: 1, "quoted keys are not supported")) {
            try parse("'DECIDE_MODEL' = 'a'\n")
        }
    }

    @Test("A dotted key is refused")
    func dottedKey() {
        #expect(throws: failure(line: 1, "dotted keys are not supported")) {
            try parse("server.DECIDE_MODEL = \"a\"\n")
        }
    }

    @Test("A key with a space is refused")
    func keyWithSpace() {
        #expect(throws: failure(line: 1, "expected key = \"value\"")) {
            try parse("DECIDE MODEL = \"a\"\n")
        }
    }

    @Test("A key set twice names the first line")
    func repeatedKey() {
        #expect(throws: failure(line: 3, "DECIDE_MODEL is set twice, first on line 1")) {
            try parse("DECIDE_MODEL = \"a\"\n# a comment\nDECIDE_MODEL = \"b\"\n")
        }
    }

    @Test("An empty string value is refused")
    func emptyValue() {
        #expect(throws: failure(line: 1, "DECIDE_MODEL is empty")) {
            try parse("DECIDE_MODEL = \"\"\n")
        }
        #expect(throws: failure(line: 1, "DECIDE_MODEL is empty")) {
            try parse("DECIDE_MODEL = ''\n")
        }
        // Only whitespace counts as empty too, since every consumer trims.
        #expect(throws: failure(line: 1, "DECIDE_MODEL is empty")) {
            try parse("DECIDE_MODEL = \" \\t \"\n")
        }
    }

    @Test("An unterminated string is refused")
    func unterminatedString() {
        #expect(throws: failure(line: 1, "unterminated string")) {
            try parse("DECIDE_MODEL = \"abc\n")
        }
        #expect(throws: failure(line: 1, "unterminated string")) {
            try parse("DECIDE_MODEL = 'abc\n")
        }
    }

    @Test("A backslash at the end of the line is refused")
    func trailingBackslash() {
        #expect(throws: failure(line: 1, "unterminated string")) {
            try parse(#"DECIDE_MODEL = "abc\"# + "\n")
        }
    }

    @Test("An escape the subset leaves out names the character")
    func unsupportedEscape() {
        #expect(throws: failure(line: 1, #"unsupported escape \u"#)) {
            try parse("DECIDE_MODEL = \"a\\u0041b\"\n")
        }
        #expect(throws: failure(line: 1, #"unsupported escape \x"#)) {
            try parse("DECIDE_MODEL = \"a\\x41b\"\n")
        }
    }

    @Test("A table is refused")
    func table() {
        #expect(throws: failure(line: 1, "tables are not supported")) {
            try parse("[model]\nDECIDE_MODEL = \"a\"\n")
        }
    }

    @Test("An array is refused")
    func array() {
        #expect(throws: failure(line: 1, "arrays are not supported")) {
            try parse("DECIDE_MODEL = [1]\n")
        }
    }

    @Test("An inline table is refused")
    func inlineTable() {
        #expect(throws: failure(line: 1, "inline tables are not supported")) {
            try parse("DECIDE_MODEL = { a = 1 }\n")
        }
    }

    @Test("A multi-line string is refused")
    func multiLineString() {
        #expect(throws: failure(line: 1, "multi-line strings are not supported")) {
            try parse(#"DECIDE_MODEL = """a""""#)
        }
        #expect(throws: failure(line: 1, "multi-line strings are not supported")) {
            try parse(#"DECIDE_MODEL = '''a'''"#)
        }
    }

    @Test("A line with no = is refused")
    func noEquals() {
        #expect(throws: failure(line: 1, "expected key = \"value\"")) {
            try parse("DECIDE_MODEL\n")
        }
    }

    @Test("Text after the value is refused")
    func textAfterTheValue() {
        #expect(throws: failure(line: 1, "text after the value")) {
            try parse("DECIDE_MODEL = \"a\" b\n")
        }
        #expect(throws: failure(line: 1, "text after the value")) {
            try parse("DECIDE_MODEL = \"a\" \"b\"\n")
        }
    }

    @Test("A raw control character in a string is refused")
    func controlCharacter() {
        #expect(throws: failure(line: 1, "control character in the value")) {
            try parse("DECIDE_MODEL = \"a\u{01}b\"\n")
        }
        #expect(throws: failure(line: 1, "control character in the value")) {
            try parse("DECIDE_MODEL = 'a\u{01}b'\n")
        }
        // After a backslash too, so no message carries a raw control character.
        #expect(throws: failure(line: 1, "control character in the value")) {
            try parse("DECIDE_MODEL = \"a\\\u{01}b\"\n")
        }
    }

    @Test("A lone carriage return in the middle of a line is refused")
    func loneCarriageReturn() {
        #expect(throws: failure(line: 1, "control character in the value")) {
            try parse("DECIDE_MODEL = \"a\rb\"\n")
        }
    }

    @Test("A control character in a comment is refused")
    func controlCharacterInComment() {
        #expect(throws: failure(line: 1, "control character in a comment")) {
            try parse("# a\u{01}b\nDECIDE_MODEL = \"a\"\n")
        }
        #expect(throws: failure(line: 1, "control character in a comment")) {
            try parse("DECIDE_MODEL = \"a\" # \u{01}\n")
        }
    }

    @Test("A carriage return with no line feed after it is not a line ending")
    func carriageReturnAtEnd() {
        #expect(throws: failure(line: 1, "text after the value")) {
            try parse("DECIDE_MODEL = \"a\"\r")
        }
        #expect(throws: failure(line: 1, "control character in a comment")) {
            try parse("# c\r")
        }
    }
}
