/// The `.decide/config` format: a subset of TOML, parsed by hand.
///
/// Every text this parser accepts is valid TOML 1.0, so a full parser can
/// replace it later without breaking a file. Where the tool refuses valid
/// TOML, the message says "not supported", not "invalid".
///
/// No message holds a value from the file. Messages name keys and constructs
/// only, so a key's value cannot land in a log.
public enum ConfigFile {
    /// The keys a file may set. They are the environment variable names, so
    /// a file reads as a slice of environment.
    public static let keys: [String] = [
        ModelConfiguration.modelVariable,
        ModelConfiguration.apiKeyVariable,
    ]

    /// Parses the text of a config file. Pure: no I/O. `path` only names the
    /// file in a message. Entries come back in file order.
    ///
    /// A line is blank, a comment, or `key = value` with an optional trailing
    /// comment. The key is bare: `A-Z a-z 0-9 _ -`, and one of `keys`. The
    /// value is a basic string with the escapes `\"`, `\\`, `\n`, `\t`, and
    /// `\r`, or a literal string with no escapes. A `#` inside quotes is part
    /// of the value. A control character anywhere but a tab is an error, in
    /// a comment as in a string. Everything else throws a `ConfigError` that
    /// names the file, the line, and the construct.
    public static func parse(_ text: String, path: String) throws(ConfigError) -> [Entry] {
        var entries: [Entry] = []
        var firstLine: [String: Int] = [:]
        for (offset, line) in lines(of: text).enumerated() {
            let number = offset + 1
            guard let entry = try parseLine(line, number: number, path: path) else { continue }
            if let first = firstLine[entry.key] {
                throw ConfigError(
                    path: path,
                    line: number,
                    problem: "\(entry.key) is set twice, first on line \(first)"
                )
            }
            // Only whitespace is empty too: every consumer trims, and a blank
            // value that got through would hide a farther file's real one
            // with a message that names no file.
            guard !entry.value.allSatisfy(\.isWhitespace) else {
                throw ConfigError(path: path, line: number, problem: "\(entry.key) is empty")
            }
            firstLine[entry.key] = number
            entries.append(entry)
        }
        return entries
    }

    /// Sets keys in the text of a config file and keeps every other byte.
    /// Pure: no I/O. `path` only names the file in a message.
    ///
    /// A key that has a line keeps that line: the key's spelling, the spacing
    /// around the `=`, a trailing comment, and the line's own ending. Only the
    /// value changes. A key that has no line is appended as `KEY = "value"`,
    /// after a line break when the text lacks one at its end. Comments, blank
    /// lines, and a leading byte order mark stay where they are. The same key
    /// twice in one call leaves the last value on one line.
    ///
    /// The value becomes a basic string, so `"`, `\`, a newline, a tab, and a
    /// carriage return are escaped. Any other control character is refused, as
    /// are an empty or whitespace-only value and a key that is not one of
    /// `keys`. A file that does not parse is refused with its line, and the
    /// user fixes it by hand. No message holds a value.
    public static func setting(
        _ pairs: [(key: String, value: String)],
        in text: String,
        path: String
    ) throws(ConfigError) -> String {
        var lineOf: [String: Int] = [:]
        for entry in try parse(text, path: path) { lineOf[entry.key] = entry.line - 1 }
        var lines = splitLines(of: text)
        // An appended line takes the text's last ending, or "\n" when it has
        // none, so a file of CRLF lines stays a file of CRLF lines.
        let ending = lines.last(where: { !$0.ending.isEmpty })?.ending ?? "\n"
        for pair in pairs {
            try check(key: pair.key, path: path)
            try check(value: pair.value, of: pair.key, path: path)
            let encoded = basicString(encoding: pair.value)
            if let index = lineOf[pair.key] {
                try replace(encoded, on: &lines[index].body, number: index + 1, path: path)
            } else {
                lineOf[pair.key] = append("\(pair.key) = \(encoded)", to: &lines, ending: ending)
            }
        }
        let result = lines.map { String(String.UnicodeScalarView($0.body)) + $0.ending }.joined()
        _ = try parse(result, path: path)
        return result
    }

    /// What an unknown key reports. The writer uses the same wording.
    static func unknownKeyProblem(_ key: String) -> String {
        "unknown key \"\(key)\"; the keys are \(keys.joined(separator: " and "))"
    }

    /// What a line the parser cannot read as `key = "value"` reports.
    private static let shapeProblem = "expected key = \"value\""

    /// What a value that is not a quoted string reports.
    private static let quotedValueProblem = """
        value must be a quoted string, for example \
        \(ModelConfiguration.modelVariable) = "typesafe:jev-latest"
        """

    /// Splits the text into lines that keep their own ending: "\r\n", "\n", or
    /// "" for a last line with no break. Joining every body to its ending
    /// gives the text back, byte for byte, which is how an edit leaves the
    /// lines it does not touch. A carriage return with no line feed after it
    /// stays in the body, as TOML says, and the line it is on fails. Scalars,
    /// not characters, because a CRLF is one character and a combining mark
    /// joins the one before it. There is always at least one line.
    private static func splitLines(
        of text: String
    ) -> [(body: [Unicode.Scalar], ending: String)] {
        var lines: [(body: [Unicode.Scalar], ending: String)] = []
        var current: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars {
            guard scalar == "\n" else {
                current.append(scalar)
                continue
            }
            var ending = "\n"
            if current.last == "\r" {
                current.removeLast()
                ending = "\r\n"
            }
            lines.append((current, ending))
            current = []
        }
        lines.append((current, ""))
        return lines
    }

    /// The lines without what belongs to no line: the line break itself, the
    /// carriage return before a line feed, and a BOM at the start of the file.
    /// The editor works on `splitLines`, so a BOM survives an edit.
    private static func lines(of text: String) -> [[Unicode.Scalar]] {
        var bodies = splitLines(of: text).map(\.body)
        if bodies[0].first == "\u{FEFF}" { bodies[0].removeFirst() }
        return bodies
    }

    /// Reads one line. Gives the entry it sets, or nil when the line is blank
    /// or a comment. Judges the line on its own shape first, so a broken line
    /// reports its construct before any rule about keys.
    private static func parseLine(
        _ line: [Unicode.Scalar],
        number: Int,
        path: String
    ) throws(ConfigError) -> Entry? {
        func fail(_ problem: String) -> ConfigError {
            ConfigError(path: path, line: number, problem: problem)
        }

        let start = skippingBlanks(line, from: 0)
        guard start < line.count else { return nil }
        switch line[start] {
        case "#":
            try comment(line, from: start, number: number, path: path)
            return nil
        case "[": throw fail("tables are not supported")
        case "\"", "'": throw fail("quoted keys are not supported")
        default: break
        }

        guard let equals = line[start...].firstIndex(of: "=") else { throw fail(shapeProblem) }
        let key = trimmingBlanks(Array(line[start..<equals]))
        guard !key.contains(".") else { throw fail("dotted keys are not supported") }
        guard !key.isEmpty, key.allSatisfy(isKeyScalar) else { throw fail(shapeProblem) }
        let name = String(String.UnicodeScalarView(key))
        guard keys.contains(name) else { throw fail(unknownKeyProblem(name)) }

        let read = try parseValue(line, from: equals + 1, number: number, path: path)
        return Entry(key: name, value: read.value, line: number)
    }

    /// Reads the value after the `=`, then what may follow it: blanks, and
    /// either the end of the line or a comment. A comment needs no space
    /// before its `#`, as in TOML. Gives the value's span as well, `start` on
    /// the opening quote and `end` after the closing one, which the editor
    /// replaces and `parseLine` ignores.
    private static func parseValue(
        _ line: [Unicode.Scalar],
        from position: Int,
        number: Int,
        path: String
    ) throws(ConfigError) -> (value: String, start: Int, end: Int) {
        func fail(_ problem: String) -> ConfigError {
            ConfigError(path: path, line: number, problem: problem)
        }

        let start = skippingBlanks(line, from: position)
        guard start < line.count else { throw fail(quotedValueProblem) }
        let first = line[start]
        if first == "\"" || first == "'", start + 2 < line.count {
            if line[start + 1] == first, line[start + 2] == first {
                throw fail("multi-line strings are not supported")
            }
        }

        let read: (value: String, next: Int)
        switch first {
        case "\"": read = try basicString(line, from: start, number: number, path: path)
        case "'": read = try literalString(line, from: start, number: number, path: path)
        case "[": throw fail("arrays are not supported")
        case "{": throw fail("inline tables are not supported")
        default: throw fail(quotedValueProblem)
        }

        let rest = skippingBlanks(line, from: read.next)
        guard rest == line.count || line[rest] == "#" else { throw fail("text after the value") }
        if rest < line.count { try comment(line, from: rest, number: number, path: path) }
        return (read.value, start, read.next)
    }

    /// Checks a comment, which starts at `position` with its `#`. TOML
    /// forbids control characters in a comment as it does in a string.
    private static func comment(
        _ line: [Unicode.Scalar],
        from position: Int,
        number: Int,
        path: String
    ) throws(ConfigError) {
        guard !line[position...].contains(where: isControl) else {
            throw ConfigError(path: path, line: number, problem: "control character in a comment")
        }
    }

    /// Reads a basic string. `position` is its opening quote. Gives the
    /// decoded value and the position after the closing quote.
    private static func basicString(
        _ line: [Unicode.Scalar],
        from position: Int,
        number: Int,
        path: String
    ) throws(ConfigError) -> (value: String, next: Int) {
        func fail(_ problem: String) -> ConfigError {
            ConfigError(path: path, line: number, problem: problem)
        }

        var value = String.UnicodeScalarView()
        var index = position + 1
        while index < line.count {
            let scalar = line[index]
            if scalar == "\"" { return (String(value), index + 1) }
            if scalar == "\\" {
                guard index + 1 < line.count else { throw fail("unterminated string") }
                let escaped = line[index + 1]
                guard !isControl(escaped) else { throw fail("control character in the value") }
                switch escaped {
                case "\"": value.append("\"")
                case "\\": value.append("\\")
                case "n": value.append("\n")
                case "t": value.append("\t")
                case "r": value.append("\r")
                default: throw fail("unsupported escape \\\(escaped)")
                }
                index += 2
                continue
            }
            guard !isControl(scalar) else { throw fail("control character in the value") }
            value.append(scalar)
            index += 1
        }
        throw fail("unterminated string")
    }

    /// Reads a literal string. `position` is its opening quote. It has no
    /// escapes, so a backslash is itself.
    private static func literalString(
        _ line: [Unicode.Scalar],
        from position: Int,
        number: Int,
        path: String
    ) throws(ConfigError) -> (value: String, next: Int) {
        func fail(_ problem: String) -> ConfigError {
            ConfigError(path: path, line: number, problem: problem)
        }

        var value = String.UnicodeScalarView()
        var index = position + 1
        while index < line.count {
            let scalar = line[index]
            if scalar == "'" { return (String(value), index + 1) }
            guard !isControl(scalar) else { throw fail("control character in the value") }
            value.append(scalar)
            index += 1
        }
        throw fail("unterminated string")
    }

    /// Refuses a key no file may hold. A key that could be bare is named, as
    /// the parser names it; any other key is not, so no message can carry
    /// arbitrary text from a caller.
    private static func check(key: String, path: String) throws(ConfigError) {
        guard !keys.contains(key) else { return }
        let scalars = key.unicodeScalars
        guard !scalars.isEmpty, scalars.allSatisfy(isKeyScalar) else {
            throw ConfigError(path: path, line: 0, problem: "the key is not a bare key")
        }
        throw ConfigError(path: path, line: 0, problem: unknownKeyProblem(key))
    }

    /// Refuses a value no file may hold: one the parser would call empty, and
    /// one holding a control character the escapes do not cover. Line 0,
    /// because the value comes from the caller and not from a line.
    private static func check(value: String, of key: String, path: String) throws(ConfigError) {
        guard !value.allSatisfy(\.isWhitespace) else {
            throw ConfigError(path: path, line: 0, problem: "\(key) is empty")
        }
        let escaped: Set<Unicode.Scalar> = ["\n", "\r"]
        let raw = value.unicodeScalars.contains { isControl($0) && !escaped.contains($0) }
        guard !raw else {
            throw ConfigError(path: path, line: 0, problem: "value has a control character")
        }
    }

    /// The value as a basic string, quoted, with the five escapes of the
    /// subset. The caller refuses any other control character first.
    private static func basicString(encoding value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    /// Puts the encoded value on a line that already parsed, in place of the
    /// value there. Everything else on the line stays: the key, the spacing
    /// around the `=`, a BOM before the key, and a trailing comment.
    private static func replace(
        _ encoded: String,
        on line: inout [Unicode.Scalar],
        number: Int,
        path: String
    ) throws(ConfigError) {
        let start = skippingBlanks(line, from: 0)
        guard let equals = line[start...].firstIndex(of: "=") else {
            throw ConfigError(path: path, line: number, problem: shapeProblem)
        }
        let read = try parseValue(line, from: equals + 1, number: number, path: path)
        line.replaceSubrange(read.start..<read.end, with: encoded.unicodeScalars)
    }

    /// Adds a line at the end and gives its index. Ends the line before it
    /// first when that line has no ending of its own, so a text with no final
    /// break gets one; an empty text has an empty last line and takes no
    /// blank line.
    private static func append(
        _ line: String,
        to lines: inout [(body: [Unicode.Scalar], ending: String)],
        ending: String
    ) -> Int {
        let last = lines.count - 1
        if !lines[last].body.isEmpty, lines[last].ending.isEmpty { lines[last].ending = ending }
        lines.append((Array(line.unicodeScalars), ending))
        return lines.count - 1
    }

    /// The first position from `position` that holds neither a space nor a
    /// tab. Whitespace is space and tab only, as in TOML.
    private static func skippingBlanks(_ line: [Unicode.Scalar], from position: Int) -> Int {
        var index = position
        while index < line.count, line[index] == " " || line[index] == "\t" { index += 1 }
        return index
    }

    /// The scalars with the spaces and tabs at both ends removed.
    private static func trimmingBlanks(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var result = scalars
        while let last = result.last, last == " " || last == "\t" { result.removeLast() }
        while let first = result.first, first == " " || first == "\t" { result.removeFirst() }
        return result
    }

    /// Whether the scalar may be in a bare key.
    private static func isKeyScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9", "_", "-": true
        default: false
        }
    }

    /// Whether TOML forbids the scalar in a string. Tab is allowed.
    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x08, 0x0A...0x1F, 0x7F: true
        default: false
        }
    }
}

/// One `key = "value"` line, and where it is.
public struct Entry: Equatable, Sendable {
    /// The key, one of `ConfigFile.keys`.
    public let key: String
    /// The value, with the escapes of a basic string decoded. Not trimmed;
    /// `ModelConfiguration` trims later.
    public let value: String
    /// The 1-based line the entry is on, so a later message can name it.
    public let line: Int

    public init(key: String, value: String, line: Int) {
        self.key = key
        self.value = value
        self.line = line
    }
}

/// A file the tool reads and cannot use: a config file or a question file.
/// The message carries no "Error: " prefix; `ExitCode` adds it with the path
/// and the line.
public struct ConfigError: Error, Equatable, Sendable {
    /// The file the problem is in.
    public let path: String
    /// The 1-based line the problem is on. 0 means the whole file.
    public let line: Int
    /// What is wrong, in one clause. It never holds a value from the file.
    public let problem: String

    public init(path: String, line: Int, problem: String) {
        self.path = path
        self.line = line
        self.problem = problem
    }
}
