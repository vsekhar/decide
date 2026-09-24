import Testing

@testable import DecideCore

/// The file every test names, so each error proves it carries the path.
private let path = "/tmp/x/triage.txt"

/// Splits text as the file at `path`.
private func tokens(_ text: String) throws -> [QuestionFile.Token] {
    try QuestionFile.tokens(of: text, path: path)
}

/// A token and the line it starts on.
private func token(_ text: String, _ line: Int) -> QuestionFile.Token {
    QuestionFile.Token(text: text, line: line)
}

/// The error a quote with no end must throw.
private func unterminated(line: Int) -> ConfigError {
    ConfigError(path: path, line: line, problem: "unterminated quote")
}

@Suite("QuestionFile")
struct QuestionFileTests {
    @Test("The README's triage.txt gives its tokens and their lines")
    func readmeExample() throws {
        let result = try tokens(
            """
            "Which team handles this ticket"
                --option shipping
                --option billing
                --option returns

            "How urgent is this ticket"
                --level not_urgent
                --level somewhat_urgent
                --level urgent

            "Should we issue a refund"

            """
        )
        #expect(
            result == [
                token("Which team handles this ticket", 1),
                token("--option", 2), token("shipping", 2),
                token("--option", 3), token("billing", 3),
                token("--option", 4), token("returns", 4),
                token("How urgent is this ticket", 6),
                token("--level", 7), token("not_urgent", 7),
                token("--level", 8), token("somewhat_urgent", 8),
                token("--level", 9), token("urgent", 9),
                token("Should we issue a refund", 11),
            ]
        )
    }

    @Test("Leading and trailing whitespace is dropped")
    func outerWhitespace() throws {
        #expect(try tokens("  \n  a b  \n\n") == [token("a", 2), token("b", 2)])
    }

    @Test("A tab separates tokens")
    func tabs() throws {
        #expect(try tokens("\ta\tb\t") == [token("a", 1), token("b", 1)])
    }

    @Test("CRLF endings separate lines")
    func carriageReturnLineFeed() throws {
        #expect(try tokens("a\r\nb\r\n") == [token("a", 1), token("b", 2)])
    }

    @Test("A leading byte order mark is dropped")
    func byteOrderMark() throws {
        #expect(try tokens("\u{FEFF}a") == [token("a", 1)])
    }

    @Test("A comment line and a trailing comment are dropped; a # inside a word is kept")
    func comments() throws {
        let result = try tokens(
            """
            # the team
            a # why
            b#c
            """
        )
        #expect(result == [token("a", 2), token("b#c", 3)])
    }

    @Test("A # right after a closing quote is inside the word, as in a shell")
    func hashAfterQuote() throws {
        #expect(try tokens("\"a\"#c") == [token("a#c", 1)])
    }

    @Test("Single quotes keep a backslash and a #")
    func singleQuotes() throws {
        #expect(try tokens(#"'a\b #c'"#) == [token(#"a\b #c"#, 1)])
    }

    @Test("Double quotes decode \\\" and \\\\ and keep any other pair as typed")
    func doubleQuotes() throws {
        #expect(try tokens(#""a\"b\\c\nd""#) == [token(#"a"b\c\nd"#, 1)])
    }

    @Test("A quote may span lines; the token's line is where it opens")
    func quoteSpanningLines() throws {
        let result = try tokens("a\n\"b\nc\" d\ne")
        #expect(result == [token("a", 1), token("b\nc", 2), token("d", 3), token("e", 4)])
    }

    @Test("Quotes inside a word join with the text around them")
    func quotesInsideAWord() throws {
        #expect(
            try tokens(#"shipping="Delivery issues""#) == [token("shipping=Delivery issues", 1)]
        )
        #expect(try tokens(#""a"'b'c"#) == [token("abc", 1)])
    }

    @Test("An empty quoted pair is an empty token")
    func emptyToken() throws {
        #expect(try tokens(#"a "" b"#) == [token("a", 1), token("", 1), token("b", 1)])
        #expect(try tokens("''") == [token("", 1)])
    }

    @Test("An unterminated quote names the line it opens on")
    func unterminatedQuote() {
        #expect(throws: unterminated(line: 2)) {
            try tokens("a\n\"b\nc")
        }
        #expect(throws: unterminated(line: 3)) {
            try tokens("a\n\nb 'c\nd")
        }
        // An escaped quote does not end a double-quoted string.
        #expect(throws: unterminated(line: 1)) {
            try tokens(#""a\""#)
        }
    }

    @Test("Empty text and comment-only text give no tokens")
    func noTokens() throws {
        #expect(try tokens("") == [])
        #expect(try tokens("# one\n  # two\n") == [])
    }

    @Test("A backslash outside quotes is an ordinary character")
    func bareBackslash() throws {
        #expect(try tokens(#"a\b c\"#) == [token(#"a\b"#, 1), token(#"c\"#, 1)])
    }

    @Test("Nothing is expanded: variables, tildes, and command substitutions stay as typed")
    func noExpansion() throws {
        #expect(
            try tokens("$HOME ~ ${x} $(ls) `ls`")
                == [token("$HOME", 1), token("~", 1), token("${x}", 1), token("$(ls)", 1), token("`ls`", 1)]
        )
    }

    @Test("A lone carriage return separates tokens but starts no line")
    func loneCarriageReturn() throws {
        #expect(
            try tokens("a\rb\n'c\rd' e")
                == [token("a", 1), token("b", 1), token("c\rd", 2), token("e", 2)]
        )
    }
}

/// The README's `triage.txt`, as the file at `path`.
private let readmeFile = """
    "Which team handles this ticket"
        --option shipping
        --option billing
        --option returns

    "How urgent is this ticket"
        --level not_urgent
        --level somewhat_urgent
        --level urgent

    "Should we issue a refund"

    """

/// Expands the line with a reader that gives the text in `files`, throws the
/// error in `failing`, and gives nil for any other path.
private func expand(
    _ arguments: [String],
    files: [String: String] = [:],
    failing: [String: ConfigReadError] = [:]
) throws -> [QuestionFile.Item] {
    try QuestionFile.expanding(arguments) { (path: String) throws(ConfigReadError) -> String? in
        if let error = failing[path] { throw error }
        return files[path]
    }
}

/// Each argument as a token item.
private func items(_ arguments: [String]) -> [QuestionFile.Item] {
    arguments.map(QuestionFile.Item.token)
}

/// The error a file refuses with, at `path`.
private func refused(line: Int, _ problem: String) -> ConfigError {
    ConfigError(path: path, line: line, problem: problem)
}

@Suite("QuestionFile expansion")
struct QuestionFileExpansionTests {
    @Test("The README line gives the context flag, then the file's 15 tokens")
    func readmeLine() throws {
        let result = try expand(
            ["--context", "@ticket.txt", "--questions", "@\(path)"], files: [path: readmeFile]
        )
        #expect(
            result
                == items([
                    "--context", "@ticket.txt",
                    "Which team handles this ticket",
                    "--option", "shipping", "--option", "billing", "--option", "returns",
                    "How urgent is this ticket",
                    "--level", "not_urgent", "--level", "somewhat_urgent", "--level", "urgent",
                    "Should we issue a refund",
                ])
        )
    }

    @Test("A question before and after the flag keeps its place")
    func questionsAroundTheFlag() throws {
        let result = try expand(
            ["A", "--questions", "@\(path)", "B"], files: [path: "C --option x"]
        )
        #expect(result == items(["A", "C", "--option", "x", "B"]))
    }

    @Test("Two --questions flags each splice their own file")
    func twoFlags() throws {
        let result = try expand(
            ["--questions", "@a", "--questions", "@b"], files: ["a": "A", "b": "B --yes y"]
        )
        #expect(result == items(["A", "B", "--yes", "y"]))
    }

    @Test("--questions=@path reads the file")
    func equalsForm() throws {
        #expect(try expand(["--questions=@\(path)"], files: [path: "A"]) == items(["A"]))
    }

    @Test("A value without @ is the text itself, and messages name it --questions")
    func inlineText() throws {
        #expect(
            try expand(["--questions", #""Q one" --yes y"#]) == items(["Q one", "--yes", "y"])
        )
        #expect(
            throws: ConfigError(
                path: "--questions",
                line: 1,
                problem: "a question file starts with a question, not a flag"
            )
        ) {
            try expand(["--questions=--model x"])
        }
    }

    @Test("A line with --help, -h, --version, or --set-config comes back as it is")
    func lineTakers() throws {
        for flag in ["--help", "-h", "--version", "--set-config"] {
            let line = ["--questions", "@nope", flag]
            #expect(try expand(line) == items(line), "\(flag)")
        }
    }

    @Test("A missing file names the path")
    func missingFile() {
        #expect(throws: refused(line: 0, "no such file")) {
            try expand(["--questions", "@\(path)"])
        }
    }

    @Test("A file that does not read, or is not UTF-8, names the path")
    func unreadableFile() {
        #expect(throws: refused(line: 0, "cannot read the file")) {
            try expand(["--questions", "@\(path)"], failing: [path: .unreadable])
        }
        #expect(throws: refused(line: 0, "is not valid UTF-8")) {
            try expand(["--questions", "@\(path)"], failing: [path: .notUTF8])
        }
    }

    @Test("A file that starts with { is refused as JSON, at its line")
    func jsonFile() {
        #expect(throws: refused(line: 2, "JSON question files are not supported yet")) {
            try expand(["--questions", "@\(path)"], files: [path: "\n{\"questions\": []}\n"])
        }
    }

    @Test("A file that starts with a flag is refused at its line")
    func flagFirst() {
        #expect(throws: refused(line: 2, "a question file starts with a question, not a flag")) {
            try expand(["--questions", "@\(path)"], files: [path: "# team\n--option a\n"])
        }
    }

    @Test("A flag that is not a question flag is refused at its line, with no value")
    func disallowedFlags() {
        let cases: [(file: String, flag: String)] = [
            ("Q\n--context c", "--context"),
            ("Q\n--context=secret", "--context"),
            ("Q\n--questions @other", "--questions"),
            ("Q\n-q", "-q"),
            ("Q\n--model a:b", "--model"),
        ]
        for (file, flag) in cases {
            #expect(throws: refused(line: 2, "\(flag) is not allowed in a question file"), "\(file)") {
                try expand(["--questions", "@\(path)"], files: [path: file])
            }
        }
    }

    @Test("--stats and --distribution with a value are refused, and the value does not print")
    func bareFlagWithAValue() {
        for flag in ["--stats", "--distribution"] {
            #expect(throws: refused(line: 2, "\(flag) takes no value"), "\(flag)") {
                try expand(["--questions", "@\(path)"], files: [path: "Q\n\(flag)=secret"])
            }
        }
    }

    @Test("A value flag as the file's last token needs a value, so it never takes the line's next token")
    func valueFlagLast() {
        #expect(throws: refused(line: 2, "--yes needs a value")) {
            try expand(["--questions", "@\(path)", "-q"], files: [path: "\"Is it spam\"\n--yes\n"])
        }
        #expect(throws: refused(line: 3, "--option needs a value")) {
            try expand(["--questions", "@\(path)"], files: [path: "Q\n--option a\n--option"])
        }
    }

    @Test("No arguments is an error before any file is read")
    func noArguments() {
        #expect(throws: UsageError("no arguments given")) {
            try expand([])
        }
    }

    @Test("The token after a value flag is its value, even when it starts with -")
    func valueStartingWithADash() throws {
        let result = try expand(
            ["--questions", "@\(path)"], files: [path: "Q --option -1 --option=-2"]
        )
        #expect(result == items(["Q", "--option", "-1", "--option=-2"]))
    }

    @Test("--stats, --distribution, and --name pass in a file")
    func detailAndNameFlags() throws {
        let result = try expand(
            ["--questions", "@\(path)"],
            files: [path: "Q --stats --name x R --distribution --name=y --min-confidence 0.5"]
        )
        #expect(
            result
                == items([
                    "Q", "--stats", "--name", "x",
                    "R", "--distribution", "--name=y", "--min-confidence", "0.5",
                ])
        )
    }

    @Test("An empty file, or one of comments alone, adds nothing")
    func emptyFile() throws {
        for file in ["", "# nothing here\n"] {
            #expect(try expand(["A", "--questions", "@\(path)"], files: [path: file]) == items(["A"]))
        }
    }

    @Test("--questions @ names no file, and a bare --questions at the end needs a value")
    func missingValue() {
        #expect(throws: UsageError("--questions @ names no file")) {
            try expand(["A", "--questions", "@"])
        }
        #expect(throws: UsageError("--questions needs a value")) {
            try expand(["A", "--questions"])
        }
    }
}
