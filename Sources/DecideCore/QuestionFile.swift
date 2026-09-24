/// The question files `--questions` reads. A text whose first mark after a
/// BOM and whitespace is `{` or `[` is a JSON question file, which
/// `JSONQuestionFile` decodes, refusing a top-level array. Anything else is
/// the text format: tokens split as a shell splits a command line, plus `#`
/// comments.
///
/// No message about a text file holds text from the file, only the path,
/// the line, and the name of a flag the file may not hold.
public enum QuestionFile {
    /// One part of the command line after `--questions` expands.
    public enum Item: Equatable, Sendable {
        /// One argument, from the line or from a question file.
        case token(String)
        /// Finished questions, which take the item's place among the
        /// questions on the line.
        case questions([Question])
    }

    /// Replaces each `--questions` value on the line with the questions it
    /// holds, so they take the flag's place. Every other argument passes
    /// through as it is.
    ///
    /// A value `@<path>` names a file, which `read` gives, or nil when there
    /// is no file. Any other value is the text itself, and messages name it
    /// `--questions`. A line with `--version`, `--help`, `-h`, or
    /// `--set-config` comes back as it is, and no file is read.
    ///
    /// A text that starts with `{` or `[`, after a BOM and whitespace, is a
    /// JSON question file: its questions take the flag's place finished, as
    /// one `.questions` item. Any other text is the text format: its tokens
    /// take the flag's place. A text file starts with a question, and holds
    /// only question flags. Throws a `UsageError` for no arguments or a
    /// `--questions` with no value or no path, and a `ConfigError` that
    /// names the file for a file that is missing, does not read, or holds
    /// what the rules refuse.
    public static func expanding(
        _ arguments: [String],
        read: (String) throws(ConfigReadError) -> String?
    ) throws -> [Item] {
        guard !arguments.isEmpty else { throw UsageError("no arguments given") }
        guard !CommandLineParser.takesTheLine(arguments) else { return arguments.map(Item.token) }
        var items: [Item] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            guard let value = try CommandLineParser.flagValue(
                of: "--questions", token: argument, arguments: arguments, index: &index
            ) else {
                items.append(.token(argument))
                continue
            }
            let (text, path) = try source(of: value, read: read)
            if isJSON(text) {
                items.append(.questions(try JSONQuestionFile.questions(from: text, path: path)))
                continue
            }
            let tokens = try tokens(of: text, path: path)
            try check(tokens, path: path)
            items.append(contentsOf: tokens.map { .token($0.text) })
        }
        return items
    }

    /// Whether the text is a JSON question file: its first scalar after a
    /// BOM and whitespace is `{` or `[`. The decoder refuses a top-level
    /// array with its own message.
    private static func isJSON(_ text: String) -> Bool {
        var scalars = text.unicodeScalars[...]
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        let first = scalars.first { !isSeparator($0) }
        return first == "{" || first == "["
    }

    /// The flags a file may hold that take a value, as `--flag value` or
    /// `--flag=value`.
    private static let valueFlags = [
        "--option", "--level", "--yes", "--no", "--min-confidence", "--fallback", "--name",
    ]

    /// The flags a file may hold that take no value.
    private static let bareFlags = ["--stats", "--distribution"]

    /// The text of a `--questions` value, and the path its messages name.
    private static func source(
        of value: String,
        read: (String) throws(ConfigReadError) -> String?
    ) throws -> (text: String, path: String) {
        guard value.hasPrefix("@") else { return (value, "--questions") }
        let path = String(value.dropFirst())
        guard !path.isEmpty else { throw UsageError("--questions @ names no file") }
        let text: String?
        do {
            text = try read(path)
        } catch {
            throw ConfigFiles.error(error, at: path)
        }
        guard let text else { throw ConfigError(path: path, line: 0, problem: "no such file") }
        return (text, path)
    }

    /// Refuses a text question file that breaks its rules. The first token
    /// is a question, and one that starts with `{` or `[` is JSON that
    /// something, such as a comment line, kept the sniff from seeing. Every
    /// later token that starts with `-` is a question flag; the token after
    /// a value flag is its value, which may start with `-`. That value is in
    /// the file too, so a file's tokens never reach the line after it.
    private static func check(_ tokens: [Token], path: String) throws(ConfigError) {
        guard let first = tokens.first else { return }
        guard !first.text.hasPrefix("{"), !first.text.hasPrefix("[") else {
            throw ConfigError(
                path: path,
                line: first.line,
                problem: "a JSON question file starts with {, with nothing before it"
            )
        }
        guard !first.text.hasPrefix("-") else {
            throw ConfigError(
                path: path,
                line: first.line,
                problem: "a question file starts with a question, not a flag"
            )
        }
        var index = 1
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            guard token.text.hasPrefix("-") else { continue }
            if bareFlags.contains(token.text) { continue }
            if valueFlags.contains(token.text) {
                guard index < tokens.count else {
                    throw ConfigError(
                        path: path, line: token.line, problem: "\(token.text) needs a value"
                    )
                }
                index += 1
                continue
            }
            // Only the name before the `=` prints, never a value from the
            // file.
            let name = String(token.text.prefix { $0 != "=" })
            if name != token.text, valueFlags.contains(name) { continue }
            let problem = bareFlags.contains(name)
                ? "\(name) takes no value" : "\(name) is not allowed in a question file"
            throw ConfigError(path: path, line: token.line, problem: problem)
        }
    }

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
