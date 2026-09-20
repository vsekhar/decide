/// What the command line asks for: help, or one run.
public enum ParseResult: Equatable, Sendable {
    case help
    case run(Invocation)
}

/// Turns the argument list (after the program name) into an `Invocation`.
/// Pure: no file or network I/O.
public enum CommandLineParser {
    /// Parses the arguments.
    ///
    /// A bare token starts a question. Each later `--option` joins that
    /// question. `--help` or `-h` anywhere returns `.help`. Anything the tool
    /// cannot run throws a `UsageError` that names the problem.
    public static func parse(_ arguments: [String]) throws(UsageError) -> ParseResult {
        guard !arguments.isEmpty else { throw UsageError("no arguments given") }
        if arguments.contains(where: { $0 == "--help" || $0 == "-h" }) { return .help }

        var context: ContextSource?
        var questions: [Question] = []
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            index += 1

            if let value = try flagValue(of: "--context", token: token, arguments: arguments, index: &index) {
                guard context == nil else { throw UsageError("--context was given twice") }
                context = try contextSource(from: value)
                continue
            }

            if let value = try flagValue(of: "--option", token: token, arguments: arguments, index: &index) {
                guard !questions.isEmpty else { throw UsageError("--option before any question") }
                let parsed = try option(from: value)
                questions[questions.count - 1].options.append(parsed)
                continue
            }

            if token.hasPrefix("-") { throw UsageError("unknown flag: \(token)") }

            guard !token.isEmpty else { throw UsageError("question \(questions.count + 1) is empty") }
            questions.append(Question(instructions: token))
        }

        guard let context else { throw UsageError("no --context given") }
        guard !questions.isEmpty else { throw UsageError("no question given") }

        for (offset, question) in questions.enumerated() {
            let name = "question \(offset + 1) (\"\(question.instructions)\")"
            guard !question.options.isEmpty else { throw UsageError("\(name) has no --option") }
            var seen: Set<String> = []
            for option in question.options {
                guard seen.insert(option.id).inserted else {
                    throw UsageError("\(name) repeats the option \"\(option.id)\"")
                }
            }
        }

        return .run(Invocation(context: context, questions: questions))
    }

    /// Reads the value of a flag that takes one. Returns `nil` when the token
    /// is some other flag or a bare word. Accepts `--flag value` and
    /// `--flag=value`, and steps the index past a value it consumes.
    private static func flagValue(
        of flag: String,
        token: String,
        arguments: [String],
        index: inout Int
    ) throws(UsageError) -> String? {
        if token == flag {
            guard index < arguments.count else { throw UsageError("\(flag) needs a value") }
            let value = arguments[index]
            index += 1
            return value
        }
        if token.hasPrefix(flag + "=") { return String(token.dropFirst(flag.count + 1)) }
        return nil
    }

    /// Reads a `--context` value. A leading `@` names a file. Anything else is
    /// the text itself, and a later `@` stays literal.
    private static func contextSource(from value: String) throws(UsageError) -> ContextSource {
        guard value.hasPrefix("@") else { return .text(value) }
        let path = String(value.dropFirst())
        guard !path.isEmpty else { throw UsageError("--context @ names no file") }
        return .file(path)
    }

    /// Reads an `--option` value. The first `=` splits the id from the
    /// description. An empty description counts as none.
    private static func option(from value: String) throws(UsageError) -> Option {
        guard let separator = value.firstIndex(of: "=") else {
            guard !value.isEmpty else { throw UsageError("an --option has no id") }
            return Option(id: value)
        }
        let id = String(value[value.startIndex..<separator])
        guard !id.isEmpty else { throw UsageError("an --option has no id") }
        let description = String(value[value.index(after: separator)...])
        return Option(id: id, description: description.isEmpty ? nil : description)
    }
}
