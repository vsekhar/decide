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
    /// A bare token starts a question. Each later `--option` or `--level`
    /// joins that question and sets its kind. A question with neither is a
    /// yes/no question; `--yes` and `--no` set what it prints. `--help` or
    /// `-h` anywhere returns `.help`. Anything the tool cannot run throws a
    /// `UsageError` that names the problem.
    public static func parse(_ arguments: [String]) throws(UsageError) -> ParseResult {
        guard !arguments.isEmpty else { throw UsageError("no arguments given") }
        if arguments.contains(where: { $0 == "--help" || $0 == "-h" }) { return .help }

        var context: ContextSource?
        var questions: [QuestionBuilder] = []
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
                try add(value, as: .option, to: &questions)
                continue
            }

            if let value = try flagValue(of: "--level", token: token, arguments: arguments, index: &index) {
                try add(value, as: .level, to: &questions)
                continue
            }

            if let value = try flagValue(of: "--yes", token: token, arguments: arguments, index: &index) {
                try add(value, as: .yes, to: &questions)
                continue
            }

            if let value = try flagValue(of: "--no", token: token, arguments: arguments, index: &index) {
                try add(value, as: .no, to: &questions)
                continue
            }

            if token.hasPrefix("-") { throw UsageError("unknown flag: \(token)") }

            guard !token.isEmpty else { throw UsageError("question \(questions.count + 1) is empty") }
            questions.append(QuestionBuilder(instructions: token))
        }

        guard let context else { throw UsageError("no --context given") }
        guard !questions.isEmpty else { throw UsageError("no question given") }

        var finished: [Question] = []
        for (offset, builder) in questions.enumerated() {
            let question = try builder.question(number: offset + 1)
            finished.append(question)
        }

        return .run(Invocation(context: context, questions: finished))
    }

    /// One question as the parser builds it. `flag` is the first kind flag
    /// under it, and stays `nil` until one arrives. `yes` and `no` hold the
    /// two sides of a yes/no question in any order, so a repeat of either flag
    /// is its own error.
    private struct QuestionBuilder {
        let instructions: String
        var flag: KindFlag?
        var values: [Option] = []
        var yes: Option?
        var no: Option?

        /// How a message names this question: its number and its text.
        func name(_ number: Int) -> String {
            "question \(number) (\"\(instructions)\")"
        }

        /// The finished question. A question with no kind flag is a yes/no
        /// question. Throws when its flags do not make one.
        func question(number: Int) throws(UsageError) -> Question {
            guard let flag else { return try verdict(number: number) }
            var seen: Set<String> = []
            for value in values {
                guard seen.insert(value.id).inserted else {
                    throw UsageError("\(name(number)) repeats the \(flag.noun) \"\(value.id)\"")
                }
            }
            switch flag {
            case .option:
                return Question(instructions: instructions, kind: .choice(values))
            case .level:
                guard values.count >= 2 else {
                    throw UsageError("\(name(number)) needs at least two --level")
                }
                return Question(instructions: instructions, kind: .rating(values))
            case .yes, .no:
                return try verdict(number: number)
            }
        }

        /// The finished yes/no question. A side the user left out takes its
        /// default value. Throws when the two sides print the same value,
        /// which would make the two probabilities one.
        private func verdict(number: Int) throws(UsageError) -> Question {
            let yesSide = yes ?? Option(id: "yes")
            let noSide = no ?? Option(id: "no")
            guard yesSide.id != noSide.id else {
                throw UsageError("\(name(number)) uses the same value for --yes and --no")
            }
            return Question(
                instructions: instructions, kind: .verdict(yes: yesSide, no: noSide)
            )
        }
    }

    /// A flag that belongs to a question. `--option` makes a choice,
    /// `--level` makes a rating, and `--yes` or `--no` decorates a yes/no
    /// question.
    private enum KindFlag: String {
        case option = "--option"
        case level = "--level"
        case yes = "--yes"
        case no = "--no"

        /// The kind a flag makes. The mixed-kinds check compares groups, so
        /// `--yes` and `--no` go on one question.
        enum Group {
            case choice
            case rating
            case verdict
        }

        /// The kind this flag makes.
        var group: Group {
            switch self {
            case .option: .choice
            case .level: .rating
            case .yes, .no: .verdict
            }
        }

        /// What the flag adds to a question, for a message about one repeated
        /// value. A yes/no question holds one value per side, so a repeat of
        /// `--yes` or `--no` is its own error and never reads this.
        var noun: String {
            switch self {
            case .option: "option"
            case .level: "level"
            case .yes, .no: "value"
            }
        }

        /// What an empty value, or one with nothing before the `=`, reports.
        /// The wording differs by flag, so the whole sentence lives here.
        var missingID: String {
            switch self {
            case .option: "an --option has no id"
            case .level: "a --level has no id"
            case .yes: "a --yes has no value"
            case .no: "a --no has no value"
            }
        }
    }

    /// Adds an option, a level, or a yes or no side to the last question. The
    /// first kind flag fixes the kind, so a flag of another kind is an error.
    /// Each question takes `--yes` once and `--no` once.
    private static func add(
        _ value: String,
        as flag: KindFlag,
        to questions: inout [QuestionBuilder]
    ) throws(UsageError) {
        guard let last = questions.indices.last else {
            throw UsageError("\(flag.rawValue) before any question")
        }
        if let existing = questions[last].flag, existing.group != flag.group {
            throw UsageError(
                "\(questions[last].name(last + 1)) mixes \(existing.rawValue) and \(flag.rawValue)"
            )
        }
        let parsed = try option(from: value, as: flag)
        switch flag {
        case .option, .level:
            questions[last].values.append(parsed)
        case .yes:
            guard questions[last].yes == nil else {
                throw UsageError("\(questions[last].name(last + 1)) repeats --yes")
            }
            questions[last].yes = parsed
        case .no:
            guard questions[last].no == nil else {
                throw UsageError("\(questions[last].name(last + 1)) repeats --no")
            }
            questions[last].no = parsed
        }
        if questions[last].flag == nil { questions[last].flag = flag }
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

    /// Reads an `--option`, `--level`, `--yes`, or `--no` value. The first
    /// `=` splits the id from the description. An empty description counts as
    /// none.
    private static func option(from value: String, as flag: KindFlag) throws(UsageError) -> Option {
        guard let separator = value.firstIndex(of: "=") else {
            guard !value.isEmpty else { throw UsageError(flag.missingID) }
            return Option(id: value)
        }
        let id = String(value[value.startIndex..<separator])
        guard !id.isEmpty else { throw UsageError(flag.missingID) }
        let description = String(value[value.index(after: separator)...])
        return Option(id: id, description: description.isEmpty ? nil : description)
    }
}
