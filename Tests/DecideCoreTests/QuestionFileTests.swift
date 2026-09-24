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
