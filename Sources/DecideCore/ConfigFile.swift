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
            guard !entry.value.isEmpty else {
                throw ConfigError(path: path, line: number, problem: "\(entry.key) is empty")
            }
            firstLine[entry.key] = number
            entries.append(entry)
        }
        return entries
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

    /// Splits the text into lines and drops what belongs to no line: the line
    /// break itself, the carriage return before a line feed, and a BOM at the
    /// start of the file. A carriage return with no line feed after it stays,
    /// as TOML says, and the line it is on fails. Scalars, not characters,
    /// because a CRLF is one character and a combining mark joins the one
    /// before it.
    private static func lines(of text: String) -> [[Unicode.Scalar]] {
        var rest = Substring(text).unicodeScalars
        if rest.first == "\u{FEFF}" { rest.removeFirst() }
        var lines: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        for scalar in rest {
            if scalar == "\n" {
                if current.last == "\r" { current.removeLast() }
                lines.append(current)
                current = []
            } else {
                current.append(scalar)
            }
        }
        lines.append(current)
        return lines
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

        let value = try parseValue(line, from: equals + 1, number: number, path: path)
        return Entry(key: name, value: value, line: number)
    }

    /// Reads the value after the `=`, then what may follow it: blanks, and
    /// either the end of the line or a comment. A comment needs no space
    /// before its `#`, as in TOML.
    private static func parseValue(
        _ line: [Unicode.Scalar],
        from position: Int,
        number: Int,
        path: String
    ) throws(ConfigError) -> String {
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
        return read.value
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

/// A config file the tool cannot use. The message carries no "Error: "
/// prefix; `ExitCode` adds it with the path and the line.
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
