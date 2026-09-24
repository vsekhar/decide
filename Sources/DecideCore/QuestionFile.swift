/// The text question file format: tokens split as a shell splits a command
/// line, plus `#` comments.
///
/// No message holds text from the file, only the path and the line.
public enum QuestionFile {
    /// Splits the text of a question file into tokens. Pure: no I/O. `path`
    /// only names the file in a message. Tokens come back in file order.
    ///
    /// Space, tab, carriage return, and line feed outside quotes separate
    /// tokens. A BOM at the start of the text is dropped. A `#` where a token
    /// would start begins a comment that runs to the end of the line; a `#`
    /// inside a word is itself. `'...'` keeps every scalar up to the next
    /// `'`. `"..."` keeps every scalar up to the next unescaped `"`, where
    /// `\"` gives `"`, `\\` gives `\`, and any other backslash pair stays as
    /// typed. Quotes may span lines, and join with the text around them, so
    /// `a="b c"` is one token. `""` alone is an empty token. A backslash
    /// outside quotes is itself, and nothing is expanded. The only error is
    /// a quote with no end, which names the line the quote opens on.
    public static func tokens(of text: String, path: String) throws(ConfigError) -> [Token] {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }

        var tokens: [Token] = []
        var current: String.UnicodeScalarView?
        var start = 0
        var line = 1
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if isSeparator(scalar) {
                if let text = current { tokens.append(Token(text: String(text), line: start)) }
                current = nil
                if scalar == "\n" { line += 1 }
                index += 1
                continue
            }
            if current == nil {
                if scalar == "#" {
                    while index < scalars.count, scalars[index] != "\n" { index += 1 }
                    continue
                }
                current = String.UnicodeScalarView()
                start = line
            }
            switch scalar {
            case "'", "\"":
                let opening = line
                index += 1
                var closed = false
                while index < scalars.count {
                    let inner = scalars[index]
                    if inner == scalar {
                        closed = true
                        index += 1
                        break
                    }
                    if inner == "\n" { line += 1 }
                    if scalar == "\"", inner == "\\", index + 1 < scalars.count {
                        let next = scalars[index + 1]
                        if next == "\"" || next == "\\" {
                            current?.append(next)
                            index += 2
                            continue
                        }
                    }
                    current?.append(inner)
                    index += 1
                }
                guard closed else {
                    throw ConfigError(path: path, line: opening, problem: "unterminated quote")
                }
            default:
                current?.append(scalar)
                index += 1
            }
        }
        if let text = current { tokens.append(Token(text: String(text), line: start)) }
        return tokens
    }

    /// Whether the scalar separates tokens outside quotes.
    private static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\r" || scalar == "\n"
    }

    /// One token of a question file, and where it starts.
    public struct Token: Equatable, Sendable {
        /// The text, with its quotes removed and its escapes decoded.
        public let text: String
        /// The 1-based line the token starts on, so a caller can name the
        /// line of a token it refuses.
        public let line: Int

        public init(text: String, line: Int) {
            self.text = text
            self.line = line
        }
    }
}
